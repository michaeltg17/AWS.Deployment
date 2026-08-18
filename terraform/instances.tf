data "aws_ami" "al2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
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

# Control-plane node: k3s server + rancher (installed later via
# bootstrap/setup-control-node.sh). Installs itself on first boot.
resource "aws_instance" "control" {
  ami                         = data.aws_ami.al2.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.control.id]
  associate_public_ip_address = true

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
      - curl -sfL https://get.k3s.io | K3S_TOKEN=${random_string.k3s_token.result} sh -s - server --disable traefik --disable servicelb --write-kubeconfig-mode 644
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

  ami                         = data.aws_ami.al2.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.worker.id]
  associate_public_ip_address = true

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
      - curl -sfL https://get.k3s.io | K3S_URL=https://${aws_instance.control.public_ip} K3S_TOKEN=${random_string.k3s_token.result} sh -s - agent
  EOF

  tags = merge(local.tags, { Name = "${var.project_name}-worker-${count.index}" })

  lifecycle {
    ignore_changes = [ami]
  }
}
