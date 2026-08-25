data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name = "name"
    # AL2023 (kernel 6.1): cgroup v2 by default, required by modern k3s kubelet
    values = ["al2023-ami-2023*kernel-6.1-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Shared k3s cluster token. The control node installs the server with it and
# workers use it to join, so both can self-recover on reboot.
resource "random_string" "k3s_token" {
  length  = 32
  special = false
}

# Elastic IP for the control node. Ephemeral public IPs are released on
# stop/start, which would change the URL and invalidate the k3s server cert
# (SAN is pinned to the IP at first boot). An EIP stays put across
# stop/start and is free while attached to a running instance.
resource "aws_eip" "control" {
  domain = "vpc"

  tags = merge(local.tags, { Name = "${var.project_name}-control-eip" })
}

resource "aws_eip_association" "control" {
  instance_id   = aws_instance.control.id
  allocation_id = aws_eip.control.id
}

# Control-plane node: k3s server + rancher (installed later via
# bootstrap/setup-control-node.sh). Installs itself on first boot.
resource "aws_instance" "control" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.control.id]
  associate_public_ip_address = true
  key_name                    = var.ssh_key_name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    encrypted             = true
    delete_on_termination = true
  }

  user_data = <<-EOF
    #cloud-config
    hostname: ${var.project_name}-control
    runcmd:
      - if [ ! -f /swapfile ]; then fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile; fi
      - if [ "$(stat -fc %T /sys/fs/cgroup/)" != "cgroup2fs" ]; then grubby --update-kernel=ALL --args="systemd.unified_cgroup_hierarchy=1" && reboot; fi
      # seed the k3s server cert SANs with the public IP available at first
      # boot (ephemeral IP; the EIP is attached right after by terraform)
      - |
        set -eu
        IMDS_TOK=$(curl -s -X PUT -H "X-aws-ec2-metadata-token-ttl-seconds: 60" http://169.254.169.254/latest/api/token)
        PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOK" http://169.254.169.254/latest/meta-data/public-ipv4)
        if [ -n "$PUBLIC_IP" ]; then
          mkdir -p /etc/rancher/k3s
          printf 'tls-san:\n  - %s\n' "$PUBLIC_IP" > /etc/rancher/k3s/config.yaml
        fi
      # keep the server cert SANs in sync with the node's public IP (EIP).
      # Runs every 5 min; no-op unless the IP is missing from the SAN list,
      # in which case it adds it, re-issues the serving cert, and restarts
      # k3s once. Covers fresh boots before the EIP is attached and any
      # future EIP re-association.
      - |
        set -eu
        cat > /usr/local/bin/k3s-tls-san-sync.sh <<'EOS'
        #!/usr/bin/env bash
        set -eu
        CFG=/etc/rancher/k3s/config.yaml
        [ -f /var/lib/rancher/k3s/server/tls/serving-kube-apiserver.crt ] || exit 0
        IMDS_TOK=$(curl -s -X PUT -H "X-aws-ec2-metadata-token-ttl-seconds: 60" http://169.254.169.254/latest/api/token)
        IP=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOK" http://169.254.169.254/latest/meta-data/public-ipv4 || true)
        [ -n "$IP" ] || exit 0
        grep -qxF "  - $IP" "$CFG" 2>/dev/null && exit 0
        if [ -f "$CFG" ] && grep -qxF "tls-san:" "$CFG"; then
          printf '  - %s\n' "$IP" >> "$CFG"
        else
          printf 'tls-san:\n  - %s\n' "$IP" > "$CFG"
        fi
        rm -f /var/lib/rancher/k3s/server/tls/serving-kube-apiserver.crt /var/lib/rancher/k3s/server/tls/serving-kube-apiserver.key
        systemctl restart k3s
        EOS
        chmod +x /usr/local/bin/k3s-tls-san-sync.sh
        cat > /etc/systemd/system/k3s-tls-san-sync.service <<'EOS'
        [Unit]
        Description=Sync k3s API server cert SANs to the node public IP
        After=network-online.target

        [Service]
        Type=oneshot
        ExecStart=/usr/local/bin/k3s-tls-san-sync.sh
        EOS
        cat > /etc/systemd/system/k3s-tls-san-sync.timer <<'EOS'
        [Unit]
        Description=Run k3s-tls-san-sync periodically

        [Timer]
        OnBootSec=90
        OnUnitActiveSec=300

        [Install]
        WantedBy=timers.target
        EOS
        systemctl daemon-reload
        systemctl enable --now k3s-tls-san-sync.timer
      - curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_SELINUX_RPM=true K3S_TOKEN=${random_string.k3s_token.result} sh -s - server --disable traefik --disable servicelb --write-kubeconfig-mode 644
  EOF

  tags = merge(local.tags, { Name = "${var.project_name}-control" })

  lifecycle {
    ignore_changes = [ami]
  }
}

# Worker nodes auto-join the control plane on first boot (k3s agent retries
# until the server is up, so boot order does not matter).
resource "aws_instance" "worker" {
  count = var.worker_instance_count

  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.worker.id]
  associate_public_ip_address = true
  key_name                    = var.ssh_key_name

  depends_on = [aws_instance.control]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    encrypted             = true
    delete_on_termination = true
  }

  user_data = <<-EOF
    #cloud-config
    hostname: ${var.project_name}-worker-${count.index}
    runcmd:
      - if [ ! -f /swapfile ]; then fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile; fi
      - if [ "$(stat -fc %T /sys/fs/cgroup/)" != "cgroup2fs" ]; then grubby --update-kernel=ALL --args="systemd.unified_cgroup_hierarchy=1" && reboot; fi
      - curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_SELINUX_RPM=true K3S_URL=https://${aws_instance.control.private_ip}:6443 K3S_TOKEN=${random_string.k3s_token.result} sh -s - agent
  EOF

  tags = merge(local.tags, { Name = "${var.project_name}-worker-${count.index}" })

  lifecycle {
    ignore_changes = [ami]
  }
}
