variable "ENV" {
  description = "Environment name (prod, dev, etc.)"
  type        = string
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
  description = "Set to true to install External Secrets"
  type        = bool
  default     = true
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
  default = "1.32"
}

variable "AWS_REGION" {
  type = string
}