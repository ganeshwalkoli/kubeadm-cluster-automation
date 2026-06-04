#!/bin/bash
set -e

echo "Starting Kubernetes Air-Gap Bundling Process..."

# 1.1 Create Download Directory Structure
mkdir -p ~/k8s-airgap/{rpms,images,cni,calico,configs}
cd ~/k8s-airgap

echo "Setting up repositories..."
# 1.2 Download Kubernetes & Docker RPM Packages
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.35/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.35/rpm/repodata/repomd.xml.key
EOF

sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

echo "Downloading RPMs..."
sudo dnf download --resolve --destdir=~/k8s-airgap/rpms \
  kubelet kubeadm kubectl containerd.io containernetworking-plugins

curl -sL -o ~/k8s-airgap/rpms/kubernetes-gpg.key \
  https://pkgs.k8s.io/core:/stable:/v1.35/rpm/repodata/repomd.xml.key

echo "Downloading Dependencies..."
sudo dnf download --resolve --destdir=~/k8s-airgap/rpms \
  socat conntrack ipset ipvsadm ebtables tc iproute-tc libseccomp

# 1.4 Pull & Export Kubernetes Core Images
K8S_VERSION="v1.35.0"
cd ~/k8s-airgap/images
echo "Pulling K8s Core Images..."
sudo kubeadm config images pull --kubernetes-version ${K8S_VERSION}

for image in $(sudo kubeadm config images list --kubernetes-version ${K8S_VERSION}); do
  filename=$(echo $image | tr '/:' '_')
  echo "Exporting $image → ${filename}.tar"
  sudo ctr -n k8s.io image export ${filename}.tar $image
done

# 1.5 Pull & Export Containerd Pause Image
PAUSE_IMAGE="registry.k8s.io/pause:3.9"
echo "Pulling Pause Image..."
sudo ctr image pull $PAUSE_IMAGE
sudo ctr image export ~/k8s-airgap/images/pause.tar $PAUSE_IMAGE

# 1.6 Download CNI Plugins
CNI_VERSION="v1.4.0"
cd ~/k8s-airgap/cni
echo "Downloading CNI plugins..."
curl -sL -O "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz"
curl -sL -O "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz.sha256"

# 1.7 Download & Export Calico Images
CALICO_VERSION="v3.27.0"
cd ~/k8s-airgap/calico
echo "Downloading Calico artifacts..."
curl -sL -O "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml"

CALICO_IMAGES=(
  "docker.io/calico/cni:${CALICO_VERSION}"
  "docker.io/calico/node:${CALICO_VERSION}"
  "docker.io/calico/kube-controllers:${CALICO_VERSION}"
)

for image in "${CALICO_IMAGES[@]}"; do
  sudo ctr image pull $image
  filename=$(echo $image | tr '/:' '_')
  sudo ctr image export ${filename}.tar $image
  echo "Exported: ${filename}.tar"
done

# 1.8 Create Repo Metadata for RPMs
echo "Generating local YUM repository metadata..."
sudo dnf install -y createrepo
createrepo ~/k8s-airgap/rpms/

# 1.9 Bundle Everything
echo "Creating final tarball..."
cd ~
tar -czf k8s-airgap-bundle.tar.gz k8s-airgap/
sha256sum k8s-airgap-bundle.tar.gz > k8s-airgap-bundle.sha256

echo "Bundling complete! Please transfer k8s-airgap-bundle.tar.gz to your air-gapped nodes."
echo "Bundle size: $(du -sh k8s-airgap-bundle.tar.gz)"
