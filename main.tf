terraform {

  backend "s3" {
    bucket = "mytf-backend-21"
    key    = "kube-spray"
    region = "eu-central-1"
    profile = "my"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"

    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "eu-central-1"
  profile = "my"
}



data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}


# resource "aws_vpc" "main" {
#   cidr_block = "10.0.0.0/16"
#   enable_dns_support = true #gives you an internal domain name
#   enable_dns_hostnames = true #gives you an internal host name
#   tags = {
#     Name = "temporary"
#   }
# }

# resource "aws_subnet" "k8s-subnet-public-1" {
#     vpc_id = aws_vpc.main.id
#     cidr_block = "10.0.0.0/24"
#     map_public_ip_on_launch = true
#     availability_zone = "eu-central-1a"
#     tags = {
#         Name = "k8s-subnet-public-1"
#     }
# }

# resource "aws_internet_gateway" "k8s-igw" {
#     vpc_id =  aws_vpc.main.id
#     tags = {
#         Name = "k8s-igw"
#     }
# }

# resource "aws_route_table" "crt-prod-public" {
#     vpc_id = aws_vpc.main.id
    
#     route {
#         //associated subnet can reach everywhere
#         cidr_block = "0.0.0.0/0" 
#         //CRT uses this IGW to reach internet
#         gateway_id =  aws_internet_gateway.k8s-igw.id
#     }
    
#     tags = {
#         Name = "prod-public-crt"
#     }
# }

# resource "aws_route_table_association" "crta-k8s-subnet-public-1"{
#     subnet_id = aws_subnet.k8s-subnet-public-1.id
#     route_table_id = aws_route_table.crt-prod-public.id
# }

resource "aws_security_group" "kube_spray" {
  name        = "kube-spray"
  description = "Allow 22 and 6443"
  # vpc_id      = aws_vpc.main.id

  ingress {
    # description      = "6443 TLS from VPC"
    from_port        = 6443
    to_port          = 6443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  ingress {
    # description      = "22 TLS from VPC"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "kube-spray"
  }
}



resource "aws_instance" "masters" {
    count =      1
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.medium"
  
  key_name = "maxim.run v3"
  tags = {
    Name = "kube-master-${count.index}"
    Provisioner ="terraform"
    Purpose = "kube-spray"
  }

  vpc_security_group_ids = [aws_security_group.kube_spray.id]

  root_block_device {
    volume_size = "10"

  }


}


resource "aws_instance" "workers" {
  count         =  4
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.large"
  
  key_name = "maxim.run v3"
  tags = {
    Name = "kube-worker-${count.index}"
    Provisioner ="terraform"
    Purpose = "kube-spray"
  }

  # vpc_security_group_ids = ["kube-spray"]

  root_block_device {
    volume_size = "10"

  }

  ebs_block_device {
    tags = {
      Name = "kube-ebs-${count.index}"
      Provisioner ="terraform"
      Purpose = "kube-spray"
    }

    device_name = "/dev/sdb"
    volume_size = "20"

  }

}



# data "template_file" "init" {
#   template = file("${path.module}/inventory.tpl")
#   rendered =  file("${path.module}/inventory.yaml")
#   vars = {
#     masters = [for host in aws_instance.masters: { "name" : host.tags.Name, "ip" : host.public_ip }]
#     workers = [for host in aws_instance.workers: { "name" : host.tags.Name, "ip" : host.public_ip }]
#   }
# }

resource "time_sleep" "wait_60_seconds" {
  depends_on = [aws_instance.masters, aws_instance.workers]

  create_duration = "60s"
}


resource "local_file" "inventory" {
    content     = templatefile("inventory.tpl", {
          masters = [for host in aws_instance.masters: { "name" : host.tags.Name, "ip" : host.public_ip }]
          workers = [for host in aws_instance.workers: { "name" : host.tags.Name, "ip" : host.public_ip }]
        }
      )
    filename = "inventory.yaml"
    depends_on = [time_sleep.wait_60_seconds]

    
    provisioner "local-exec" {
      command = "ansible-playbook -i inventory.yaml cluster.yaml"
    }
}


output "public_ip" {
  value = concat (
    [for host in aws_instance.masters: { "name" : host.tags.Name, "ip" : host.public_ip }] ,
    [for host in aws_instance.workers: { "name" : host.tags.Name, "ip" : host.public_ip }] 

    )


}

