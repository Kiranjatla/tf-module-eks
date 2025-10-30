resource "null_resource" "nginx-ingress-chart" {
  triggers = {
    a = timestamp()
  }
  depends_on = [null_resource.get-kube-config]
  count      = var.CREATE_NGINX_INGRESS ? 1 : 0
  provisioner "local-exec" {
    command = <<EOF
helm repo add nginx-stable https://helm.nginx.com/stable
helm repo update
helm upgrade -i ingress nginx-stable/nginx-ingress -f ${path.module}/extras/nginx-ingress-values.yml
EOF
  }
}