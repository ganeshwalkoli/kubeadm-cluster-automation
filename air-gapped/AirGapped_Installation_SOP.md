# Kubernetes 1.35 Air-Gapped Installation SOP

This document outlines the procedure to install Kubernetes in a strictly air-gapped environment where nodes have zero internet access.

## Prerequisites
- An **Online Machine** (RHEL 9) with internet access and Docker installed.
- The **Air-Gapped Nodes** (RHEL 9) where Kubernetes will be installed.
- A secure method to transfer files between the online machine and air-gapped nodes (e.g., Secure USB, internal file server).

---

## 1. Private Container Registry Setup (On Air-Gapped Network)

To serve container images to your cluster, you must run a private registry inside the air-gapped network. We will use the official Docker `registry:2` image.

### Step 1.1: Download Registry Image (Online Machine)
On your internet-connected machine, pull and save the registry image:
```bash
docker pull registry:2
docker save registry:2 > registry_image.tar
```
*Transfer `registry_image.tar` to your air-gapped registry server.*

### Step 1.2: Start the Registry (Air-Gapped Server)
On the air-gapped server that will act as your registry (assuming Docker is installed):
```bash
# Load the image
docker load < registry_image.tar

# Run the registry on port 5000
docker run -d -p 5000:5000 --restart=always --name private-registry registry:2
```
*Note: In a production environment, you must configure TLS/SSL for this registry so `containerd` can pull securely, or configure `containerd` on all nodes to treat `http://<REGISTRY_IP>:5000` as an insecure registry.*

---

## 2. Prepare Container Images

You need to pull all necessary Kubernetes and Calico images, move them across the air gap, and push them to your new private registry.

### Step 2.1: Pull and Save Images (Online Machine)
```bash
# Get the list of required Kubernetes images
kubeadm config images list --kubernetes-version v1.35.0 > k8s_images.txt

# Pull each K8s image
for i in $(cat k8s_images.txt); do docker pull $i; done

# Pull Calico images (Tigera operator & Calico node)
docker pull quay.io/tigera/operator:v1.34.0 # (Use your specific Calico version)
docker pull docker.io/calico/cni:v3.28.0
docker pull docker.io/calico/node:v3.28.0
docker pull docker.io/calico/kube-controllers:v3.28.0

# Save all images to a tarball
docker save $(cat k8s_images.txt) quay.io/tigera/operator:v1.34.0 calico/cni:v3.28.0 calico/node:v3.28.0 calico/kube-controllers:v3.28.0 > all_k8s_images.tar
```
*Transfer `all_k8s_images.tar` to a machine in the air-gapped network.*

### Step 2.2: Push to Private Registry (Air-Gapped Network)
Load the tarball and push them to your new private registry (`<REGISTRY_IP>:5000`):
```bash
docker load < all_k8s_images.tar

# Tag and push each image (Example for kube-apiserver)
docker tag registry.k8s.io/kube-apiserver:v1.35.0 <REGISTRY_IP>:5000/kube-apiserver:v1.35.0
docker push <REGISTRY_IP>:5000/kube-apiserver:v1.35.0

# Repeat the tag and push for ALL K8s and Calico images
```

---

## 3. Create a Local YUM/RPM Repository

You must provide the RPM packages (like `containerd`, `kubeadm`, `kubelet`, `kubectl`) to the offline nodes without relying on `pkgs.k8s.io`.

### Step 3.1: Download RPMs (Online Machine)
On a RHEL 9 online machine, download the required packages and their dependencies:
```bash
# Add the K8s and Docker repo configurations first
# Then use yumdownloader/dnf download to fetch packages but not install them
mkdir -p /root/k8s-rpms
cd /root/k8s-rpms
dnf download --resolve --alldeps containerd.io kubeadm kubelet kubectl

# Install createrepo to generate repo metadata
dnf install -y createrepo
createrepo /root/k8s-rpms

# Archive the directory for transfer
cd /root
tar -czvf k8s-rpms.tar.gz k8s-rpms/
```
*Transfer `k8s-rpms.tar.gz` to your air-gapped nodes.*

### Step 3.2: Configure YUM (Air-Gapped Nodes)
Transfer the `k8s-rpms.tar.gz` archive to the air-gapped node and extract it to `/opt`:
```bash
# Extract the archive
tar -xzvf k8s-rpms.tar.gz -C /opt/
```

Create a local repo file: `/etc/yum.repos.d/local-k8s.repo`
```ini
[local-k8s]
name=Local Kubernetes Repository
baseurl=file:///opt/k8s-rpms
enabled=1
gpgcheck=0
```
Install the packages:
```bash
dnf install -y containerd.io kubelet kubeadm kubectl
systemctl enable --now kubelet
```

---

## 4. Install Kubernetes using Offline Resources

Now that the packages are installed and the private registry is populated, you must instruct `kubeadm` and Calico to use them.

### Step 4.1: Run Kubeadm Init
When initializing the control plane, tell `kubeadm` to pull from your private registry instead of the internet:
```bash
kubeadm init \
  --image-repository <REGISTRY_IP>:5000 \
  --kubernetes-version v1.35.0 \
  --pod-network-cidr=192.168.0.0/16
```

### Step 4.2: Adjust Calico Manifests
Before applying Calico, edit the `tigera-operator.yaml` and `custom-resources.yaml` files.
Find all instances of `quay.io/` or `docker.io/` and replace them with `<REGISTRY_IP>:5000/`.

Apply the modified files:
```bash
kubectl create -f tigera-operator.yaml
kubectl create -f custom-resources.yaml
```

The cluster will now successfully provision completely offline!
