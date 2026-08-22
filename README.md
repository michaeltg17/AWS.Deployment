# AWS.Deployment

Deploy a small full-stack app — **API + React + PostgreSQL** — onto **Kubernetes (k3s) on AWS EC2**, managed with **Rancher**. No load balancer / API gateway: ingress-nginx runs in hostNetwork mode on the nodes, so the app is served directly on the node IPs at `:80` (`:443` is mapped, TLS comes with a domain/cert later).

```
                Internet
                   |
        EC2 public IP (node)
                   |
         nginx-ingress (hostNetwork :80/:443, one per node)
          /api/*            /*
             |               |
          aws-api        aws-react
           (ghcr)         (ghcr)
             |
        postgres 18.6 (EBS PVC)
        migrations job (ghcr)
```

- **Terraform** provisions everything (VPC, subnet, SGs, 2 EC2 nodes). Every resource is tagged (`Project=aws-deployment`, `Environment=dev`, `ManagedBy=terraform`) so it is easy to find and delete — AWS has no resource groups, tags are the equivalent.
- **k3s** installs itself on the nodes via cloud-init (shared random token, so workers auto-join).
- **Rancher** is installed on the control node via Helm (NodePort :31591).
- **One image per app**: `ghcr.io/michaeltg17/aws-{api,react,db-migrations}:<sha7>`. Environments differ only by deploy-time values (`API_URL`, tags) in `k8s/environments/<env>.env` — no per-environment image builds.

## Repo layout

```
terraform/            IAC: VPC, SGs, EC2 (control + workers), tagged
bootstrap/
  setup-control-node.sh   helm + ingress-nginx + rancher (run once, on control node)
k8s/
  namespace.yaml
  secrets.yaml            template -> rendered by deploy.sh
  postgresql.yaml         statefulset + PVC + services
  migrations-job.yaml     one-shot dbup runner, re-run on upgrades
  api.yaml                deployment + service (AWSApi__* env vars)
  react.yaml              configmap (API_URL) + deployment + service
  ingress.yaml            /api -> api, / -> react
  environments/
    dev.env.example        copy to dev.env: domain, IMAGE_API_URL, API_URL, tags
    dev.secrets.env.example  copy to dev.secrets.env, fill secrets
  deploy.sh               renders + applies everything in order
```

## Prerequisites

- AWS account + `aws` CLI credentials (or `terraform.tfvars` with `aws_profile`)
- Terraform >= 1.5
- kubectl
- an SSH key (any)
- the three images pushed to ghcr.io: `aws-api`, `aws-react`, `aws-db-migrations` (public, no registry secret needed)
- the React app reads `API_URL` from an env var at runtime (no per-env builds)

## Deploy (dev)

1. **Provision AWS** (2 × t3.small, ~$0.04/h; free tier covers a few hours, and it costs nothing once destroyed):

   ```sh
   cd terraform
   cp terraform.tfvars.example terraform.tfvars   # adjust if needed
   terraform init
   terraform apply
   terraform output -raw control_public_ip        # -> $CTRL_IP
   ```

2. **Bootstrap the control node** (installs helm, ingress-nginx, rancher; prints URL + admin token):

    ```sh
    scp ../bootstrap/setup-control-node.sh ec2-user@$CTRL_IP:~/
    ssh ec2-user@$CTRL_IP 'sudo sh ~/setup-control-node.sh'
    ```

3. **Configure kubectl** (run from the repo root; Git Bash or WSL):

   ```sh
   scp ec2-user@$CTRL_IP:/etc/rancher/k3s/k3s.yaml .kubeconfig
   sed -i -e "s|127.0.0.1|$CTRL_IP|g" .kubeconfig
   export KUBECONFIG=$PWD/.kubeconfig
   kubectl get nodes        # 2 nodes = Ready
   ```

