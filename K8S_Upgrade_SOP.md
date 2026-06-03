# Kubernetes Cluster Upgrade SOP (kubeadm on RHEL 9)

This Standard Operating Procedure details the steps to safely perform a minor-version upgrade (e.g., v1.35.x to v1.36.x) on a production Kubernetes cluster using `kubeadm`.

> [!WARNING]
> **The Golden Rule of Upgrades:** ALWAYS upgrade the Control Plane node(s) first. Only after the Control Plane is fully upgraded should you begin upgrading the Worker Nodes one by one.

---

## 0. Prerequisites & Best Practices

1. **Use Deployments, Not Bare Pods:** Before upgrading, ensure your workloads are managed by `Deployments`, `StatefulSets`, or `DaemonSets`. Because upgrading requires "draining" (evicting) pods from a server, any bare `kind: Pod` workloads will be permanently deleted and not automatically recreated.
2. **Transient Errors are Normal:** When you apply the upgrade on the Control Plane, `kubeadm` will restart `etcd` and the API Server. During this 1-3 minute window, you will likely see `context deadline exceeded` or `Client.Timeout` errors on your screen. **Do not panic and do not cancel the command.** It is just noisy logging while the API server is temporarily offline.

---

## Phase 1: Upgrade the Control Plane Node
> 🖥️ **RUN ON:** Control Plane Node

### 1. Update the Repository
Point your package manager to the new Kubernetes version (e.g., from v1.35 to v1.36).
```bash
sudo sed -i 's/v1.35/v1.36/g' /etc/yum.repos.d/kubernetes.repo
```

### 2. Upgrade `kubeadm`
Install the new version of `kubeadm` first to orchestrate the upgrade.
```bash
# We use --disableexcludes to override the lock in the repo file
sudo yum install -y kubeadm-1.36.1 --disableexcludes=kubernetes
```

### 3. Apply the Cluster Upgrade
Tell `kubeadm` to fetch the new container images and seamlessly restart the core control plane components.
```bash
# Verify the cluster is healthy and see the upgrade plan
sudo kubeadm upgrade plan

# Apply the upgrade (Wait for it to finish, ignore transient timeout errors)
sudo kubeadm upgrade apply v1.36.1
```

### 4. Upgrade `kubelet` and `kubectl`
Now that the brain is upgraded, upgrade the node's local services.
```bash
# Safely evict all workloads off the Control Plane node
kubectl drain $(hostname) --ignore-daemonsets

# Install the new packages
sudo yum install -y kubelet-1.36.1 kubectl-1.36.1 --disableexcludes=kubernetes

# Restart the local kubelet service so it picks up the new version
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# Uncordon the node to allow workloads to be scheduled here again
kubectl uncordon $(hostname)
```

---

## Phase 2: Upgrade the Worker Node(s)
> Repeat these steps for every worker node in your cluster, one at a time.

### 1. Update Repo & Install `kubeadm`
> 🖥️ **RUN ON:** Worker Node
```bash
sudo sed -i 's/v1.35/v1.36/g' /etc/yum.repos.d/kubernetes.repo
sudo yum install -y kubeadm-1.36.1 --disableexcludes=kubernetes
```

### 2. Drain the Worker Node
> 🖥️ **RUN ON:** Control Plane Node
```bash
# Safely evict all running pods from this specific worker node
kubectl drain <worker-node-hostname> --ignore-daemonsets --force
```

### 3. Upgrade Node Configuration & Services
> 🖥️ **RUN ON:** Worker Node
```bash
# Upgrade the local node configuration
sudo kubeadm upgrade node

# Install the new packages
sudo yum install -y kubelet-1.36.1 kubectl-1.36.1 --disableexcludes=kubernetes

# Restart the local kubelet service
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

### 4. Finish Up
> 🖥️ **RUN ON:** Control Plane Node
```bash
# Allow pods to be scheduled on the worker node again
kubectl uncordon <worker-node-hostname>
```

---
## Phase 3: Verification
> 🖥️ **RUN ON:** Control Plane Node

Ensure all nodes report the new version and show a `Ready` status.
```bash
kubectl get nodes -o wide
```
