resource "aws_iam_policy" "external-secrets-secret-manager-serviceaccount-policy" {
  count = var.CREATE_EXTERNAL_SECRETS ? 1 : 0
  name = "ExternalSecretsPolicy-sm-${var.ENV}-eks-cluster"
  path = "/"
  description = "ExternalSecretsPolicy-sm-${var.ENV}-eks-cluster"
  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds"
        ],
        "Resource": "*"
      }
    ]
  })
}

resource "aws_iam_policy" "external-secrets-parameter-store-serviceaccount-policy" {
  count = var.CREATE_EXTERNAL_SECRETS ? 1 : 0
  name = "ExternalSecretsPolicy-pm-${var.ENV}-eks-cluster"
  path = "/"
  description = "ExternalSecretsPolicy-pm-${var.ENV}-eks-cluster"
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

data "aws_iam_policy_document" "external-secrets-policy_document" {
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

resource "aws_iam_role" "external-secrets-oidc-role" {
  name = "external-secrets-role-with-oidc"
  assume_role_policy = data.aws_iam_policy_document.external-secrets-policy_document.json
}

resource "aws_iam_role_policy_attachment" "external-secrets-secret-manager-role-attach" {
  count = var.CREATE_EXTERNAL_SECRETS ? 1 : 0
  role = aws_iam_role.external-secrets-oidc-role.name
  policy_arn = aws_iam_policy.external-secrets-secret-manager-serviceaccount-policy.*.arn[0]
}

resource "aws_iam_role_policy_attachment" "external-secrets-parameter-store-role-attach" {
  count = var.CREATE_EXTERNAL_SECRETS ? 1 : 0
  role = aws_iam_role.external-secrets-oidc-role.name
  policy_arn = aws_iam_policy.external-secrets-parameter-store-serviceaccount-policy.*.arn[0]
}

resource "kubernetes_service_account" "external-ingress-ingress-sa" {
  depends_on = [null_resource.get-kube-config]
  count = var.CREATE_EXTERNAL_SECRETS ? 1 : 0
  metadata {
    name = "external-secrets-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.external-secrets-oidc-role.arn
    }
  }
  automount_service_account_token = true
}

# Render external-store.yml with real ARN
resource "local_file" "external_store_rendered" {
  count    = var.CREATE_EXTERNAL_SECRETS ? 1 : 0
  filename = "${path.module}/extras/external-store.yml"
  content  = templatefile("${path.module}/extras/external-store.yml.tpl", {
    ROLE_ARN = aws_iam_role.external-secrets-oidc-role.arn
  })
}

# Install External Secrets
resource "null_resource" "external-secrets-ingress-chart" {
  count = var.CREATE_EXTERNAL_SECRETS ? 1 : 0
  triggers = { timestamp = timestamp() }

  depends_on = [
    null_resource.get-kube-config,
    kubernetes_service_account.external-ingress-ingress-sa,
    local_file.external_store_rendered
  ]

  provisioner "local-exec" {
    command = <<EOF
# 1. Add Helm repo
helm repo add external-secrets https://charts.external-secrets.io || true
helm repo update

# 2. Install latest Helm chart (v0.20.4)
echo "Installing External Secrets (latest v0.20.4)..."
helm upgrade -i external-secrets external-secrets/external-secrets \
  -n kube-system \
  --create-namespace \
  --set serviceAccount.create=false \
  --set serviceAccount.name=external-secrets-controller \
  --set installCRDs=true \
  --version 0.20.4 \
  --timeout 5m

# 3. Wait for Deployment
echo "Waiting for Deployment..."
until kubectl -n kube-system get deploy external-secrets > /dev/null 2>&1; do sleep 5; done

# 4. Wait for pod to be ready (5 min max)
echo "Waiting up to 5 min for pod..."
timeout 300 kubectl -n kube-system wait --for=condition=available deploy/external-secrets --timeout=300s || {
  echo "Pod failed. Debugging logs..."
  kubectl -n kube-system get pods -l app.kubernetes.io/name=external-secrets
  kubectl -n kube-system logs -l app.kubernetes.io/name=external-secrets --tail=20 || true
  echo "Attempting restart..."
  kubectl -n kube-system rollout restart deploy external-secrets
  sleep 30
  if ! timeout 180 kubectl -n kube-system wait --for=condition=available deploy/external-secrets --timeout=180s; then
    echo "Second attempt failed. Check IRSA role trust."
    exit 1
  fi
}

# 5. Wait 30s for CRDs
echo "Waiting 30s for CRDs..."
sleep 30

# 6. Apply ClusterSecretStore
kubectl apply -f ${path.module}/extras/external-store.yml || true

echo "External Secrets deployed successfully!"
EOF
  }

  provisioner "local-exec" {
    when = destroy
    command = <<EOF
helm uninstall external-secrets -n kube-system || true
kubectl delete -f ${path.module}/extras/external-store.yml || true
EOF
  }
}