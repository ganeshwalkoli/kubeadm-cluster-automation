#!/bin/bash
set -e

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <MINOR_VERSION> <FULL_PATCH_VERSION>"
    echo "Example: $0 1.34 1.34.2"
    echo "Example: $0 1.35 1.35.5"
    exit 1
fi

MINOR=$1
PATCH=$2

echo "========================================="
echo "🚀 Upgrading Node to Kubernetes v${PATCH}..."
echo "========================================="

echo "=> 1. Updating YUM Repository to v${MINOR} branch..."
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${MINOR}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${MINOR}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

echo "=> 2. Installing kubeadm-${PATCH}..."
sudo yum install -y kubeadm-${PATCH} --disableexcludes=kubernetes

echo "=> 3. Upgrading Kubernetes Components..."
# If the API server manifest exists, this is a Control Plane node
if [ -f "/etc/kubernetes/manifests/kube-apiserver.yaml" ]; then
    echo "👑 Control Plane detected. Running 'kubeadm upgrade apply'..."
    sudo kubeadm upgrade apply v${PATCH} -y
else
    echo "👷 Worker Node detected. Running 'kubeadm upgrade node'..."
    sudo kubeadm upgrade node
fi

echo "=> 4. Installing kubelet-${PATCH} and kubectl-${PATCH}..."
sudo yum install -y kubelet-${PATCH} kubectl-${PATCH} --disableexcludes=kubernetes

echo "=> 5. Restarting Kubelet Service..."
sudo systemctl daemon-reload
sudo systemctl restart kubelet

echo "========================================="
echo "✅ Node upgrade to v${PATCH} completed!"
echo "========================================="
