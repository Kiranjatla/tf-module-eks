resource "aws_eks_node_group" "node_group" {
  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = "tf-nodes-spot"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = var.PRIVATE_SUBNET_IDS

  capacity_type  = "SPOT"
  instance_types = ["t3.xlarge"]

  scaling_config {
    desired_size = var.DESIRED_SIZE
    max_size     = var.MAX_SIZE
    min_size     = var.MIN_SIZE
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    role = "general"
    env  = var.ENV
  }

#  taint {
#    key    = "spot"
#    value  = "true"
#    effect = "NO_SCHEDULE"
#  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_policy
  ]

  tags = {
    Name        = "eks-node-group-spot-${var.ENV}"
    Environment = var.ENV
    ManagedBy   = "terraform"
  }
}