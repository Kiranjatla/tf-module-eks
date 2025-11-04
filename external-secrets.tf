# ===================================================================
# 1. IAM POLICIES (Permissions for ESO to read Secrets/Parameters)
# ===================================================================

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
          "secretsmanager:ListSecretVersionIds",
          "secretsmanager:ListSecrets"
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

# ===================================================================
# 2. IAM ROLE (OIDC Role for the Kubernetes Service Account)
# ===================================================================

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
  name               = "external-secrets-role-with-oidc"
  assume_role_policy = data.aws_iam_policy_document.external-secrets-policy_document.json
}

resource "aws_iam_role_policy_attachment" "external-secrets-secret-manager-role-attach" {
  count      = var.CREATE_EXTERNAL_SECRETS ? 1 : 0
  role       = aws_iam_role.external-secrets-oidc-role.name
  policy_arn = aws_iam_policy.external-secrets-secret-manager-serviceaccount-policy.*.arn[0]
}

resource "aws_iam_role_policy_attachment" "external-secrets-parameter-store-role-attach" {
  count      = var.CREATE_EXTERNAL_SECRETS ? 1 : 0
  role       = aws_iam_role.external-secrets-oidc-role.name
  policy_arn = aws_iam_policy.external-secrets-parameter-store-serviceaccount-policy.*.arn[0]
}

# ===================================================================
# 3. KUBERNETES SERVICE ACCOUNT (The IRSA hook)
# ===================================================================

resource "kubernetes_service_account" "external-secrets-sa" {
  depends_on = [null_resource.get-kube-config]
  count      = var.CREATE_EXTERNAL_SECRETS ? 1 : 0
  metadata {
    name      = "external-secrets-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.external-secrets-oidc-role.arn
    }
  }
  automount_service_account_token = true
}

# ===================================================================
# 4. HELM CHART INSTALL (Uses shell due to Helm requirements)
# ===================================================================

resource "null_resource" "external-secrets-helm-chart" {
  count    = var.CREATE_EXTERNAL_SECRETS ? 1 : 0
  triggers = { timestamp = timestamp() }

  # Must run after kubeconfig is ready and the Service Account exists
  depends_on = [
    null_resource.get-kube-config,
    kubernetes_service_account.external-secrets-sa,
  ]

  provisioner "local-exec" {
    command = <<-EOF
# Define the kubeconfig path for reliable execution
KUBECONFIG_PATH="${pathexpand("~/.kube/config")}"

# Add Helm repo
helm repo add external-secrets https://charts.external-secrets.io || true
helm repo update

echo "Installing External Secrets (v0.20.4)..."
helm upgrade -i external-secrets external-secrets/external-secrets \
  -n kube-system \
  --create-namespace \
  --set serviceAccount.create=false \
  --set serviceAccount.name=external-secrets-controller \
  --set installCRDs=true \
  --version 0.20.4 \
  --timeout 10m

echo "Waiting for Deployment and CRDs to be ready..."
# Wait for the Deployment to be available
kubectl --kubeconfig $KUBECONFIG_PATH -n kube-system wait --for=condition=available deploy/external-secrets --timeout=3m

# Wait for the CRD to be established before declarative manifests apply
until kubectl --kubeconfig $KUBECONFIG_PATH get crd clustersecretstores.external-secrets.io -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' | grep -q True; do
  echo "CRD not ready yet... sleeping 5s"
  sleep 5
done

echo "External Secrets chart deployed and CRDs are established."
EOF
  }

  provisioner "local-exec" {
    when = destroy
    command = "helm uninstall external-secrets -n kube-system || true"
  }
}

# ===================================================================
# 5. DECLARATIVE CLUSTERSECRETSTORE DEPLOYMENT (The reliable fix)
# ===================================================================

# 1. Deploy the Secrets Manager ClusterSecretStore
resource "kubernetes_manifest" "roboshop_secret_manager_store" {
  count = var.CREATE_EXTERNAL_SECRETS ? 1 : 0

  # Dependencies ensure the CRD exists and the Kubernetes provider is authenticated.
  depends_on = [
    null_resource.external-secrets-helm-chart,
    null_resource.get-kube-config
  ]

  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "roboshop-secret-manager"
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = "us-east-1"
          auth = {
            jwt = {
              serviceAccountRef = {
                name      = "external-secrets-controller"
                namespace = "kube-system"
              }
            }
          }
        }
      }
    }
  }
}

# 2. Deploy the Parameter Store ClusterSecretStore
resource "kubernetes_manifest" "roboshop_parameter_store" {
  count = var.CREATE_EXTERNAL_SECRETS ? 1 : 0

  # Dependencies ensure the CRD exists and the Kubernetes provider is authenticated.
  depends_on = [
    null_resource.external-secrets-helm-chart,
    null_resource.get-kube-config
  ]

  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "roboshop-parameter-store"
    }
    spec = {
      provider = {
        aws = {
          service = "ParameterStore"
          region  = "us-east-1"
          auth = {
            jwt = {
              serviceAccountRef = {
                name      = "external-secrets-controller"
                namespace = "kube-system"
              }
            }
          }
        }
      }
    }
  }
}