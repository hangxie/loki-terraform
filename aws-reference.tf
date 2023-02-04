locals {
  short_region_name_map = {
    "us-east-1" = "use1"
    "us-east-2" = "use2"
    "us-west-1" = "usw2"
    "us-west-2" = "usw2"
    "eu-west-1" = "euw1"
    "eu-west-2" = "euw2"
  }
  short_region_name = local.short_region_name_map[data.aws_region.current.name]

  # https://docs.aws.amazon.com/elasticloadbalancing/latest/application/enable-access-logging.html
  elb_logging_account_map = {
    "us-east-1" = "127311923021"
    "us-east-2" = "033677994240"
    "us-west-1" = "027434742980"
    "us-west-2" = "027434742980"
    "eu-west-1" = "156460612806"
    "eu-west-2" = "652711504416"
  }
  elb_logging_account = local.elb_logging_account_map[data.aws_region.current.name]
}
