# AWS.Deployment

Deploy a small full-stack app — **API + Next.js + PostgreSQL** — onto **AWS**, managed end to end with **Terraform** (infrastructure) and **Kubernetes manifests** (workloads). No domain in dev: the app is served plain-HTTP on the ALB's DNS name.

```
                 Internet
                    |
       ALB :80 (internet-facing, HTTP)
       created by the AWS Load Balancer
       Controller from k8s/ingress.yaml
                    |
             EKS Ingress
             /api/*  ->  API service
             /       ->  Next.js service
                    |
  EKS node group (private subnets, 3 AZs, no public IPs)
  +------------------+     +------------------+
  | Next.js pods     |     | API pods         |
  +------------------+     +------------------+
                                   |
                          RDS PostgreSQL
                          (Multi-AZ, private)
```

**Terraform owns the infrastructure** (VPC, subnets, NAT, EKS cluster + node group, RDS, IAM incl. the load-balancer-controller role and the GitHub OIDC role). **Kubernetes owns the workloads** (deployments, services, ingress, config, secrets, migrations job). The ALB is an AWS resource but it is created and managed by the controller in-cluster from the Ingress, so route changes are just manifest changes.

## Repo layout

```
terraform/
  modules/
    vpc/              VPC, 3 public + 3 private subnets, IGW, 1 NAT
    eks/              cluster, node group, addons, SGs, aws-auth,
                      ALB-controller IRSA role, GitHub OIDC role
    rds/              PostgreSQL instance, subnet group, SG
  environments/
    dev/              module wiring + per-env values (tfvars, gitignored)
bootstrap/
  setup-eks.sh        kubeconfig + wait nodes + helm install ALB controller
k8s/
  namespace.yaml
  secrets.yaml        template -> rendered by deploy.sh
  migrations-job.yaml one-shot dbup runner, re-run on upgrades
  api.yaml            deployment + service (AWSApi__* env vars, ALB healthcheck path)
  react.yaml          configmap (API_URL) + deployment + service
  ingress.yaml        ALB ingress: /api -> api, / -> react
  environments/
    dev.env.example        copy to dev.env: IMAGE_API_URL, RDS_ENDPOINT, DB_USER, tags
    dev.secrets.env.example  copy to dev.secrets.env: DB_PASSWORD, IMAGE_API_KEY
  deploy.sh               renders + applies everything in order
```

## Prerequisites

- AWS account + `aws` CLI credentials (or `terraform.tfvars` with `aws_profile`), plus `kubectl`
- Terraform >= 1.5 (CI uses a pinned docker image, no local install needed)
- the three images pushed to ghcr.io: `aws-api`, `aws-react`, `aws-db-migrations` (public, no registry secret needed)
- the React app reads `API_URL` from an env var at runtime (no per-env builds)

## Deploy (dev)

1. **Provision AWS** (takes ~15-20 min; see "Costs" below):

   ```sh
   cd terraform/environments/dev
   cp terraform.tfvars.example terraform.tfvars   # set db_master_password
   terraform init
   terraform apply
   ```

   `db_master_password` in `terraform.tfvars` MUST equal `DB_PASSWORD` in `k8s/environments/dev.secrets.env` (and the `DB_PASSWORD_DEV` GitHub secret for CD).

2. **Bootstrap the cluster** (kubeconfig + ALB load balancer controller):

   ```sh
   bash bootstrap/setup-eks.sh dev
   ```

3. **Fill env values**:

   ```sh
   cp k8s/environments/dev.env.example k8s/environments/dev.env
   #    IMAGE_API_URL=<image api host>, RDS_ENDPOINT=(terraform output -raw rds_endpoint),
   #    DB_USER=(terraform output -raw db_user)
   cp k8s/environments/dev.secrets.env.example k8s/environments/dev.secrets.env
   #    fill DB_PASSWORD= (same as terraform.tfvars) and IMAGE_API_KEY=
   ```

4. **Deploy**:

   ```sh
   cd k8s
   ./deploy.sh dev
   ```

   The script renders the placeholders, applies namespace → secrets → migrations job (against RDS) → api → react → ingress, and prints the ALB URL once the controller publishes it on the Ingress status.

5. **Validate**:

   ```sh
   curl http://<ALB-DNS>/api/    # api through the ALB
   curl http://<ALB-DNS>/        # Next.js through the ALB
   ```

## Deploy a new build (manual CD)

The app repos (`AWS.Api`, `AWS.React`) build and push their ghcr images on their own CI. To deploy the latest build to an environment you press a button — no tags to edit by hand:

