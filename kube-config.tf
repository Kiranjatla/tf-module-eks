resource "null_resource" "get_kube_config" {
  depends_on = [
    aws_eks_cluster.eks,
    aws_eks_node_group.node_group
  ]

  provisioner "local-exec" {
    command = <<EOT
      aws eks update-kubeconfig \
        --name ${local.cluster_name} \
        --region ${var.AWS_REGION} \
        --kubeconfig "${pathexpand("~/.kube/config")}"
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "rm -f \"${pathexpand(\"~/.kube/config\")}\""
  }
}

provider "kubernetes" {
  host                   = aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.eks.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks", "get-token",
      "--cluster-name", aws_eks_cluster.eks.name,
      "--region", var.AWS_REGION
    ]
  }
}