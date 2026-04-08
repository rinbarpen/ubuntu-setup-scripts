#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

VM_CHOICES=$(whiptail --title "Virtualization" --checklist \
  "Select VM software to install:" 12 55 2 \
  "virtualbox"  "VirtualBox"              OFF \
  "kvm"         "QEMU/KVM + virt-manager" OFF \
  3>&1 1>&2 2>&3) || { log_warn "Skipped VM selection"; exit 0; }

SELECTED=$(echo "$VM_CHOICES" | tr -d '"')

if echo "$SELECTED" | grep -Fqw "virtualbox"; then
  if command -v virtualbox &>/dev/null; then
    log_info "VirtualBox already installed, skipping"
  else
    log_info "Installing VirtualBox..."
    sudo install -m 0755 -d /etc/apt/keyrings
    wget -qO- https://www.virtualbox.org/download/oracle_vbox_2016.asc \
      | sudo gpg --dearmor -o /etc/apt/keyrings/oracle-vbox.gpg
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/oracle-vbox.gpg] https://download.virtualbox.org/virtualbox/debian $(lsb_release -cs) contrib" \
      | sudo tee /etc/apt/sources.list.d/virtualbox.list
    sudo apt-get update -qq
    sudo apt-get install -y virtualbox-7.0
    sudo usermod -aG vboxusers "$USER"
    log_info "VirtualBox installed. Re-login required."
  fi
fi

if echo "$SELECTED" | grep -Fqw "kvm"; then
  if command -v virsh &>/dev/null; then
    log_info "QEMU/KVM already installed, skipping"
  else
  log_info "Installing QEMU/KVM..."
  sudo apt-get install -y \
    qemu-kvm libvirt-daemon-system virt-manager bridge-utils
  sudo usermod -aG libvirt "$USER"
  sudo usermod -aG kvm "$USER"
  sudo systemctl enable --now libvirtd
  log_info "QEMU/KVM installed. Re-login required."
  fi
fi

log_info "vms: done"