1. GitHub → **Actions** → **Deploy** (`.github/workflows/cd.yml`) → choose `env` → **Run workflow**.
2. The workflow assumes the env's OIDC role, resolves the `sha7` of the app repos' `main` HEAD (or a specific `sha7` from the optional `api_tag` / `react_tag` fields, to pin or roll back), resolves the RDS endpoint/user via the aws CLI, renders the env files, and runs `k8s/deploy.sh <env>` against the EKS cluster.

Required per environment (repo settings → Secrets & variables → Actions):

| Type   | Name                  | Value                                                        |
| ------ | --------------------- | ------------------------------------------------------------ |
| Secret | `AWS_ROLE_ARN_DEV`    | `terraform output -raw cd_role_arn`                          |
| Secret | `DB_PASSWORD_DEV`     | RDS master password (must match `db_master_password` in tfvars) |
| Secret | `IMAGE_API_KEY_DEV`   | image API key for this env                                    |
| Var    | `IMAGE_API_URL_DEV`   | image API base URL for this env (e.g. the dev image-api host) |

No kubeconfig secret: kubectl uses `aws eks get-token` against the OIDC role.

## Run CI locally

The same checks that run in GitHub Actions also run in a docker container, so no local tooling is needed:

```sh
bash ci-docker.sh
```

Builds the `aws-deployment-ci` tools image once (terraform, shellcheck, python3, kubeconform), then runs `ci.sh` against the current working tree (mounted, so uncommitted changes count).

## Upgrade the app

Push to an app repo's `main` (its CI pushes the `sha7` + `latest` ghcr images), then Actions → **Deploy** with the env. The run deploys that commit's `sha7` and includes the migrations job + rolling the deployments. To pin or roll back, fill the `api_tag` / `react_tag` fields with a specific `sha7`.

## Destroy everything (after validation)

```sh
# optional: clean cluster first
kubectl -n app delete job migrations
kubectl delete ns app
cd terraform/environments/dev && terraform destroy
```

`terraform destroy` removes everything this config created (EKS, RDS, VPC, NAT, IAM). Nothing persists: the RDS snapshot is skipped and the dev DB is disposable (the migrations job rebuilds the schema on next deploy). Verify: `aws ec2 describe-instances --filters "tag:Project=aws-deployment"` and `aws eks list-clusters` return nothing for this project.

Re-deploying later is: `terraform apply` → `bootstrap/setup-eks.sh` → `k8s/deploy.sh`.

## Costs (us-east-1, approx)

| Resource                        | ~$/mo   | Notes                                        |
| ------------------------------- | ------- | -------------------------------------------- |
| EKS control plane               | 73      | fixed, as long as the cluster exists         |
| 3 x t3.medium workers (2 vCPU)  | ~90     | smallest EKS-supported type; 1 node = ~$30   |
| RDS db.t4g.micro Multi-AZ       | ~40     | single-AZ halves it                          |
| ALB                             | ~18-25  | + data transfer ~$0.09/GB                    |
| NAT gateway (1)                 | ~32     | + data ~$0.045/GB                            |
| 3 x 20GB gp3 node volumes       | ~5      |                                              |
| **Total (HA profile)**          | **~260**| 1-node / single-AZ-DB profile: ~$160         |

Cost knobs (`terraform/environments/dev/variables.tf`): `worker_desired_size`/`worker_min_size` (3 = one node per AZ), `worker_instance_types`, `db_instance_class`, `db_multi_az`.

## Known limitations (by design, for this phase)

- Plain HTTP, no domain/cert: the ALB listens on :80 only. When a domain exists, add an ACM cert + `listen-ports` HTTPS + a redirect (Ingress annotations).
- Single NAT gateway in one AZ (cheapest): an AZ outage affects new image pulls, not running pods. Add one NAT per AZ for full HA.
- The app connects to RDS as the master user (dev). Create a dedicated app user (and IAM auth) before prod.
- The RDS connection uses `SSL Mode=Require` with `Trust Server Certificate=true`: traffic is encrypted but the RDS CA is not pinned, so the server's identity is not verified (a MITM could present a fake cert). For prod, pin the RDS CA certificate and use `SSL Mode=Verify-Full`.
- Local Terraform state in the repo dir. Move to an S3 backend + DynamoDB lock before CI/CD runs `terraform apply` against prod.
- `worker_min_size` defaults to 1: set it to 3 (one per AZ) when the app needs real HA.
