#!/bin/bash

set -e

VM_NAME=$1
STATIC_IP=$2   # e.g. 192.168.1.100/24 (optional, uses DHCP if omitted)
GATEWAY=$3    # e.g. 192.168.1.1 (required if static IP is set)

if [ -z "$VM_NAME" ]; then
  echo "Usage: ./deploy-vm.sh <vm-name> [static-ip/prefix] [gateway]"
  echo "  Example (DHCP):   ./deploy-vm.sh myvm"
  echo "  Example (static): ./deploy-vm.sh myvm 192.168.1.100/24 192.168.1.1"
  exit 1
fi

if [ -n "$STATIC_IP" ] && [ -z "$GATEWAY" ]; then
  echo "Error: gateway is required when specifying a static IP"
  exit 1
fi

if [ -n "$STATIC_IP" ] && [[ "$STATIC_IP" != */* ]]; then
  echo "Error: static IP must include a prefix length, e.g. 10.4.1.25/24"
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

if [ -n "$STATIC_IP" ]; then
  cat > network-config <<EOF
version: 2
ethernets:
  eth0:
    dhcp4: false
    addresses:
      - $STATIC_IP
    gateway4: $GATEWAY
    nameservers:
      addresses: [8.8.8.8, 1.1.1.1]
EOF
fi

echo "Generating ISO..."

if [ -n "$STATIC_IP" ]; then
  genisoimage -output seed.iso \
    -volid cidata -joliet -rock \
    user-data meta-data network-config
else
  genisoimage -output seed.iso \
    -volid cidata -joliet -rock \
    user-data meta-data
fi

mkdir -p /mnt/c/HyperV/ISOs
cp seed.iso $ISO_PATH

echo "Creating VM and waiting for IP..."

if [ -n "$STATIC_IP" ]; then
  BARE_IP=$(echo "$STATIC_IP" | cut -d'/' -f1)
  PS_OUTPUT=$(powershell.exe -ExecutionPolicy Bypass -File C:\\HyperV\\deploy-vm.ps1 -vmName "$VM_NAME" -isoPath "$WINDOWS_ISO_PATH" -staticIp "$BARE_IP")
else
  PS_OUTPUT=$(powershell.exe -ExecutionPolicy Bypass -File C:\\HyperV\\deploy-vm.ps1 -vmName "$VM_NAME" -isoPath "$WINDOWS_ISO_PATH")
fi

# Clean CRLF
PS_OUTPUT=$(echo "$PS_OUTPUT" | tr -d '\r')

echo "$PS_OUTPUT"

if [ -n "$STATIC_IP" ]; then
  # Use the static IP directly (strip prefix length)
  VM_IP=$(echo "$STATIC_IP" | cut -d'/' -f1)
  echo "Using static IP: $VM_IP"
else
  # Extract IPv4 from PowerShell output
  VM_IP=$(echo "$PS_OUTPUT" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1)

  if [ -z "$VM_IP" ]; then
    echo "Failed to detect IP"
    echo "Full PowerShell output:"
    echo "$PS_OUTPUT"
    exit 1
  fi

  echo "Parsed IP: $VM_IP"
fi

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
