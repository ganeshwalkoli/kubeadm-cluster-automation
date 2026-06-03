# Kubernetes Administration Scripts & SOPs

This repository contains a collection of battle-tested bash scripts and Standard Operating Procedures (SOPs) for installing, upgrading, and managing production-grade Kubernetes clusters on RHEL 9 using `kubeadm`, `containerd`, and Calico CNI.

## Contents

### Automation Scripts
* `k8s_01_install_packages.sh`: Automates OS-level preparation (swap, kernel modules, sysctl, containerd) and installs `kubeadm`, `kubelet`, and `kubectl` for a specified minor/patch version.
* `k8s_02_init_cluster.sh`: Automates `kubeadm init`, configures the `kubeconfig`, and deploys the Calico network mesh on the Control Plane.
* `k8s_node_upgrade.sh`: Automates the OS-level upgrade process for both Control Plane and Worker nodes, handling YUM repository branch changes and safely executing the correct `kubeadm upgrade` commands.

### Standard Operating Procedures (SOPs)
* `K8S_1.35_RHEL9_Installation_SOP.md`: Detailed step-by-step guide for fresh cluster installation, including network port requirements and AWS Security Group configurations.
* `K8S_Upgrade_SOP.md`: Step-by-step guide for safely performing minor version upgrades across the cluster, including critical node draining procedures.
* `K8S_Network_Whitelist.md`: A comprehensive, version-agnostic list of required URLs and CDNs for air-gapped or proxy-restricted enterprise environments.

### Testing
* `nginx-test.yaml`: Deployment manifest to verify cross-node workload scheduling.
* `nginx-test-2.yaml`: Standalone pod manifest for testing cross-node Calico VXLAN/BGP routing.

## Usage
These scripts are designed to accept specific Kubernetes versions to allow precise control over the cluster lifecycle.

Example Installation:
```bash
chmod +x k8s_01_install_packages.sh
./k8s_01_install_packages.sh 1.35 1.35.5
```

Example Upgrade:
```bash
chmod +x k8s_node_upgrade.sh
./k8s_node_upgrade.sh 1.36 1.36.1
```
