resource "aws_iam_policy" "parameter_store_policy" {
  count = var.CREATE_PARAMETER_STORE ? 1 : 0

  name        = "ParameterStore-ssm-${var.ENV}-eks-cluster"
  description = "Allows EKS Service Accounts to read SSM Parameters"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = [
        "ssm:DescribeParameters",
        "ssm:GetParameterHistory",
        "ssm:GetParametersByPath",
        "ssm:GetParameters",
        "ssm:GetParameter"
      ]
      Resource = "*"
    }]
  })

  tags = {
    Name        = "parameter-store-policy-${var.ENV}"
    Environment = var.ENV
    ManagedBy   = "terraform"
  }
}

data "aws_iam_policy_document" "parameter_store_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.cluster.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:default:ssm-reader"]  # UPDATE THIS!
    }
  }
}

resource "aws_iam_role" "parameter_store_oidc_role" {
  count              = var.CREATE_PARAMETER_STORE ? 1 : 0
  name               = "parameter-store-oidc-role-${var.ENV}"
  assume_role_policy = data.aws_iam_policy_document.parameter_store_assume_role.json

  tags = {
    Name        = "parameter-store-oidc-role-${var.ENV}"
    Environment = var.ENV
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "parameter_store_attach" {
  count      = var.CREATE_PARAMETER_STORE ? 1 : 0
  role       = aws_iam_role.parameter_store_oidc_role[0].name
  policy_arn = aws_iam_policy.parameter_store_policy[0].arn
}