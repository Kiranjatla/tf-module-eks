# Assumed data sources must be defined elsewhere (e.g., in main.tf)
# data "aws_caller_identity" "current" { }
# resource "aws_eks_cluster" "eks" { ... }
# resource "null_resource" "get-kube-config" { ... }

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
# 4. HELM CHART INSTALL AND PREREQUISITE WAITS
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

# 1. Wait for the main Deployment to be available
kubectl --kubeconfig $KUBECONFIG_PATH -n kube-system wait --for=condition=available deploy/external-secrets --timeout=3m

# 2. Wait for the CRD to be established
until kubectl --kubeconfig $KUBECONFIG_PATH get crd clustersecretstores.external-secrets.io -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' | grep -q True; do
  echo "CRD not ready yet... sleeping 5s"
  sleep 5
done

# 3. CRITICAL WAIT: Wait for the Webhook Service Endpoints to be ready
echo "Waiting for external-secrets-webhook endpoints to be available..."
until kubectl --kubeconfig $KUBECONFIG_PATH get endpoints external-secrets-webhook -n kube-system -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null; do
  echo "Webhook endpoint not yet available... sleeping 5s"
  sleep 5
done
echo "Webhook endpoint is ready."

# FINAL AGGRESSIVE SLEEP: Gives the Kubernetes API server and networking components time to fully settle.
echo "Waiting 10 seconds for API server service endpoint registration to settle..."
sleep 10

echo "External Secrets chart deployed and all prerequisites are established."
EOF
  }

  provisioner "local-exec" {
    when = destroy
    command = "helm uninstall external-secrets -n kube-system || true"
  }
}

# ===================================================================
# 5. FINAL RELIABLE DEPLOYMENT OF CLUSTERSECRETSTORE (Using Shell)
# ===================================================================

# This block executes the ClusterSecretStore deployment via kubectl,
# which has proven to be successful where kubernetes_manifest failed
# due to a persistent webhook race condition.
resource "null_resource" "deploy-cluster-secret-stores" {
  count = var.CREATE_EXTERNAL_SECRETS ? 1 : 0

  # MUST run after the Helm chart installation and all its waits are complete.
  depends_on = [
    null_resource.external-secrets-helm-chart
  ]

  provisioner "local-exec" {
    command = <<-EOF
# Define the kubeconfig path for reliable execution
KUBECONFIG_PATH="${pathexpand("~/.kube/config")}"

echo "Applying ClusterSecretStore manifests using proven kubectl method..."
cat <<YAML | kubectl --kubeconfig $KUBECONFIG_PATH apply -f -
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: roboshop-secret-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: "us-east-1"
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-controller
            namespace: kube-system
---
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: roboshop-parameter-store
spec:
  provider:
    aws:
      service: ParameterStore
      region: "us-east-1"
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-controller
            namespace: kube-system
YAML

echo "ClusterSecretStores applied successfully."
EOF
  }

  provisioner "local-exec" {
    when = destroy
    # Clean up the ClusterSecretStore resources on destroy
    command = <<-EOF
KUBECONFIG_PATH="${pathexpand("~/.kube/config")}"
kubectl --kubeconfig $KUBECONFIG_PATH delete clustersecretstore roboshop-secret-manager || true
kubectl --kubeconfig $KUBECONFIG_PATH delete clustersecretstore roboshop-parameter-store || true
EOF
  }
}
