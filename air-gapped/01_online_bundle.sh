#!/bin/bash
WORK_DIR="${PWD}/k8s-airgap"
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root using sudo"
  exit 1
fi

echo "Starting Kubernetes Air-Gap Bundling Process..."

# 1.1 Create Download Directory Structure
mkdir -p ${WORK_DIR}/{rpms,images,cni,calico,configs}
cd ${WORK_DIR}

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

echo "Installing local tools required for bundling..."
sudo dnf install -y containerd.io kubeadm-1.35.5
sudo containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo systemctl restart containerd
sudo systemctl enable --now containerd

echo "Downloading RPMs..."
sudo dnf download --resolve --destdir=${WORK_DIR}/rpms \
  kubelet-1.35.5*.$(uname -m) kubeadm-1.35.5*.$(uname -m) kubectl-1.35.5*.$(uname -m) containerd.io containernetworking-plugins

curl -sL -o ${WORK_DIR}/rpms/kubernetes-gpg.key \
  https://pkgs.k8s.io/core:/stable:/v1.35/rpm/repodata/repomd.xml.key

echo "Downloading Dependencies..."
sudo dnf download --resolve --destdir=${WORK_DIR}/rpms \
  socat conntrack ipset ipvsadm ebtables iproute-tc libseccomp iptables iptables-libs

# 1.4 Pull & Export Kubernetes Core Images
K8S_VERSION="v1.35.5"
cd ${WORK_DIR}/images
echo "Pulling K8s Core Images..."
sudo kubeadm config images pull --kubernetes-version ${K8S_VERSION}

for image in $(sudo kubeadm config images list --kubernetes-version ${K8S_VERSION}); do
  filename=$(echo $image | tr '/:' '_')
  echo "Exporting $image → ${filename}.tar"
  sudo ctr -n k8s.io image export ${filename}.tar $image
done

# 1.5 Pull & Export Containerd Pause Image
PAUSE_IMAGE="registry.k8s.io/pause:3.10"
echo "Pulling Pause Image..."
sudo ctr image pull $PAUSE_IMAGE
sudo ctr image export ${WORK_DIR}/images/pause.tar $PAUSE_IMAGE

# 1.6 Download CNI Plugins
CNI_VERSION="v1.5.0"
cd ${WORK_DIR}/cni
echo "Downloading CNI plugins..."
curl -sL -O "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz"
curl -sL -O "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz.sha256"

# 1.7 Download & Export Calico Images
CALICO_VERSION="v3.28.0"
cd ${WORK_DIR}/calico
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
sudo createrepo ${WORK_DIR}/rpms/

# 1.9 Bundle Everything
echo "Creating final tarball..."
cd ${WORK_DIR}/..
tar -czf k8s-airgap-bundle.tar.gz k8s-airgap/
sha256sum k8s-airgap-bundle.tar.gz > k8s-airgap-bundle.sha256

echo "Bundling complete! Please transfer k8s-airgap-bundle.tar.gz to your air-gapped nodes."
echo "Bundle size: $(du -sh k8s-airgap-bundle.tar.gz)"
