resource "aws_iam_openid_connect_provider" "cluster" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [local.oidc_thumbprint]
  url             = aws_eks_cluster.eks.identity[0].oidc[0].issuer

  tags = {
    Name        = "${local.cluster_name}-oidc"
    Environment = var.ENV
    ManagedBy   = "terraform"
  }
}