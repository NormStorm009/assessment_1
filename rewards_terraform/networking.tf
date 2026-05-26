#==== The VPC ======#
resource "aws_vpc" "main" {
  cidr_block       = var.vpc_cidr_block
  instance_tenancy = "default"

  tags = {
    Name        = "${local.name}-vpc"
    Environment = "${var.env}"
  }
}

#==== The Internet Gateway ======#
resource "aws_internet_gateway" "ig" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${local.name}-ig"
    Environment = "${var.env}"
  }
}


#==== NAT Gateway ======#

resource "aws_eip" "nat" {
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_subnet_1.id

  tags = {
    Name        = "${local.name}-nat"
    Environment = "${var.env}"
  }

  depends_on = [aws_internet_gateway.ig]
}

#==== The Subnets ======#

resource "aws_subnet" "public_subnet_1" {
  vpc_id     = aws_vpc.main.id
  cidr_block = var.public_subnet_cidr_blocks[0]
  map_public_ip_on_launch = true
  availability_zone = var.azs[0]

  tags = {
    Name        = "${local.name}-public-subnet-1"
    Environment = "${var.env}"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id     = aws_vpc.main.id
  cidr_block = var.public_subnet_cidr_blocks[1]
  map_public_ip_on_launch = true
  availability_zone = var.azs[1]

  tags = {
    Name        = "${local.name}-public-subnet-2"
    Environment = "${var.env}"
  }
}

resource "aws_subnet" "private_subnet_1" {
  vpc_id     = aws_vpc.main.id
  cidr_block = var.private_subnet_cidr_blocks[0]
  map_public_ip_on_launch = true
  availability_zone = var.azs[0]

  tags = {
    Name        = "${local.name}-private-subnet-1"
    Environment = "${var.env}"
  }
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id     = aws_vpc.main.id
  cidr_block = var.private_subnet_cidr_blocks[1]
  map_public_ip_on_launch = true
  availability_zone = var.azs[1]

  tags = {
    Name        = "${local.name}-private-subnet-2"
    Environment = "${var.env}"
  }
}

#==== The Routes ======#
#== PUBLIC ==#

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "${local.name}-route-table-pub"
    Environment = "${var.env}"
  }
}

resource "aws_route" "public" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.ig.id
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public.id
}

#== PRIVATE ==#

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "${local.name}-route-table-priv"
    Environment = "${var.env}"
  }
}

resource "aws_route" "private" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_2" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private.id
}