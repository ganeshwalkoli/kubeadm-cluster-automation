# Kubernetes Air-Gapped Setup — Tarball / Offline Bundle

## Architecture Overview
`[Internet-Connected Machine] → Download Everything → Bundle → Transfer (USB/SCP/SFTP) → [Air-Gapped Machine] → Install`

## STEP 1: On Internet-Connected Machine — Download Everything

### 1.1 Create Download Directory Structure
```bash
mkdir -p ~/k8s-airgap/{rpms,images,cni,calico,configs}
cd ~/k8s-airgap
```

### 1.2 Download Kubernetes & Docker RPM Packages
```bash
# Add Kubernetes repo
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.35/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.35/rpm/repodata/repomd.xml.key
EOF

# Add Docker CE repo for containerd
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# Download RPMs with all dependencies
dnf download --resolve --destdir=~/k8s-airgap/rpms \
  kubelet-1.35.5*.$(uname -m) \
  kubeadm-1.35.5*.$(uname -m) \
  kubectl-1.35.5*.$(uname -m) \
  containerd.io \
  containernetworking-plugins

# Download GPG key
curl -o ~/k8s-airgap/rpms/kubernetes-gpg.key \
  https://pkgs.k8s.io/core:/stable:/v1.35/rpm/repodata/repomd.xml.key
```

### 1.3 Download RHEL/CentOS Dependencies
```bash
dnf download --resolve --destdir=~/k8s-airgap/rpms \
  socat \
  conntrack \
  ipset \
  ipvsadm \
  ebtables \
  tc \
  iproute-tc \
  libseccomp \
  iptables \
  iptables-libs
```

### 1.4 Pull & Export Kubernetes Core Images
```bash
K8S_VERSION="v1.35.5"
cd ~/k8s-airgap/images

# Pull all required kubeadm images
kubeadm config images pull --kubernetes-version ${K8S_VERSION}

# List and export each image
for image in $(kubeadm config images list --kubernetes-version ${K8S_VERSION}); do
  filename=$(echo $image | tr '/:' '_')
  echo "Exporting $image → ${filename}.tar"
  ctr -n k8s.io image export ${filename}.tar $image
done
```

### 1.5 Pull & Export Containerd Pause Image
```bash
PAUSE_IMAGE="registry.k8s.io/pause:3.10"
ctr image pull $PAUSE_IMAGE
ctr image export ~/k8s-airgap/images/pause.tar $PAUSE_IMAGE
```

### 1.6 Download CNI Plugins
```bash
CNI_VERSION="v1.5.0"
cd ~/k8s-airgap/cni

curl -LO "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz"
curl -LO "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz.sha256"
```

### 1.7 Download & Export Calico Images
```bash
CALICO_VERSION="v3.28.0"
cd ~/k8s-airgap/calico

# Download Calico manifests
curl -LO "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml"

# Pull Calico images
CALICO_IMAGES=(
  "docker.io/calico/cni:${CALICO_VERSION}"
  "docker.io/calico/node:${CALICO_VERSION}"
  "docker.io/calico/kube-controllers:${CALICO_VERSION}"
)

for image in "${CALICO_IMAGES[@]}"; do
  ctr image pull $image
  filename=$(echo $image | tr '/:' '_')
  ctr image export ${filename}.tar $image
  echo "Exported: ${filename}.tar"
done
```

### 1.8 Create Repo Metadata for RPMs
```bash
# Install createrepo if not present
dnf install -y createrepo

# Generate local repo metadata
createrepo ~/k8s-airgap/rpms/
```

### 1.9 Bundle Everything
```bash
cd ~
tar -czvf k8s-airgap-bundle.tar.gz k8s-airgap/

# Generate checksum for verification
sha256sum k8s-airgap-bundle.tar.gz > k8s-airgap-bundle.sha256

echo "Bundle size: $(du -sh k8s-airgap-bundle.tar.gz)"
```

## STEP 2: Transfer Bundle to Air-Gapped Environment
```bash
# Option A — SCP
scp k8s-airgap-bundle.tar.gz user@airgap-server:/tmp/

# Option B — USB (mount and copy)
cp k8s-airgap-bundle.tar.gz /media/usb-drive/

# Option C — SFTP
sftp user@airgap-server
> put k8s-airgap-bundle.tar.gz /tmp/
```

