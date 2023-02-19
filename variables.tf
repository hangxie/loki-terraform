variable "resource_name_prefix" {
  description = "prefix to name of all resources"
  type        = string
  default     = "hxie-test"
}

variable "vpc_id" {
  description = "CIDR for VPC"
  type        = string
}

variable "subnet_ids" {
  description = "subnets for loki hosts"
  type        = list(string)
}

variable "debian_ami" {
  description = "Debian 11 AMI"
  type        = string
  default     = "ami-0fec2c2e2017f4e7b"
}

variable "loki_version" {
  description = "grafana/loki docker image tag"
  type        = string
  default     = "2.7.3"
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
