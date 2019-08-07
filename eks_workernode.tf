resource "aws_iam_role" "eks-workernode-role" {
  name = "eks-workernode-role"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "eks-wokernode-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = "${aws_iam_role.eks-workernode-role.name}"
}

resource "aws_iam_role_policy_attachment" "eks-workernode-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = "${aws_iam_role.eks-workernode-role.name}"
}

resource "aws_iam_role_policy_attachment" "eks-workernode-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = "${aws_iam_role.eks-workernode-role.name}"
}

resource "aws_iam_instance_profile" "eks-workernode-profile" {
  name = "eks-workernode-profile"
  role = "${aws_iam_role.eks-workernode-role.name}"
}

# EKS Secgroup
resource "aws_security_group" "eks-workernode-secgroup" {
  name        = "eks-workernode-secgroup"
  description = "Security group for all nodes in the cluster"
  vpc_id      = "${aws_vpc.eks-vpc.id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = "${
    map(
     "Name", "eks-workernode-secgroup",
     "kubernetes.io/cluster/${var.cluster-name}", "owned",
    )
  }"
}

resource "aws_security_group_rule" "workernode-ingress-self" {
  description              = "Allow node to communicate with each other"
  from_port                = 0
  protocol                 = "-1"
  security_group_id        = "${aws_security_group.eks-workernode-secgroup.id}"
  source_security_group_id = "${aws_security_group.eks-secgroup.id}"
  to_port                  = 65535
  type                     = "ingress"
}

resource "aws_security_group_rule" "workernode-ingress-cluster" {
  description              = "Allow worker Kubelets and pods to receive communication from the cluster control plane"
  from_port                = 1025
  protocol                 = "tcp"
  security_group_id        = "${aws_security_group.eks-workernode-secgroup.id}"
  source_security_group_id = "${aws_security_group.eks-secgroup.id}"
  to_port                  = 65535
  type                     = "ingress"
}


data "aws_ami" "eks-workernode" {
  filter {
    name   = "name"
    values = ["amazon-eks-node-${aws_eks_cluster.kubernetes-cluster.version}-v*"]
  }

  most_recent = true
  owners      = ["602401143452"] # Amazon EKS AMI Account ID
}

# EKS currently documents this required userdata for EKS worker nodes to
# properly configure Kubernetes applications on the EC2 instance.
# We implement a Terraform local here to simplify Base64 encoding this
# information into the AutoScaling Launch Configuration.
# More information: https://docs.aws.amazon.com/eks/latest/userguide/launch-workers.html
locals {
  workernode-userdata = <<USERDATA
#!/bin/bash
set -o xtrace
/etc/eks/bootstrap.sh --apiserver-endpoint '${aws_eks_cluster.kubernetes-cluster.endpoint}' --b64-cluster-ca '${aws_eks_cluster.kubernetes-cluster.certificate_authority.0.data}' '${var.cluster-name}'
USERDATA
}

resource "aws_launch_configuration" "eks-asgroup-config" {
  associate_public_ip_address = true
  iam_instance_profile        = "${aws_iam_instance_profile.eks-workernode-profile.name}"
  image_id                    = "${data.aws_ami.eks-workernode.id}"
  instance_type               = "m4.large"
  name_prefix                 = "eks-asgroup"
  security_groups             = ["${aws_security_group.eks-workernode-secgroup.id}"]
  user_data_base64            = "${base64encode(local.workernode-userdata)}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "eks-asgroup" {
  desired_capacity     = 2
  launch_configuration = "${aws_launch_configuration.eks-asgroup-config.id}"
  max_size             = 3
  min_size             = 1
  name                 = "eks-asgroup"
  vpc_zone_identifier  = flatten(["${aws_subnet.eks-subnet.*.id}"])

  tag {
    key                 = "Name"
    value               = "eks-asgroup"
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.cluster-name}"
    value               = "owned"
    propagate_at_launch = true
  }
}