## STEP 3: On Air-Gapped Machine — Extract Bundle
```bash
cd /tmp
# Verify checksum
sha256sum -c k8s-airgap-bundle.sha256

# Extract
tar -xzvf k8s-airgap-bundle.tar.gz -C /opt/
cd /opt/k8s-airgap
```

## STEP 4: Install on Air-Gapped Nodes

### 4.1 Setup Local YUM Repository
```bash
cat <<EOF | sudo tee /etc/yum.repos.d/k8s-local.repo
[k8s-local]
name=Kubernetes Local Repo
baseurl=file:///opt/k8s-airgap/rpms
enabled=1
gpgcheck=1
gpgkey=file:///opt/k8s-airgap/rpms/kubernetes-gpg.key
EOF

# Disable all other repos to avoid internet calls
dnf clean all
dnf install -y --disablerepo="*" --enablerepo="k8s-local" \
  kubelet kubeadm kubectl containerd.io \
  socat conntrack ipset ipvsadm ebtables iproute-tc libseccomp iptables iptables-libs
```

### 4.2 Install CNI Plugins
```bash
mkdir -p /opt/cni/bin
tar -xzvf /opt/k8s-airgap/cni/cni-plugins-linux-amd64-*.tgz -C /opt/cni/bin/
```

### 4.3 Configure Containerd
```bash
# Generate default config
containerd config default > /etc/containerd/config.toml

# Update sandbox (pause) image to local if using private registry
sed -i 's|sandbox_image = .*|sandbox_image = "registry.k8s.io/pause:3.10"|' \
  /etc/containerd/config.toml

# Use systemd cgroup driver
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' \
  /etc/containerd/config.toml

systemctl enable --now containerd
```

### 4.4 Import All Container Images
```bash
# Import Kubernetes core images
for tar in /opt/k8s-airgap/images/*.tar; do
  echo "Importing $tar..."
  ctr -n k8s.io image import $tar
done

# Import Calico images
for tar in /opt/k8s-airgap/calico/*.tar; do
  echo "Importing $tar..."
  ctr -n k8s.io image import $tar
done

# Verify all images loaded
crictl images
```

### 4.5 Pre-flight System Config
```bash
# Disable swap
swapoff -a
sed -i '/swap/d' /etc/fstab

# Load kernel modules
modprobe overlay || true
modprobe br_netfilter || true
modprobe nf_conntrack || true

cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
nf_conntrack
EOF

# Kernel parameters
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

# Disable SELinux (or set to permissive)
setenforce 0
sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
```

### 4.6 Initialize Kubernetes Cluster
```bash
# Create kubeadm config (offline mode)
cat <<EOF > /opt/k8s-airgap/configs/kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v1.35.5
imageRepository: registry.k8s.io   # Uses locally imported images
networking:
  podSubnet: "192.168.0.0/16"       # Calico default
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: <MASTER-NODE-IP>
  bindPort: 6443
EOF

# Initialize — will use locally imported images
kubeadm init \
  --config=/opt/k8s-airgap/configs/kubeadm-config.yaml \
  --upload-certs

# Setup kubectl access
mkdir -p $HOME/.kube
cp /etc/kubernetes/admin.conf $HOME/.kube/config
```

### 4.7 Apply Calico CNI (Offline)
```bash
# Apply directly from local file
kubectl apply -f /opt/k8s-airgap/calico/calico.yaml

# Verify nodes and pods
kubectl get nodes
kubectl get pods -A
```

### 4.8 Join Worker Nodes
```bash
# On master — get join command
kubeadm token create --print-join-command

# Copy bundle to each worker node and repeat Steps 4.1 to 4.5
# Then run the join command on each worker
kubeadm join <MASTER-IP>:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

---

## Complete Checklist

| Task | Status |
| :--- | :--- |
| RPM packages downloaded with dependencies | ✅ |
| createrepo metadata generated | ✅ |
| All k8s core images exported as tarballs | ✅ |
| Calico images exported as tarballs | ✅ |
| CNI plugins tarball downloaded | ✅ |
| Bundle transferred to air-gapped machine | ✅ |
| Local YUM repo configured | ✅ |
| Images imported via ctr | ✅ |
| Containerd configured with systemd cgroup | ✅ |
| kubeadm init completed successfully | ✅ |
| Calico CNI applied | ✅ |
| Worker nodes joined | ✅ |
