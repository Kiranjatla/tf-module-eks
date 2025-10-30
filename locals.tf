# Local values for reuse
locals {
  cluster_name = "${var.ENV}-eks-cluster"
}

# OIDC thumbprint using native TLS provider
data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.eks.identity[0].oidc[0].issuer
}

locals {
  oidc_thumbprint = data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint
}