4. **Fill env values**:

    ```sh
    cp k8s/environments/dev.env.example k8s/environments/dev.env
    #    fill DOMAIN=$CTRL_IP and IMAGE_API_URL=(image API base URL for this env)
    cp k8s/environments/dev.secrets.env.example k8s/environments/dev.secrets.env
    #    fill DB_PASSWORD= and IMAGE_API_KEY=
    ```

5. **Deploy**:

   ```sh
   cd k8s
   ./deploy.sh dev
   ```

   The script renders the placeholders, applies namespace → secrets → postgresql → waits → migrations job → api → react → ingress, and waits for readiness.

6. **Validate**:

   ```sh
    curl http://$CTRL_IP/api/            # api through ingress (host :80)
    curl http://$CTRL_IP/                # react through ingress (host :80)
   ```

    Rancher dashboard: `http://$CTRL_IP:31591` (admin / token printed by step 2; add the cluster with a local kubeconfig import).

## Deploy a new build (manual CD)

The app repos (`AWS.Api`, `AWS.React`) build and push their ghcr images on their own CI. To deploy the latest `main` build to a cluster you press a button — no tags to edit by hand:

1. GitHub → **Actions** → **Deploy** (`.github/workflows/cd.yml`) → choose `env` → **Run workflow**.
2. The workflow resolves the `main` sha7 tags of the app repos, renders the env files, and runs `k8s/deploy.sh <env>` against the cluster from the kubeconfig secret.

Required per environment (repo settings → Secrets & variables → Actions):

| Type     | Name (dev)        | Value                                                                    |
| -------- | ----------------- | ------------------------------------------------------------------------ |
| Secret   | `KUBECONFIG_DEV`  | kubeconfig file content (created in step 3)                              |
| Secret   | `DB_PASSWORD_DEV` | PostgreSQL password — must match what the cluster was deployed with       |
| Secret   | `IMAGE_API_KEY_DEV` | image API key for this env                                              |
| Variable | `DOMAIN_DEV`      | cluster node public IP (or domain)                                        |
| Variable | `IMAGE_API_URL_DEV` | image API base URL for this env (e.g. the dev image-api host)           |

If you rebuild the cluster (terraform destroy/apply), regenerate `dev.secrets.env`, redeploy, and update `DB_PASSWORD_DEV`/`KUBECONFIG_DEV` again.

## Run CI locally

The same checks that run in GitHub Actions also run in a docker container, so no local tooling is needed:

```sh
bash ci-docker.sh
```

Builds the `aws-deployment-ci` tools image once (terraform, shellcheck, python3, kubeconform), then runs `ci.sh` against the current working tree (mounted, so uncommitted changes count).

## Upgrade the app

```sh
# new image tag in environments/<env>.env (API_IMAGE_TAG etc.), then:
kubectl -n app delete job migrations
./deploy.sh dev                        # re-runs migrations + rolls api/react
```

## Destroy everything (after validation)

```sh
# optional: clean cluster first
kubectl -n app delete job migrations
kubectl delete ns app
cd terraform && terraform destroy
```

`terraform destroy` removes only what this config created (EC2, EBS, VPC, SGs). Verify: `aws ec2 describe-instances --filters "tag:Project=aws-deployment"` returns none.

## Known limitations (by design, for this phase)

- Ingress-nginx runs `hostNetwork` (no load balancer): each node's host `:80`/`:443` is owned by the ingress controller, so nothing else may bind those ports on the nodes. Pod-level load balancing is still done by k8s (Services).

- Plain HTTP (no TLS) — no domain/cert yet; the ingress controller already owns node `:443`, TLS is a later step.
- `ssh_allowed_cidrs` / `app_allowed_cidrs` default to `0.0.0.0/0` — lock down before leaving dev.
- Single-AZ, no HA (one control node). Fine for validation; bump `worker_instance_count` / add nodes later.
- PostgreSQL is a single-node StatefulSet on `local-path` storage (fits in the 20GB root EBS). Swap for a managed PG or RWO EBS PVC before prod.
