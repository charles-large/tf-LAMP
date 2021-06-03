provider "aws" {
  region = "us-east-1"
  shared_credentials_file = "~/.aws/creds"
  profile = "test"
  
}

resource "aws_vpc" "MainVPC" {
  cidr_block = "10.10.0.0/16"

  tags = {
    "Name" = "MainVPC"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.MainVPC.id

  tags = {
    Name = "main"
  }
}

resource "aws_subnet" "PublicSubnet" {
  vpc_id = aws_vpc.MainVPC.id
  cidr_block = "10.10.10.0/24"

  tags = {
    "Name" = "Public Subnet"
  }
}

resource "aws_subnet" "PrivateSubnet" {
  vpc_id = aws_vpc.MainVPC.id
  cidr_block = "10.10.15.0/24"

  tags = {
    "Name" = "Private Subnet"
  }
}

variable "sg_private_ingress_rules" {
  default = [{
          cidr_block = ["10.10.10.25/32"]
          description = "MySQL from EC2 Web"
          from_port = 3306
          protocol = "tcp"
          to_port = 3306
        },
        {
          cidr_block = ["10.10.10.30/32"]
          description = "SSh Access from Jumpbox"
          from_port = 22
          protocol = "tcp"
          to_port = 22
        }]
    
  
}

variable "sg_public_ingress_rules" {
  default = [
        {
          cidr_block = ["10.0.0.0/16"]
          description = "Web Server Access"
          from_port = 80
          protocol = "tcp"
          to_port = 80
        },
        {
          cidr_block = ["10.0.0.0/16"]
          description = "SSh Access"
          from_port = 22
          protocol = "tcp"
          to_port = 22
        }
    ]
    
  
}


resource "aws_security_group" "SecurityGroup1" {
  name = "SecurityGroup1"
  description = "allow ssh, http"
  vpc_id = aws_vpc.MainVPC.id
  dynamic "ingress"{
    for_each = var.sg_private_ingress_rules
    content {
        cidr_blocks = ingress.value["cidr_block"]
        description = ingress.value["description"]
        from_port = ingress.value["from_port"]
        protocol = ingress.value["protocol"]
        to_port = ingress.value["to_port"]
    }
  }
}

resource "aws_security_group" "SecurityGroup2" {
  name = "SecurityGroup2"
  description = "MYSQL and SSH access"
  vpc_id = aws_vpc.MainVPC.id
  dynamic "ingress"{
    for_each = var.sg_public_ingress_rules
    content {
        cidr_blocks = ingress.value["cidr_block"]
        description = ingress.value["description"]
        from_port = ingress.value["from_port"]
        protocol = ingress.value["protocol"]
        to_port = ingress.value["to_port"]
    }
  }

}

resource "aws_eip" "ngEIP" {
  vpc      = false

}


resource "aws_nat_gateway" "PublicSubnetNAT" {
  allocation_id = aws_eip.ngEIP.id
  subnet_id = aws_subnet.PublicSubnet.id

  tags = {
    "Name" = "WebServerNG"
  }

  depends_on = [aws_internet_gateway.gw]
  
}

resource "aws_route_table" "MainVPCPrivateRouteTable" {
  vpc_id = aws_vpc.MainVPC.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.PublicSubnetNAT.id
    
  }

}

resource "aws_route_table" "MainVPCPublicRouteTable" {
  vpc_id = aws_vpc.MainVPC.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
    
  }

}

resource "aws_route_table_association" "a" {
  subnet_id = aws_subnet.PublicSubnet.id
  route_table_id = aws_route_table.MainVPCPublicRouteTable.id
  
}

resource "aws_route_table_association" "b" {
  subnet_id = aws_subnet.PrivateSubnet.id
  route_table_id = aws_route_table.MainVPCPrivateRouteTable.id
  
}

# resource "aws_elb" "elb" {
#   name = "MainELB"
#   subnets = [ aws_subnet.PublicSubnet.id ]

#   listener {
#     instance_port = 80
#     instance_protocol = HTTP
#     lb_port = 80
#     lb_protocol = HTTP
#     internal = true
    
#   }
  
# }

resource "aws_launch_template" "launch_template" {
  image_id = "ami-0d5eff06f840b45e9"
  instance_type = "t2.micro"
  key_name = "will_it_work"
  name_prefix = "ASG-"
  vpc_security_group_ids = [ aws_security_group.SecurityGroup2.id]
  tag_specifications {
    resource_type = "instance"
    tags = {
      name = "test"
    }
  }

}

resource "aws_autoscaling_group" "asg" {
  max_size = 5
  min_size = 2
  desired_capacity = 2
  vpc_zone_identifier = [ aws_subnet.PublicSubnet.id ]
  
  launch_template {
    id = aws_launch_template.launch_template.id
    version = "$Latest"
  }

  
  
}

resource "aws_instance" "EC2WEB" {
  ami = "ami-0d5eff06f840b45e9"
  instance_type = "t2.micro"
  subnet_id = aws_subnet.PublicSubnet.id
  private_ip = "10.10.10.25"
  associate_public_ip_address = true
  key_name = "will_it_work"
  vpc_security_group_ids = [aws_security_group.SecurityGroup1.id]
}

resource "aws_instance" "JumpBox" {
  ami = "ami-0d5eff06f840b45e9"
  instance_type = "t2.micro"
  subnet_id = aws_subnet.PublicSubnet.id
  associate_public_ip_address = true
  private_ip = "10.10.10.30"
  key_name = "will_it_work"
  vpc_security_group_ids = [aws_security_group.SecurityGroup1.id]
}

resource "aws_instance" "MySQL" {
  ami = "ami-0d5eff06f840b45e9"
  instance_type = "t2.micro"
  subnet_id = aws_subnet.PrivateSubnet.id
  private_ip = "10.10.15.60"
  key_name = "will_it_work"
  associate_public_ip_address = false
  vpc_security_group_ids = [aws_security_group.SecurityGroup2.id]
}