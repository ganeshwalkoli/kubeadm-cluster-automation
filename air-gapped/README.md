# Air-Gapped Kubernetes Automation Scripts

This directory contains a suite of automation scripts designed to drastically simplify the process of installing Kubernetes (v1.35) and Calico on RHEL 9 servers that have **zero internet access**.

## 🏗️ Architecture Overview

The installation is broken into two distinct phases:
1. **The Online Phase:** A script runs on an internet-connected RHEL 9 machine to download all required RPMs, generate a YUM repository, pull container images, and compress everything into a single transportable tarball.
2. **The Offline Phase:** Scripts run on the air-gapped nodes to extract the tarball, install the local RPMs, inject the container images directly into `containerd`, and initialize the cluster.

---

## 🚀 Step-by-Step Execution Guide

### Phase 1: On the Internet-Connected Machine

**1. Run the Bundler Script**
```bash
sudo ./01_online_bundle.sh
```
* **What it does:** Downloads all RPMs, dependencies, K8s images, Calico images, and the containerd pause image. It then uses `createrepo` to build a local repo and bundles everything into `~/k8s-airgap-bundle.tar.gz`.

**2. Transfer the Bundle**
Move the resulting `k8s-airgap-bundle.tar.gz` across your air-gap (via USB, secure SCP, etc.) to **every** offline node you intend to use (both your Master and Worker nodes).
* **CRITICAL:** Place the bundle exactly at `/tmp/k8s-airgap-bundle.tar.gz` on the offline nodes.

---

### Phase 2: On the Air-Gapped Nodes

#### Step A: Prepare All Nodes (Master & Workers)
On **every single node** in your cluster, run the setup script:
```bash
sudo ./02_offline_setup.sh
```
* **What it does:** Extracts the bundle, configures local YUM, installs `containerd`/`kubelet`/`kubeadm`, imports all container images directly into `ctr`, and applies pre-flight system configs (swap, sysctl, SELinux).

#### Step B: Initialize the Control Plane (Master Node ONLY)
On your designated **Master Node**, run:
```bash
sudo ./03_control_plane.sh
```
* **What it does:** Uses `kubeadm init` (pointing to the local images), sets up your `kubectl` config, and applies the Calico CNI.
* **Important:** At the end of this script, it will print a `kubeadm join` command. **Copy this command.**

#### Step C: Join the Workers (Worker Nodes ONLY)
On each of your **Worker Nodes**, run:
```bash
sudo ./04_worker_node.sh
```
* **What it does:** It will prompt you to paste the `kubeadm join` command you copied from the Master node. It then executes the join, attaching the worker to your air-gapped cluster.
