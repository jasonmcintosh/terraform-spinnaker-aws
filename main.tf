provider "aws" {
  assume_role {
    role_arn     = "${var.arn_master_account}"
    session_name = "SpinnakerCreation"
  }
}

data "aws_iam_policy_document" "spinnaker_iam_policy" {
  Statement {
    Action = [
      "iam:*",
      "ec2:*",
      "s3:*",
      "sts:PassRole",
      "sts:AssumeRole",
    ]

    Effect   = "Allow"
    Resource = ["*"]
  }
}

data "aws_iam_policy_document" "ec2_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "spinnaker_policy" {
  name        = "SpinnakerServerPolicy"
  policy      = "${data.aws_iam_policy_document.spinnaker_iam_policy.json}"
  path        = "/spinnaker"
  description = "Policy allowing Spinnaker to do actions in various other accounts"
}

resource "aws_iam_role" "spinnaker_role" {
  name               = "SpinnakerServerRole"
  path               = "/spinnaker"
  description        = "Role allowing spinnaker to do operations on systems"
  assume_role_policy = "${data.aws_iam_policy_document.ec2_assume_role_policy.json}"
}

resource "aws_iam_instance_profile" "profile_for_role" {
  role_name = "${aws_iam_role.spinnaker_role.arn}"
  name      = "SpinnakerInstanceProfile"
}

###############################################################
## NORMALLY would suggest NOT creating these here but in a base account configuration.  VPC's tend to be a more complicated discussion
## point particularly if you need to peer resources deal with IPAM and allocation and similar concepts.  BUT for the purposes of a test...
###############################################################
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "ManagementVpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.253.0/24", "10.0.254.0/24", "10.0.255.0/24"]

  enable_nat_gateway = true
  enable_vpn_gateway = false

  private_subnet_tags = {
    name               = "ManagementVpc.internal.us-east-1"
    immutable_metadata = "{'purpose':'internal'}"
  }

  public_subnet_tags = {
    name               = "ManagementVpc.external.us-east-1"
    immutable_metadata = "{'purpose':'external'}"
  }
}

resource "aws_key_pair" "deployer" {
  key_name   = "spinnaker-deploy-key"
  public_key = "${file("~/.ssh/id_rsa.pub")}"
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_security_group" "allow_ssh_web_to_spinnaker" {
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 8080
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  vpc_id = "${module.vpc.vpc_id}"
}

resource "aws_instance" "halyard_server" {
  ami                    = "${data.aws_ami.ubuntu.id}"
  instance_type          = "m5.xlarge"
  key_name               = "${aws_key_pair.login.id}"
  vpc_security_group_ids = ["${data.aws_security_group.allow_ssh_web_to_spinnaker.id}"]
  iam_instance_profile   = "${aws_iam_instance_profile.profile_for_role.arn}"
}
