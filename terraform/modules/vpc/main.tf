locals {
  # one subnet per AZ, in AZ order
  azs = slice(sort(data.aws_availability_zones.available.names), 0, length(var.public_subnet_cidrs))

  tags = var.tags
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = "${var.name}-vpc" })
}

# Public subnets: host the ALB (via the load balancer controller) and the NAT
# gateway. Nothing that should be private lives here.
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.tags, { Name = "${var.name}-public-${local.azs[count.index]}" })
}

# Private subnets: EKS worker nodes and RDS. No public IPs, reach the internet
# only through the NAT gateway (image pulls, AWS API calls from pods).
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(local.tags, { Name = "${var.name}-private-${local.azs[count.index]}" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name}-igw" })
}

# Single NAT gateway in the first AZ: cheapest option that still gives the
# private subnets internet access. If a single-AZ NAT outage becomes a
# problem, add one per AZ (each private subnet would then need its own route
# table pointing at its local AZ's NAT).
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.tags, { Name = "${var.name}-nat-eip" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(local.tags, { Name = "${var.name}-nat" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name}-public-rt" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name}-private-rt" })
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this.id
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
