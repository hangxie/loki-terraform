locals {
  key_pairs = {
    "hxie" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE1EySXLkom6jYlCp0r/Ysjhwv42ZDmlKueR52fJ+Azx Hang Xie"
  }
  ssh_origins = [
    # CIDRs that are allowed to ssh in
    "172.58.31.217/32",
  ]
  ami = {
    "ubuntu2204" = {
      "us-east-1" : "ami-00874d747dde814fa",
    }
  }
}

resource "aws_key_pair" "ops" {
  for_each   = local.key_pairs
  key_name   = format("%s-%s", var.resource_name_prefix, each.key)
  public_key = each.value
}

resource "aws_security_group" "bastion" {
  name        = format("%s-bastion", var.resource_name_prefix)
  description = "security group for bastion"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = local.ssh_origins
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

resource "aws_instance" "bastion" {
  ami                    = local.ami["ubuntu2204"][data.aws_region.current.name]
  instance_type          = "t2.micro"
  key_name               = format("%s-hxie", var.resource_name_prefix)
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  root_block_device {
    # use aws/ebs key
    encrypted   = true
    volume_size = 100
    volume_type = "gp2"
  }

  # all EC2 instances are stateless
  user_data_replace_on_change = true
  user_data = templatefile(
    "${path.module}/templates/bastion-user-data",
    {
      hostname = format("%s-bastion", var.resource_name_prefix)
    }
  )

  tags = {
    Name = format("%s-bastion", var.resource_name_prefix)
  }
}

resource "aws_eip" "bastion" {
  instance = aws_instance.bastion.id
  vpc      = true

  # according to TF, IGW may be needed to create EIP
  depends_on = [
    aws_internet_gateway.main,
  ]

  tags = {
    Name = format("%s-bastion", var.resource_name_prefix)
  }
}

output "bastion" {
  description = "bastion"
  value = {
    eip = aws_eip.bastion.public_ip
  }
}
