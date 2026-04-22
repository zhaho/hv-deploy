#!/bin/bash

set -e

VM_NAME=$1

if [ -z "$VM_NAME" ]; then
  echo "Usage: ./deploy-vm.sh <vm-name>"
  exit 1
fi

WORKDIR=~/hv-deploy/$VM_NAME
ISO_PATH="/mnt/c/HyperV/ISOs/${VM_NAME}.iso"
WINDOWS_ISO_PATH="C:\\HyperV\\ISOs\\${VM_NAME}.iso"

ANSIBLE_DIR=~/hv-deploy/ansible
INVENTORY="$ANSIBLE_DIR/inventory.ini"

SSH_KEY=$(cat ~/.ssh/id_ed25519.pub)

mkdir -p $WORKDIR
cd $WORKDIR

echo "Creating cloud-init config..."

cat > user-data <<EOF
#cloud-config
hostname: $VM_NAME

users:
  - name: ldxadm
    groups: sudo
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - $SSH_KEY

package_update: true

packages:
  - python3
  - qemu-guest-agent

runcmd:
  - systemctl enable qemu-guest-agent
EOF

cat > meta-data <<EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF

echo "Generating ISO..."

genisoimage -output seed.iso \
  -volid cidata -joliet -rock \
  user-data meta-data

mkdir -p /mnt/c/HyperV/ISOs
cp seed.iso $ISO_PATH

echo "Creating VM and waiting for IP..."

PS_OUTPUT=$(powershell.exe -ExecutionPolicy Bypass -File C:\\HyperV\\deploy-vm.ps1 -vmName "$VM_NAME" -isoPath "$WINDOWS_ISO_PATH")

# Clean CRLF
PS_OUTPUT=$(echo "$PS_OUTPUT" | tr -d '\r')

echo "$PS_OUTPUT"

# Extract IPv4
VM_IP=$(echo "$PS_OUTPUT" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1)

if [ -z "$VM_IP" ]; then
  echo "Failed to detect IP"
  echo "Full PowerShell output:"
  echo "$PS_OUTPUT"
  exit 1
fi

echo "Parsed IP: $VM_IP"

echo "Waiting for SSH..."

SSH_READY=false

for i in {1..30}; do
  if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 ldxadm@$VM_IP "echo ok" &>/dev/null; then
    echo "SSH is ready"
    SSH_READY=true
    break
  fi
  sleep 5
done

if [ "$SSH_READY" = false ]; then
  echo "SSH never became ready"
  exit 1
fi

echo "Updating Ansible inventory..."

mkdir -p $ANSIBLE_DIR

cat > $INVENTORY <<EOF
[linux]
$VM_NAME ansible_host=$VM_IP ansible_user=ldxadm ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF

echo "Running Ansible playbook..."

cd $ANSIBLE_DIR
ansible-playbook -i inventory.ini base.yml

echo "VM $VM_NAME deployed and configured successfully!"
