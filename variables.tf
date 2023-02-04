variable "resource_name_prefix" {
  description = "prefix to name of all resources"
  type        = string
  default     = "hxie-test"
}

variable "vpc_cidr" {
  description = "CIDR for VPC"
  type        = string
  default     = "172.17.0.0/16"
}

variable "private_subnet_count" {
  description = "number of private subnets"
  type        = number
  default     = 3
}

variable "private_subnet_netmask" {
  description = "network mask for private subnets"
  type        = number
  default     = 22
}

variable "public_subnet_count" {
  description = "number of public subnets"
  type        = number
  default     = 3
}

variable "public_subnet_netmask" {
  description = "network mask for public subnets"
  type        = number
  default     = 24
}

variable "loki_ports" {
  description = "ports to run loki"
  type        = map(number)
  default = {
    "rest"   = 3100
    "gossip" = 7946
    "grpc"   = 9095
  }
}

variable "loki_version" {
  description = "grafana/loki docker image tag"
  type        = string
  default     = "2.7.3"
}
