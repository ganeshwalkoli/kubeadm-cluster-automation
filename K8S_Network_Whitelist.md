# Kubernetes Air-Gapped Network Whitelist

This document outlines the required outbound FQDNs/URLs that must be allowed through the enterprise firewall for a fresh Kubernetes installation and all subsequent version upgrades using `kubeadm` (e.g., v1.33 through v1.36+). All traffic operates over standard **HTTPS (Port 443)**.

> [!IMPORTANT]
> If strict proxy rules prevent the whitelisting of underlying CDNs (like `*.s3.amazonaws.com` or `production.cloudflare.docker.com`), the industry-standard recommendation is to deploy an internal **Private Container Registry** (e.g., Harbor or AWS ECR) to host the Kubernetes and Calico images internally.

---

### 1. OS Package Downloads (YUM / RPM)
These domains are required for downloading the underlying system packages.

| FQDN / URL | Component | Purpose |
| :--- | :--- | :--- |
| `download.docker.com` | `containerd.io` | Required for `yum` to download the containerd package during initial setup. |
| `pkgs.k8s.io` | `kubeadm`, `kubelet`, `kubectl` | Required for `yum` to fetch Kubernetes package metadata and updates. |
| `prod-cdn.packages.k8s.io` | `kubeadm`, `kubelet`, `kubectl` | The actual backend CDN that serves the RPM files for installation and upgrades. |

---

### 2. Kubernetes Core Infrastructure
These domains are required by `kubeadm` to orchestrate the control plane.

| FQDN / URL | Component | Purpose |
| :--- | :--- | :--- |
| `registry.k8s.io` | Control Plane Pods | Required by `kubeadm` to download the core system container images (API server, etcd, CoreDNS, kube-proxy). |
| `*.s3.amazonaws.com` *(or `*.pkg.dev`)* | Control Plane Pods | `registry.k8s.io` redirects traffic to AWS S3 or GCP CDNs. Strict firewalls must allow these backend redirects to successfully pull images. |

---

### 3. Calico Network Plugin (CNI)
These domains are required to deploy the Tigera Operator and Calico networking mesh.

| FQDN / URL | Component | Purpose |
| :--- | :--- | :--- |
| `raw.githubusercontent.com` | Calico Manifests | Required to download the initial `tigera-operator.yaml` and `custom-resources.yaml` configuration files. |
| `quay.io` | Tigera Operator | Required to download the Tigera Operator container image, which manages the Calico installation. |
| `cdn.quay.io` | Tigera Operator | The backend CDN for Quay that actually serves the Tigera Operator image layers. |
| `docker.io` | Calico Node | Required by the Tigera operator to fetch the core Calico images from Docker Hub. |
| `registry-1.docker.io` | Calico Node | The Docker Hub API endpoint for authentication and image manifests. |
| `auth.docker.io` | Calico Node | The Docker Hub authentication server (even for anonymous public pulls). |
| `production.cloudflare.docker.com`| Calico Node | The backend Cloudflare CDN that actually serves the Calico container image layers. |

---

### 4. RHEL OS Updates
These domains are required for standard Red Hat Subscription Management (RHSM) on on-premises servers to receive OS patches and dependencies.

| FQDN / URL | Component | Purpose |
| :--- | :--- | :--- |
| `cdn.redhat.com` | RHEL base | Required for `yum` to download standard Red Hat OS updates and dependencies. |
| `subscription.rhsm.redhat.com` | RHSM | Red Hat Subscription Management API for license verification. |
| `cert.cdn.redhat.com` | RHSM | Endpoint for fetching repository certificates. |

---

### 5. GPG Keys
These domains host the security keys used by `yum` to verify the authenticity of the downloaded packages.

| FQDN / URL | Component | Purpose |
| :--- | :--- | :--- |
| `pkgs.k8s.io` | Kubernetes | Hosts the public GPG key for the official Kubernetes repositories. |
| `download.docker.com` | containerd | Hosts the public GPG key for the Docker/containerd repository. |
