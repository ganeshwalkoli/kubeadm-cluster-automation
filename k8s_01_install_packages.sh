#!/bin/bash
set -e

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <MINOR_VERSION> <FULL_PATCH_VERSION>"
    echo "Example: $0 1.35 1.35.5"
    exit 1
fi

MINOR=$1
PATCH=$2

echo "========================================="
echo "🚀 Installing Kubernetes v${PATCH} Packages..."
echo "========================================="

echo "=> 1. Disabling Swap..."
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

echo "=> 2. Loading Kernel Modules..."
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

echo "=> 3. Setting sysctl parameters..."
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system

echo "=> 4. Installing containerd runtime..."
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf install -y containerd.io
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
# Configure containerd to use systemd as the cgroup driver
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl enable --now containerd

echo "=> 5. Configuring Kubernetes Repository (v${MINOR})..."
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${MINOR}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${MINOR}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

echo "=> 6. Installing kubeadm, kubelet, and kubectl (${PATCH})..."
sudo yum install -y kubelet-${PATCH} kubeadm-${PATCH} kubectl-${PATCH} --disableexcludes=kubernetes
sudo systemctl enable --now kubelet

echo "========================================="
echo "✅ Package installation complete!"
echo "If this is the Control Plane, run the init script next."
echo "If this is a Worker Node, run the 'kubeadm join' command."
echo "========================================="
