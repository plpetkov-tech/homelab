#!/bin/bash

set -a # automatically export all variables
source /etc/k8s.env
source /etc/.env
set +a # stop automatically exporting

# Set non-interactive mode for apt commands
export DEBIAN_FRONTEND=noninteractive

# install all locales, gpg, bc (essentials for scripts to work)
apt install -y \
  locales-all \
  gpg \
  bc

# generate locales
echo -e "export LANGUAGE=en_US\nexport LANG=en_US.UTF-8\nexport LC_ALL=en_US.UTF-8\nexport LC_CTYPE=en_US.UTF-8" >> /etc/environment
source /etc/environment
locale-gen en_US.UTF-8
dpkg-reconfigure --frontend=noninteractive locales
touch /var/lib/cloud/instance/locale-check.skip

# Preconfigure keyboard settings for both Ubuntu and Debian
echo "keyboard-configuration keyboard-configuration/layout select 'English (US)'" | debconf-set-selections
echo "keyboard-configuration keyboard-configuration/layoutcode string 'us'" | debconf-set-selections
echo "keyboard-configuration keyboard-configuration/model select 'Generic 105-key PC (intl.)'" | debconf-set-selections
echo "keyboard-configuration keyboard-configuration/variant select 'English (US)'" | debconf-set-selections

mkdir -m 755 /etc/apt/keyrings

# add kubernetes apt repository
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_SHORT_VERSION}/deb/Release.key" | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_SHORT_VERSION}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list

# Note: Helm will be installed via script instead of apt repository
# to avoid DNS/repo issues with baltocdn.com

# update apt cache
apt-get update
apt upgrade -y

# Install packages from apt (without kubernetes packages first)
apt install -y \
bash \
curl \
grep \
git \
open-iscsi \
lsscsi \
multipath-tools \
scsitools \
nfs-common \
sg3-utils jq \
apparmor \
apparmor-utils \
iperf \
apt-transport-https \
ca-certificates \
gnupg-agent \
software-properties-common \
ipvsadm \
apache2-utils \
python3-kubernetes \
python3-pip \
conntrack \
unzip \
ceph \
cron \
iproute2 \
intel-gpu-tools \
intel-opencl-icd \
etcd-client

# Install Helm using the official script (more reliable than apt repo)
echo "Installing Helm via official script..."
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# =============================================================================
# IMPROVED KUBERNETES PACKAGE INSTALLATION WITH DEBUGGING
# =============================================================================

echo "=== Kubernetes Package Installation Debug ==="
echo "KUBERNETES_SHORT_VERSION: $KUBERNETES_SHORT_VERSION"
echo "KUBERNETES_MEDIUM_VERSION: $KUBERNETES_MEDIUM_VERSION"
echo "KUBERNETES_LONG_VERSION: $KUBERNETES_LONG_VERSION"

