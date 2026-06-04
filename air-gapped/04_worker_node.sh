#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

echo "================================================================="
echo "Worker Node Setup"
echo "================================================================="
echo "Before running this script, you must have run 02_offline_setup.sh"
echo "on this node to configure containerd and install kubelet."
echo "================================================================="
echo ""
echo "Please paste your full 'kubeadm join' command below (including tokens/hashes)."
echo "Example: kubeadm join 10.0.0.5:6443 --token xyz... --discovery-token-ca-cert-hash sha256:abc..."
echo ""
read -p "Join Command: " JOIN_COMMAND

if [[ -z "$JOIN_COMMAND" ]]; then
  echo "Error: No command provided."
  exit 1
fi

if [[ ! "$JOIN_COMMAND" == *"kubeadm join"* ]]; then
  echo "Error: Command does not look like a valid kubeadm join command."
  exit 1
fi

echo "Executing join command..."
$JOIN_COMMAND --ignore-preflight-errors=FileContent--proc-sys-net-bridge-bridge-nf-call-iptables,FileContent--proc-sys-net-bridge-bridge-nf-call-ip6tables

echo "Worker node successfully joined the cluster!"
