data "aws_availability_zones" "available" {}

resource "aws_vpc" "eks-vpc" {
  cidr_block = "10.200.0.0/16"

  tags = "${
    map(
      "Name", "eks-cluster",
      "kubernetes.io/cluster/var.cluster-name", "shared",
    )
  }"
}

resource "aws_subnet" "eks-subnet" {
  count = 3

  availability_zone = "${data.aws_availability_zones.available.names[count.index]}"
  cidr_block        = "10.200.${count.index}.0/24"
  vpc_id            = "${aws_vpc.eks-vpc.id}"

  tags = "${
    map(
      "Name", "eks-workernodes0${count.index}",
      "kubernetes.io/cluster/var.cluster-name", "shared",
    )
  }"
}

resource "aws_internet_gateway" "eks-gateway" {
  vpc_id = "${aws_vpc.eks-vpc.id}"

  tags = {
    Name = "eks-gateway"
  }
}

resource "aws_route_table" "eks-routetable" {
  vpc_id = "${aws_vpc.eks-vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.eks-gateway.id}"
  }
  tags = {
    Name = "eks-routetable"
  }
}

resource "aws_route_table_association" "eks-outbound" {
  count = 3

  subnet_id      = "${aws_subnet.eks-subnet.*.id[count.index]}"
  route_table_id = "${aws_route_table.eks-routetable.id}"
}

# Security groups for VPC
resource "aws_security_group" "eks-secgroup" {
  name        = "eks-secgroup"
  description = "Cluster communication with worker nodes"
  vpc_id      = "${aws_vpc.eks-vpc.id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-secgroup"
  }
}

resource "aws_security_group_rule" "ingress-workstation-https" {
  cidr_blocks       = ["A.B.C.D/32"]
  description       = "Allow https to cluster API Server"
  from_port         = 443
  protocol          = "tcp"
  security_group_id = "${aws_security_group.eks-secgroup.id}"
  to_port           = 443
  type              = "ingress"
}


# IAM Role and Policies
resource "aws_iam_role" "eks-role" {
  name = "eks-kubernetes-role"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "eks-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = "${aws_iam_role.eks-role.name}"
}

resource "aws_iam_role_policy_attachment" "eks-AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = "${aws_iam_role.eks-role.name}"
}


# EKS cluster
resource "aws_eks_cluster" "kubernetes-cluster" {
  name            = "${var.cluster-name}"
  role_arn        = "${aws_iam_role.eks-role.arn}"

  vpc_config {
    security_group_ids = ["${aws_security_group.eks-secgroup.id}"]
    subnet_ids         = flatten(["${aws_subnet.eks-subnet.*.id}"])
  }

  depends_on = [
    "aws_iam_role_policy_attachment.eks-AmazonEKSClusterPolicy",
    "aws_iam_role_policy_attachment.eks-AmazonEKSServicePolicy",
  ]
}
