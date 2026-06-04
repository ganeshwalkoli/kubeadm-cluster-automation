#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

MASTER_IP=$(hostname -I | awk '{print $1}')
echo "Detected Master IP: $MASTER_IP"

echo "Generating kubeadm config..."
cat <<EOF > /opt/k8s-airgap/configs/kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v1.35.5
imageRepository: registry.k8s.io
networking:
  podSubnet: "192.168.0.0/16"
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: ${MASTER_IP}
  bindPort: 6443
EOF

echo "Initializing Kubernetes Cluster..."
kubeadm init --config=/opt/k8s-airgap/configs/kubeadm-config.yaml --upload-certs --ignore-preflight-errors=FileContent--proc-sys-net-bridge-bridge-nf-call-iptables,FileContent--proc-sys-net-bridge-bridge-nf-call-ip6tables

echo "Configuring kubectl for root..."
export KUBECONFIG=/etc/kubernetes/admin.conf
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

echo "Applying Calico CNI..."
kubectl apply -f /opt/k8s-airgap/calico/calico.yaml

echo ""
echo "=========================================================================="
echo "Control Plane Initialized Successfully!"
echo "Please save the 'kubeadm join' command printed above to use on your workers."
echo "=========================================================================="
