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



resource "aws_security_group" "kube_spray" {
  name        = "kube-spray-${terraform.workspace}"
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

  ingress {
    # description      = "22 TLS from VPC"
    from_port        = 0 
    to_port          = 0 
    protocol         = "-1"
    # cidr_blocks      = ["0.0.0.0/0"]
    self             = true
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "kube-spray-${terraform.workspace}"
  }
}



resource "aws_instance" "masters" {
    count =      1
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.medium"
  
  key_name = "maxim.run v3"
  tags = {
    Name = "kube-master-${terraform.workspace}-${count.index}"
    Provisioner ="terraform"
    Purpose = "kube-spray"
  }


  security_groups = [aws_security_group.kube_spray.name]

  root_block_device {
    volume_size = "10"
    tags = {
      Name = "root-${terraform.workspace}-${count.index}"
      Provisioner = "terraform"
      Project = "hdfs-ceph"
      Purpose = "root"
    }

  }


}


resource "aws_instance" "workers" {
  count         =  4
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.large"
  
  key_name = "maxim.run v3"
  tags = {
    Name = "kube-worker-${terraform.workspace}-${count.index}"
    Provisioner ="terraform"
    Purpose = "kube-spray"
  }

  security_groups = [aws_security_group.kube_spray.name]

  root_block_device {
    volume_size = "10"

  }

  ebs_block_device {
    tags = {
      Name = "hdfs-ceph-${terraform.workspace}-${count.index}"
      Provisioner ="terraform"
      Project = "hdfs-ceph"
      Purpose = "hdfs-ceph"
    }

    device_name = "/dev/sdb"
    volume_size = "20"

  }

}



resource "time_sleep" "wait_100_seconds" {
  depends_on = [aws_instance.masters, aws_instance.workers]

  create_duration = "100s"
}


resource "local_file" "inventory" {
    content     = templatefile("inventory.tpl", {
          masters = [for host in aws_instance.masters: { "name" : host.tags.Name, "ip" : host.public_ip }]
          workers = [for host in aws_instance.workers: { "name" : host.tags.Name, "ip" : host.public_ip }]
        }
      )
    filename = "inventory.yaml"
    depends_on = [time_sleep.wait_100_seconds]

    
    provisioner "local-exec" {
      command = "ansible-playbook -i inventory.yaml -e tf_workspace=${terraform.workspace} cluster.yaml"
    }
}


output "public_ip" {
  value = concat (
    [for host in aws_instance.masters: { "name" : host.tags.Name, "ip" : host.public_ip }] ,
    [for host in aws_instance.workers: { "name" : host.tags.Name, "ip" : host.public_ip }] 

    )


}

