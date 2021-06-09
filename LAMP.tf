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
  availability_zone = "us-east-1b"
  tags = {
    "Name" = "Public Subnet"
  }
}

resource "aws_subnet" "PublicSubnet2" {
  vpc_id = aws_vpc.MainVPC.id
  cidr_block = "10.10.20.0/24"
  availability_zone = "us-east-1a"

  tags = {
    "Name" = "Public Subnet 2"
  }
}

# resource "aws_subnet" "PrivateSubnet" {
#   vpc_id = aws_vpc.MainVPC.id
#   cidr_block = "10.10.15.0/24"

#   tags = {
#     "Name" = "Private Subnet"
#   }
# }

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
          cidr_block = ["0.0.0.0/0"]
          description = "Web Server Access"
          from_port = 80
          protocol = "tcp"
          to_port = 80
        },
        {
          cidr_block = ["0.0.0.0/0"]
          description = "SSh Access"
          from_port = 22
          protocol = "tcp"
          to_port = 22
        },
        {
          cidr_block = ["0.0.0.0/0"]
          description = "HTTPS"
          from_port = 443
          protocol = "tcp"
          to_port = 443
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
  tags = {
    Name = "PrivateSubnet"
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
  tags = {
    Name = "PublicSubnet"
  }

}

resource "aws_eip" "ngEIP" {
  vpc      = false

}


# resource "aws_nat_gateway" "PublicSubnetNAT" {
#   allocation_id = aws_eip.ngEIP.id
#   subnet_id = aws_subnet.PublicSubnet.id

#   tags = {
#     "Name" = "PublicNG"
#   }

#   depends_on = [aws_internet_gateway.gw]
  
# }

# resource "aws_route_table" "MainVPCPrivateRouteTable" {
#   vpc_id = aws_vpc.MainVPC.id

#   route {
#     cidr_block = "0.0.0.0/0"
#     nat_gateway_id = aws_nat_gateway.PublicSubnetNAT.id
    
#   }

#   tags = {
#     Name = "MainVPCPrivateRouteTable"
#   }

# }

resource "aws_route_table" "MainVPCPublicRouteTable" {
  vpc_id = aws_vpc.MainVPC.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
    
  }

  tags = {
    Name = "MainVPCPublicRouteTable"
  }
}

resource "aws_route_table" "MainVPCPublicRouteTable2" {
  vpc_id = aws_vpc.MainVPC.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
    
  }

  tags = {
    Name = "MainVPCPublicRouteTable2"
  }

}

resource "aws_route_table_association" "a" {
  subnet_id = aws_subnet.PublicSubnet.id
  route_table_id = aws_route_table.MainVPCPublicRouteTable.id
  
}

resource "aws_route_table_association" "b" {
  subnet_id = aws_subnet.PublicSubnet2.id
  route_table_id = aws_route_table.MainVPCPublicRouteTable2.id
  
}

# resource "aws_route_table_association" "c" {
#   subnet_id = aws_subnet.PrivateSubnet.id
#   route_table_id = aws_route_table.MainVPCPrivateRouteTable.id
  
# }

resource "aws_launch_template" "launch_template" {
  image_id = "ami-0d5eff06f840b45e9"
  instance_type = "t2.micro"
  key_name = "terraform_deploy"
  name_prefix = "ASG-"
  vpc_security_group_ids = [aws_security_group.SecurityGroup2.id]
  
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "test"
    }
  }

  user_data = "${base64encode(<<EOF
  #!/bin/bash
  sudo yum install httpd -y
  sudo echo $hostname > /var/www/html/index.txt
  sudo systemctl start httpd
  EOF
  )}"
}

resource "aws_autoscaling_group" "asg" {
  max_size = 5
  min_size = 0
  desired_capacity = 2
  health_check_type = "ELB"
  health_check_grace_period = "360"
  target_group_arns = [aws_lb_target_group.lb-tg.arn]
  vpc_zone_identifier = [ aws_subnet.PublicSubnet.id, aws_subnet.PublicSubnet2.id ]
  
  launch_template {
    id = aws_launch_template.launch_template.id
    version = "$Latest"
  }
  
}

resource "aws_lb" "elb" {
  name = "MainELB"
  subnets = [aws_subnet.PublicSubnet.id, aws_subnet.PublicSubnet2.id]
  load_balancer_type = "application"
  internal = false
  
}

resource "aws_lb_target_group" "lb-tg"{
  name = "tf-lb-tg"
  port = 80
  protocol = "HTTP"
  vpc_id = aws_vpc.MainVPC.id

}

resource "aws_lb_listener" "lb_listener"{
  load_balancer_arn = aws_lb.elb.id
  port = 80
  protocol = "HTTP"

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.lb-tg.arn
  }


}



# resource "aws_autoscaling_attachment" "asg_attachment"{
#   autoscaling_group_name = aws_autoscaling_group.asg.id
#   elb = aws_lb.elb.id
# }

# resource "aws_instance" "EC2WEB" {
#   ami = "ami-0d5eff06f840b45e9"
#   instance_type = "t2.micro"
#   subnet_id = aws_subnet.PublicSubnet.id
#   private_ip = "10.10.10.25"
#   associate_public_ip_address = true
#   key_name = "will_it_work"
#   vpc_security_group_ids = [aws_security_group.SecurityGroup1.id]
# }

# resource "aws_instance" "JumpBox" {
#   ami = "ami-0d5eff06f840b45e9"
#   instance_type = "t2.micro"
#   subnet_id = aws_subnet.PublicSubnet.id
#   associate_public_ip_address = true
#   private_ip = "10.10.10.30"
#   key_name = "terraform_deploy"
#   vpc_security_group_ids = [aws_security_group.SecurityGroup2.id]
# }

# resource "aws_instance" "MySQL" {
#   ami = "ami-0d5eff06f840b45e9"
#   instance_type = "t2.micro"
#   subnet_id = aws_subnet.PrivateSubnet.id
#   private_ip = "10.10.15.60"
#   key_name = "will_it_work"
#   associate_public_ip_address = false
#   vpc_security_group_ids = [aws_security_group.SecurityGroup2.id]
# }