#!/bin/bash
set -e

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <FULL_PATCH_VERSION>"
    echo "Example: $0 1.35.5"
    exit 1
fi

PATCH=$1

echo "========================================="
echo "🚀 Initializing Kubernetes Control Plane..."
echo "========================================="

echo "=> 1. Running kubeadm init..."
sudo kubeadm init --pod-network-cidr=192.168.0.0/16 --kubernetes-version=v${PATCH}

echo "=> 2. Setting up kubeconfig for the current user..."
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

echo "=> 3. Installing Calico Network Plugin..."
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/custom-resources.yaml

echo "==========================================================="
echo "✅ Cluster Initialization Complete!"
echo "Please copy the 'kubeadm join' command printed above and"
echo "run it on your worker nodes to attach them to the cluster."
echo "==========================================================="
