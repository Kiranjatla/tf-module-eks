# Private Subnets – Cluster Tag
resource "aws_ec2_tag" "private_subnet_cluster" {
  count       = length(var.PRIVATE_SUBNET_IDS)
  resource_id = var.PRIVATE_SUBNET_IDS[count.index]
  key         = "kubernetes.io/cluster/${local.cluster_name}"
  value       = "owned"
}

# Private Subnets – Internal LB
resource "aws_ec2_tag" "private_subnet_internal_lb" {
  count       = length(var.PRIVATE_SUBNET_IDS)
  resource_id = var.PRIVATE_SUBNET_IDS[count.index]
  key         = "kubernetes.io/role/internal-elb"
  value       = "1"
}

# Public Subnets – Cluster Tag
resource "aws_ec2_tag" "public_subnet_cluster" {
  count       = length(var.PUBLIC_SUBNET_IDS)
  resource_id = var.PUBLIC_SUBNET_IDS[count.index]
  key         = "kubernetes.io/cluster/${local.cluster_name}"
  value       = "owned"
}

# Public Subnets – Public LB
resource "aws_ec2_tag" "public_subnet_public_lb" {
  count       = length(var.PUBLIC_SUBNET_IDS)
  resource_id = var.PUBLIC_SUBNET_IDS[count.index]
  key         = "kubernetes.io/role/elb"
  value       = "1"
}