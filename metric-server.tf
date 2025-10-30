resource "null_resource" "metric-server" {
  count = var.INSTALL_KUBE_METRICS ? 1 : 0
  depends_on = [null_resource.get-kube-config]
  provisioner "local-exec" {
    command = "kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
  }
}