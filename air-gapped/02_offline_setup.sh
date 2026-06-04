#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

if [ ! -f "/tmp/k8s-airgap-bundle.tar.gz" ]; then
  echo "Error: /tmp/k8s-airgap-bundle.tar.gz not found! Please transfer the bundle to /tmp first."
  exit 1
fi

echo "Extracting bundle..."
cd /tmp
sha256sum -c k8s-airgap-bundle.sha256 || { echo "Checksum failed!"; exit 1; }
tar -xzf k8s-airgap-bundle.tar.gz -C /opt/

echo "Setting up local YUM repository..."
cat <<EOF > /etc/yum.repos.d/k8s-local.repo
[k8s-local]
name=Kubernetes Local Repo
baseurl=file:///opt/k8s-airgap/rpms
enabled=1
gpgcheck=0
EOF

echo "Installing RPM packages..."
dnf clean all
dnf install -y --disablerepo="*" --enablerepo="k8s-local" \
  kubelet kubeadm kubectl containerd.io socat conntrack ipset ipvsadm ebtables iproute-tc libseccomp iptables iptables-libs

echo "Extracting CNI plugins..."
mkdir -p /opt/cni/bin
tar -xzf /opt/k8s-airgap/cni/cni-plugins-linux-amd64-*.tgz -C /opt/cni/bin/

echo "Configuring containerd..."
containerd config default > /etc/containerd/config.toml
sed -i 's|sandbox_image = .*|sandbox_image = "registry.k8s.io/pause:3.10"|' /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable --now containerd

echo "Importing Container Images..."
for tar in /opt/k8s-airgap/images/*.tar; do
  echo "Importing $tar..."
  ctr -n k8s.io image import $tar
done

for tar in /opt/k8s-airgap/calico/*.tar; do
  echo "Importing $tar..."
  ctr -n k8s.io image import $tar
done

echo "Applying System Pre-flight configs..."
swapoff -a
sed -i '/swap/d' /etc/fstab

modprobe overlay || true
modprobe br_netfilter || true
modprobe nf_conntrack || true

cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
nf_conntrack
EOF

cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

setenforce 0 || true
sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

echo "Offline setup complete! containerd and kubelet are ready."
