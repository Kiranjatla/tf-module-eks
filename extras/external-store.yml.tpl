apiVersion: external-secrets.io/v1alpha1
kind: ClusterSecretStore
metadata:
  name: roboshop-secret-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      role: ${ROLE_ARN}

---
apiVersion: external-secrets.io/v1alpha1
kind: ClusterSecretStore
metadata:
  name: roboshop-parameter-store
spec:
  provider:
    aws:
      service: ParameterStore
      region: us-east-1
      role: ${ROLE_ARN}