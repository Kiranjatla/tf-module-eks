variable "ENV" {
  type = string
}

variable "PRIVATE_SUBNET_IDS" {
  type = list(string)
}

variable "PUBLIC_SUBNET_IDS" {
  type = list(string)
}

variable "DESIRED_SIZE" {
  type = number
}

variable "MAX_SIZE" {
  type = number
}

variable "MIN_SIZE" {
  type = number
}

variable "CREATE_ALB_INGRESS" {
  default = false
}

variable "CREATE_EXTERNAL_SECRETS" {
  default = false
}

variable "INSTALL_KUBE_METRICS" {
  default = false
}

variable "CREATE_SCP" {
  default = false
}

variable "CREATE_NGINX_INGRESS" {
  default = false
}

variable "CREATE_PARAMETER_STORE" {
  default = false
}

variable "versionx" {
  default = "1.31"
}

variable "AWS_REGION" {
  type = string
}