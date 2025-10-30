resource "aws_iam_policy" "ascp-sm-serviceaccount-policy" {
  count       = var.CREATE_SCP ? 1 : 0
  name        = "ascp-sm-${var.ENV}-eks-cluster"
  path        = "/"
  description = "ascp-sm-${var.ENV}-eks-cluster"

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds",
        ],
        "Resource": "*"
      }
    ]
  })
}

resource "aws_iam_policy" "ascp-ps-serviceaccount-policy" {
  count       = var.CREATE_SCP ? 1 : 0
  name        = "ascp-ps-${var.ENV}-eks-cluster"
  path        = "/"
  description = "ascp-ps-${var.ENV}-eks-cluster"

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "ssm:GetParameterHistory",
          "ssm:GetParametersByPath",
          "ssm:GetParameters",
          "ssm:GetParameter",
          "ssm:DescribeParameters"
        ],
        "Resource": "*"
      }
    ]
  })
}

//resource "kubernetes_service_account" "ascp-sa" {
//  depends_on = [null_resource.get-kube-config]
//  count = var.CREATE_EXTERNAL_SECRETS ? 1 : 0
//  metadata {
//    name      = "secrets-store-csi-driver"
//    namespace = "kube-system"
//    annotations = {
//      "eks.amazonaws.com/role-arn" = aws_iam_role.ascp-oidc-role.arn
//    }
//  }
//  automount_service_account_token = true
//}

data "aws_iam_policy_document" "ascp-policy_document" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test = "StringEquals"
      variable = "${replace(
        aws_eks_cluster.eks.identity[0].oidc[0].issuer,
        "https://",
        "",
      )}:aud"
      values = ["sts.amazonaws.com"]
    }

    principals {
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(
        aws_eks_cluster.eks.identity[0].oidc[0].issuer,
        "https://",
        "",
      )}"]
      type = "Federated"
    }
  }
}

resource "aws_iam_role" "ascp-oidc-role" {
  name               = "ascp-role-with-oidc"
  assume_role_policy = data.aws_iam_policy_document.ascp-policy_document.json
}

resource "aws_iam_role_policy_attachment" "ascp-sm-role-attach" {
  count       = var.CREATE_SCP ? 1 : 0
  role       = aws_iam_role.ascp-oidc-role.name
  policy_arn = aws_iam_policy.ascp-sm-serviceaccount-policy.*.arn[0]
}

resource "aws_iam_role_policy_attachment" "ascp-ps-role-attach" {
  count       = var.CREATE_SCP ? 1 : 0
  role       = aws_iam_role.ascp-oidc-role.name
  policy_arn = aws_iam_policy.ascp-ps-serviceaccount-policy.*.arn[0]
}

resource "null_resource" "ascp-helm-chart" {
  triggers = {
    a = timestamp()
  }
  depends_on = [null_resource.get-kube-config]
  count      = var.CREATE_SCP ? 1 : 0
  provisioner "local-exec" {
    command = <<EOF
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm repo update
helm upgrade -i -n kube-system csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver
EOF
  }
}