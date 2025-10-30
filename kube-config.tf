resource "null_resource" "get-kube-config" {
  depends_on = [aws_eks_node_group.node-group]
  provisioner "local-exec" {
    command = "aws eks update-kubeconfig  --name ${var.ENV}-eks-cluster"
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = aws_eks_cluster.eks.arn
}