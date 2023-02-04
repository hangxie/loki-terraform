locals {
  vpc_netmask = tonumber(split("/", var.vpc_cidr)[1])
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = format("%s-%s", var.resource_name_prefix, "main")
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = format("%s-%s", var.resource_name_prefix, "main")
  }
}

locals {
  # private subnets start from low end addresses
  private_cidrs = [
    for index in range(0, var.private_subnet_count) :
    cidrsubnet(
      var.vpc_cidr,
      var.private_subnet_netmask - local.vpc_netmask,
      index,
    )
  ]
}

resource "aws_subnet" "private" {
  for_each = {
    for index, cidr_block in local.private_cidrs : index => cidr_block
  }

  vpc_id     = aws_vpc.main.id
  cidr_block = each.value

  availability_zone = data.aws_availability_zones.current.names[
    each.key % length(data.aws_availability_zones.current.names)
  ]

  tags = {
    Name = format("%s-private-%s", var.resource_name_prefix, each.key + 1)
  }
}

locals {
  # public subnets start from high end addresses
  available_slots = pow(2, (var.public_subnet_netmask - local.vpc_netmask))
  public_cidrs = [
    for index in range(0, var.public_subnet_count) :
    cidrsubnet(
      var.vpc_cidr,
      var.public_subnet_netmask - local.vpc_netmask,
      local.available_slots - index - 1,
    )
  ]
}

resource "aws_subnet" "public" {
  for_each = {
    for index, cidr_block in local.public_cidrs : index => cidr_block
  }

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  map_public_ip_on_launch = true

  availability_zone = data.aws_availability_zones.current.names[
    each.key % length(data.aws_availability_zones.current.names)
  ]

  tags = {
    Name = format("%s-public-%s", var.resource_name_prefix, each.key + 1)
  }
}

resource "aws_eip" "natgw" {
  for_each = {
    for index in range(0, var.public_subnet_count) : index => index
  }

  vpc = true

  tags = {
    Name = format("%s-natgw-%d", var.resource_name_prefix, each.key + 1)
  }

  # according to TF, IGW may be needed to create EIP
  depends_on = [
    aws_internet_gateway.main,
  ]
}

resource "aws_nat_gateway" "natgw" {
  for_each = {
    for index in range(0, var.public_subnet_count) : index => index
  }
  allocation_id = aws_eip.natgw[each.key].allocation_id
  subnet_id     = aws_subnet.public[each.key].id

  tags = {
    Name = format("%s-natgw-%d", var.resource_name_prefix, each.key + 1)
  }
}

resource "aws_route_table" "private" {
  for_each = {
    for index in range(0, var.private_subnet_count) : index => index
  }
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.natgw[each.key].id
  }

  tags = {
    Name = format("%s-private-%d", var.resource_name_prefix, each.key + 1)
  }
}

resource "aws_route_table_association" "private" {
  for_each = {
    for index in range(0, var.private_subnet_count) : index => index
  }
  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = format("%s-public", var.resource_name_prefix)
  }
}

resource "aws_route_table_association" "public" {
  for_each = {
    for index in range(0, var.public_subnet_count) : index => index
  }
  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public.id
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = format("com.amazonaws.%s.s3", data.aws_region.current.name)
  route_table_ids = concat(
    [for route_table in aws_route_table.private : route_table.id],
    # feel like public subnet should not have access to endpoint for a bit more security
    [aws_route_table.public.id],
  )
  tags = {
    Name = format("%s-s3", var.resource_name_prefix)
  }
}

output "vpc" {
  description = "VPC attributes"
  value = {
    arn  = aws_vpc.main.arn
    id   = aws_vpc.main.id
    cidr = aws_vpc.main.cidr_block
  }
}

output "igw" {
  description = "Internet gateway attributes"
  value = {
    id = aws_internet_gateway.main.id
  }
}

output "private_subnets" {
  description = "all private subnets"
  value = [for sn in aws_subnet.private :
    {
      arn  = sn.arn
      id   = sn.id
      cidr = sn.cidr_block
    }
  ]
}

output "public_subnets" {
  description = "all public subnets"
  value = [for sn in aws_subnet.public :
    {
      arn  = sn.arn
      id   = sn.id
      cidr = sn.cidr_block
    }
  ]
}

output "nat_gw" {
  description = "all NAT gateways"
  value = [for index in range(0, var.public_subnet_count) :
    {
      id  = aws_nat_gateway.natgw[index].id
      eip = aws_eip.natgw[index].public_ip
    }
  ]
}
