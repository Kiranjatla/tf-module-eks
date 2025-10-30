resource "aws_eks_cluster" "eks" {
  name     = local.cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = var.versionx

  vpc_config {
    subnet_ids              = concat(var.PRIVATE_SUBNET_IDS, var.PUBLIC_SUBNET_IDS)
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["0.0.0.0/0"]  # Restrict in prod
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_controller
  ]

  tags = {
    Name        = local.cluster_name
    Environment = var.ENV
    ManagedBy   = "terraform"
  }
}