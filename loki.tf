locals {
  loki_bucket_name     = format("%s-loki-%s", var.resource_name_prefix, local.short_region_name)
  hosts_parameter_name = format("%s-loki-hosts", var.resource_name_prefix)
}

resource "aws_iam_instance_profile" "loki" {
  name = format("%s-loki", var.resource_name_prefix)
  role = aws_iam_role.loki.name
}

resource "aws_iam_role" "loki" {
  name = format("%s-loki-%s", var.resource_name_prefix, local.short_region_name)

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name = format("%s-loki-%s", var.resource_name_prefix, local.short_region_name)
  }
}

# It seems embedded policy is sufficient for now
resource "aws_iam_role_policy" "loki" {
  name = format("%s-loki-%s", var.resource_name_prefix, local.short_region_name)
  role = aws_iam_role.loki.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:ListObjects",
          "s3:ListBucket",
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.loki.arn,
          format("%s/*", aws_s3_bucket.loki.arn),
        ]
      },
      {
        Action   = "iam:PassRole"
        Effect   = "Allow"
        Resource = "*"
        Condition = {
          "StringEquals" : {
            "iam:PassedToService" : "ec2.amazonaws.com"
          }
        }
      },
      {
        Action   = "ssm:GetParameter"
        Effect   = "Allow"
        Resource = format("arn:aws:ssm:%s:%s:parameter/%s", data.aws_region.current.name, data.aws_caller_identity.current.account_id, local.hosts_parameter_name)
      },
    ]
  })
}

resource "aws_s3_bucket" "loki" {
  bucket = local.loki_bucket_name
}

resource "aws_s3_bucket_server_side_encryption_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id
  rule {
    apply_server_side_encryption_by_default {
      # use aws/s3 key managed by AWS
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "loki" {
  bucket = aws_s3_bucket.loki.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id
  rule {
    status = "Enabled"
    id     = "purge-all-after-1-year"
    expiration { days = 365 }
  }
}

resource "aws_security_group" "loki" {
  name        = format("%s-loki", var.resource_name_prefix)
  description = "security group for loki instances"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "all"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  ingress {
    description     = "ssh"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = format("%s-basition-ssh", var.resource_name_prefix)
  }
}

resource "aws_instance" "loki" {
  for_each = {
    for index in range(0, var.private_subnet_count) : index => index
  }
  ami                    = local.ami["ubuntu2204"][data.aws_region.current.name]
  instance_type          = "t2.micro" # TODO determine right flavor
  key_name               = format("%s-hxie", var.resource_name_prefix)
  subnet_id              = aws_subnet.private[each.key].id
  vpc_security_group_ids = [aws_security_group.loki.id]
  root_block_device {
    # use aws/ebs key
    encrypted   = true
    volume_size = 100
    volume_type = "gp2"
  }
  iam_instance_profile = aws_iam_instance_profile.loki.id

  # all EC2 instances are stateless
  user_data_replace_on_change = true
  user_data = templatefile(
    "${path.module}/templates/loki-user-data",
    {
      hostname           = format("%s-loki-%d", var.resource_name_prefix, tonumber(each.key) + 1)
      loki_bucket        = local.loki_bucket_name
      rest_port          = var.loki_ports["rest"]
      grpc_port          = var.loki_ports["grpc"]
      gossip_port        = var.loki_ports["gossip"]
      ssm_parameter_name = local.hosts_parameter_name
      region             = data.aws_region.current.name
      loki_version       = var.loki_version
    }
  )

  tags = {
    Name = format("%s-loki-%d", var.resource_name_prefix, each.key + 1)
  }
}

resource "aws_alb" "loki" {
  name               = format("%s-loki", var.resource_name_prefix)
  internal           = true # no plan to expose to public
  load_balancer_type = "application"
  security_groups    = [aws_security_group.loki.id]
  subnets            = [for subnet in aws_subnet.private : subnet.id]

  enable_deletion_protection = false
  access_logs {
    bucket  = aws_s3_bucket.logging.bucket
    prefix  = "lb/loki"
    enabled = true
  }

  tags = {
    Name = format("%s-loki", var.resource_name_prefix)
  }
}

resource "aws_alb_target_group" "loki_rest" {
  name     = format("%s-loki-rest", var.resource_name_prefix)
  vpc_id   = aws_vpc.main.id
  port     = var.loki_ports["rest"]
  protocol = "HTTP"

  health_check {
    protocol = "HTTP"
    port     = var.loki_ports["rest"]
    path     = "/ready"
  }
}

resource "aws_alb_listener" "loki_rest" {
  load_balancer_arn = aws_alb.loki.arn
  port              = var.loki_ports["rest"]
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.loki_rest.arn
  }
}

resource "aws_alb_target_group_attachment" "loki_rest" {
  for_each = {
    for index in range(0, var.private_subnet_count) : index => index
  }
  target_group_arn = aws_alb_target_group.loki_rest.arn
  target_id        = aws_instance.loki[each.key].id
  port             = var.loki_ports["rest"]
}

resource "aws_ssm_parameter" "loki_hosts" {
  name  = local.hosts_parameter_name
  type  = "String"
  value = join(",", [for instance in aws_instance.loki : instance.private_ip])
}