# Clear any potential apt cache issues
echo "Cleaning apt cache..."
apt-get clean
rm -rf /var/lib/apt/lists/*
apt-get update

# Verify the exact versions available
echo "=== Checking available Kubernetes package versions ==="
echo "Available kubelet versions matching $KUBERNETES_MEDIUM_VERSION:"
apt-cache madison kubelet | grep "$KUBERNETES_MEDIUM_VERSION" | head -3

echo "Available kubeadm versions matching $KUBERNETES_MEDIUM_VERSION:"
apt-cache madison kubeadm | grep "$KUBERNETES_MEDIUM_VERSION" | head -3

echo "Available kubectl versions matching $KUBERNETES_MEDIUM_VERSION:"
apt-cache madison kubectl | grep "$KUBERNETES_MEDIUM_VERSION" | head -3

# Test if the exact version exists before installing
if apt-cache madison kubelet | grep -q "$KUBERNETES_LONG_VERSION"; then
    echo "✓ kubelet version $KUBERNETES_LONG_VERSION found"
else
    echo "✗ kubelet version $KUBERNETES_LONG_VERSION NOT found"
    echo "Available $KUBERNETES_MEDIUM_VERSION versions for kubelet:"
    apt-cache madison kubelet | grep "$KUBERNETES_MEDIUM_VERSION"

    # Try to auto-detect the correct version
    DETECTED_VERSION=$(apt-cache madison kubelet | grep "$KUBERNETES_MEDIUM_VERSION" | head -1 | awk '{print $3}')
    if [ -n "$DETECTED_VERSION" ]; then
        echo "Auto-detected available version: $DETECTED_VERSION"
        echo "Updating KUBERNETES_LONG_VERSION to: $DETECTED_VERSION"
        KUBERNETES_LONG_VERSION="$DETECTED_VERSION"
    else
        echo "ERROR: No $KUBERNETES_MEDIUM_VERSION versions found for kubelet"
        exit 1
    fi
fi

# Install with explicit error handling
echo "=== Installing Kubernetes packages ==="
echo "Installing with version: $KUBERNETES_LONG_VERSION"

if apt install -y \
    kubelet="$KUBERNETES_LONG_VERSION" \
    kubeadm="$KUBERNETES_LONG_VERSION" \
    kubectl="$KUBERNETES_LONG_VERSION"; then
    
    echo "✓ Successfully installed Kubernetes packages"
else
    echo "✗ Failed to install Kubernetes packages with version $KUBERNETES_LONG_VERSION"
    echo "Attempting fallback installation..."

    # Fallback: get the actual available version
    ACTUAL_VERSION=$(apt-cache madison kubelet | grep "$KUBERNETES_MEDIUM_VERSION" | head -1 | awk '{print $3}')
    if [ -n "$ACTUAL_VERSION" ]; then
        echo "Trying fallback version: $ACTUAL_VERSION"
        
        if apt install -y \
            kubelet="$ACTUAL_VERSION" \
            kubeadm="$ACTUAL_VERSION" \
            kubectl="$ACTUAL_VERSION"; then
            echo "✓ Fallback installation successful"
        else
            echo "✗ Fallback installation also failed"
            exit 1
        fi
    else
        echo "✗ No fallback version available"
        exit 1
    fi
fi

# Verify installation
echo "=== Verifying Kubernetes installation ==="
if which kubelet && which kubeadm && which kubectl; then
    echo "✓ All Kubernetes binaries found in PATH"
    kubelet --version
    kubeadm version --output=short
    kubectl version --client --output=yaml
else
    echo "✗ Some Kubernetes binaries not found in PATH"
    echo "kubelet: $(which kubelet || echo 'NOT FOUND')"
    echo "kubeadm: $(which kubeadm || echo 'NOT FOUND')"  
    echo "kubectl: $(which kubectl || echo 'NOT FOUND')"
    exit 1
fi

# hold back kubernetes packages
echo "=== Holding Kubernetes packages ==="
apt-mark hold kubelet kubeadm kubectl
echo "Held packages:"
apt-mark showhold | grep -E "(kubelet|kubeadm|kubectl)"

# =============================================================================
# END OF IMPROVED KUBERNETES INSTALLATION
# =============================================================================

# install containerd, which have different package names on Debian and Ubuntu
distro=$(lsb_release -is)
if [[ "$distro" = *"Debian"* ]]; then

    echo "Installing containerd on Debian..."
    # add docker apt repository
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    sudo apt install -y containerd.io

    # remove the extra kernel modules script, it's not needed on Debian
    rm -f /root/extra-kernel-modules.sh

elif [[ "$distro" = *"Ubuntu"* ]]; then

    echo "Installing containerd on Ubuntu..."
    sudo apt install -y containerd

    # ----------------- Disable Runc AppArmor Profile -----------------

    # Define paths for the AppArmor runc profile and the disable directory
    RUNC_PROFILE="/etc/apparmor.d/runc"
    DISABLE_DIR="/etc/apparmor.d/disable"
    DISABLED_PROFILE="$DISABLE_DIR/runc"

    # Check if AppArmor runc profile exists
    if [[ -f "$RUNC_PROFILE" ]]; then
        echo "AppArmor runc profile found at $RUNC_PROFILE"

        # Ensure the disable directory exists
        if [[ ! -d "$DISABLE_DIR" ]]; then
            echo "Creating disable directory at $DISABLE_DIR"
            mkdir -p "$DISABLE_DIR"
        fi

        # Check if runc profile is already disabled
        if [[ ! -L "$DISABLED_PROFILE" ]]; then
            # Create symbolic link to disable the profile
            echo "Disabling AppArmor profile for runc"
            ln -s "$RUNC_PROFILE" "$DISABLED_PROFILE"

            # Reload AppArmor to apply the changes
            echo "Reloading AppArmor profile for runc"
            apparmor_parser -R "$RUNC_PROFILE" || echo "Warning: Failed to reload AppArmor profile"
        else
            echo "AppArmor runc profile is already disabled."
        fi
    else
        echo "AppArmor runc profile does not exist, no action required."
    fi

    # ----------------- Extra kernel modules package -----------------

    echo "Installing extra linux kernel modules to help with recognizing passed through devices..."
    GRUB_DEFAULT_FILE="/etc/default/grub"
    GRUB_CFG_FILE="/boot/grub/grub.cfg"

    # Extract the GRUB_DEFAULT value
    grub_default=$(grep "^GRUB_DEFAULT=" "$GRUB_DEFAULT_FILE" | cut -d'=' -f2 | tr -d '"')

    # Determine which kernel will be booted based on GRUB_DEFAULT setting
    if [[ "$grub_default" == "saved" ]]; then
        # Check the saved entry in grubenv if GRUB_DEFAULT is 'saved'
        saved_entry=$(grep "saved_entry" /boot/grub/grubenv | cut -d'=' -f2)
        if [[ -z "$saved_entry" ]]; then
            echo "No saved entry found. Defaulting to the first menu entry."
            grub_default=0
        else
            grub_default=$saved_entry
        fi
    fi

    # Check if GRUB_DEFAULT is a number or points to the generic "Ubuntu" entry
    if [[ "$grub_default" =~ ^[0-9]+$ || "$grub_default" == "0" || "$grub_default" == "Ubuntu" ]]; then
        # Search for the latest kernel in the submenu entries if the generic "Ubuntu" is selected
        kernel_entry=$(awk -F\' '/menuentry / {menu++} /menuentry .*Linux/ && menu==2 {print $2; exit}' "$GRUB_CFG_FILE")
    else
        # If GRUB_DEFAULT points to a specific menu entry string
        kernel_entry=$(awk -F\' -v title="$grub_default" '$0 ~ title {print $2; exit}' "$GRUB_CFG_FILE")
    fi

    # Extract the kernel version from the menu entry (e.g., "Linux 6.8.0-48-generic")
    kernel_version=$(echo "$kernel_entry" | grep -oP '\b[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-generic\b')

    echo "Kernel version set for the next reboot: $kernel_version"
    package="linux-modules-extra-$kernel_version"
    apt install -y "$package"

    # Add a cron job to keep extra kernel modules up-to-date after every reboot.
    #   This is necessary because apt doesn't keep this package up to date with the kernel
    #   version unless you install linux-generic or some other large meta package.
    (crontab -l 2>/dev/null; echo "@reboot /root/extra-kernel-modules.sh") | crontab -

else
    echo "Unsupported distribution: $distro"
    exit 1
fi

# Create default containerd config
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml

# Setup cgroup drivers (will use systemd, not cgroupfs, because its native to Debian/Ubuntu)
sed -i '/SystemdCgroup = false/s/false/true/' /etc/containerd/config.toml

systemctl daemon-reload
systemctl enable containerd
systemctl enable open-iscsi
systemctl enable iscsid
# systemctl enable multipathd  # Disabled - conflicts with Longhorn storage
systemctl enable qemu-guest-agent

if [[ -n "$NVIDIA_DRIVER_VERSION" && "$NVIDIA_DRIVER_VERSION" != "none" ]]; then
  if [[ "$distro" = *"Debian"* ]]; then

    # add contrib, non-free, and non-free-firmware components to sources.list
    sed -i '/^Components:/ s/main/main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources

    apt-get update

    # install nvidia kernel modules
    apt install -y \
      "linux-headers-$(uname -r)"

    # install nvidia driver
    apt install -y \
      nvidia-driver \
      firmware-misc-nonfree

  elif [[ "$distro" = *"Ubuntu"* ]]; then

    # install nvidia kernel modules
    apt install -y \
      "linux-modules-nvidia-${NVIDIA_DRIVER_VERSION}-server-generic" \
      "linux-headers-generic" \
      "nvidia-dkms-${NVIDIA_DRIVER_VERSION}-server"

    # install nvidia driver
    apt install -y \
      "nvidia-driver-${NVIDIA_DRIVER_VERSION}-server"

  else
    echo "Unsupported distribution: $distro"
    exit 1
  fi

  # add nvidia-container-toolkit apt repository
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
    && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
      sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
      sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

  apt-get update

  # install nvidia toolkit/runtime
  apt install -y \
    nvidia-container-toolkit \
    nvidia-container-runtime
fi

# Start containerd service immediately (not just enable for boot)
systemctl start containerd

# Wait for containerd to be fully ready
echo "Waiting for containerd to be ready..."
max_attempts=30
attempt=0
while ! systemctl is-active --quiet containerd || ! ctr version &>/dev/null; do
    if [ $attempt -ge $max_attempts ]; then
        echo "ERROR: containerd failed to start within $max_attempts seconds"
        exit 1
    fi
    echo "Attempt $((attempt + 1))/$max_attempts: containerd not ready, waiting..."
    sleep 2
    attempt=$((attempt + 1))
done

echo "containerd is ready!"

# Additional wait to ensure the CRI socket is fully functional
sleep 5

# Pre-pull kubeadm images to speed up cluster bootstrap
echo "=== Pre-pulling Kubernetes images ==="
echo "Pre-pulling Kubernetes images for faster cluster initialization..."
echo "Using Kubernetes version: $KUBERNETES_MEDIUM_VERSION"

if kubeadm config images pull --kubernetes-version="$KUBERNETES_MEDIUM_VERSION" --v=2; then
    echo "✓ Successfully pre-pulled Kubernetes images"
else
    echo "⚠ WARNING: Failed to pre-pull images, but continuing. Images will be pulled during cluster init."
    echo "This might happen if kubeadm isn't working correctly. Let's verify:"
    kubeadm version || echo "kubeadm version command failed"
    # Don't exit on failure here since the cluster can still work, images will just be pulled later
fi

# Final verification
echo "=== Final Installation Verification ==="
echo "Installed Kubernetes packages:"
dpkg -l | grep -E "(kubelet|kubeadm|kubectl)" | awk '{print $2, $3}'

echo ""
echo "Kubernetes binary versions:"
kubelet --version 2>/dev/null || echo "kubelet version check failed"
kubeadm version --output=short 2>/dev/null || echo "kubeadm version check failed"
kubectl version --client --output=yaml 2>/dev/null || echo "kubectl version check failed"

# extraneous package cleanup
echo "=== Cleaning up ==="
apt autoremove -y

echo "=== Script completed successfully ==="