#!/bin/bash
# Installs and configures workstation for EKS
# This assumes that you have a configured
# AWS CLI installtion
KUBE_CLUSTER=
AWS_REGION=

# Add Kubernetes repositories
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF

# Install and configure kubectl
yum update
yum install -y kubelet
mkdir $HOME/.kube && touch $HOME/.kube/config 
aws eks get-token --cluster-name $KUBE_CLUSTER
aws eks --region $AWS_REGION update-kubeconfig --name $KUBE_CLUSTER

# Install and configure aws-iam-authenticator
curl -o aws-iam-authenticator https://amazon-eks.s3-us-west-2.amazonaws.com/1.13.7/2019-06-11/bin/linux/amd64/aws-iam-authenticator --output $HOME
chmod +x $HOME/aws-iam-authenticator
mkdir -p $HOME/bin && cp $HOME/aws-iam-authenticator $HOME/bin/aws-iam-authenticator && export PATH=$HOME/bin:$PATH
echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc
