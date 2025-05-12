#!/bin/bash
# Script to build and install a minimal Linux system for ARM64 using QEMU
# Author: Siddhant Jajoo (modified)

set -e  # Exit on any error
set -u  # Treat unset variables as errors

# Defaults
OUTDIR=/tmp/aeld
KERNEL_REPO=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
KERNEL_VERSION=v5.15.163
BUSYBOX_VERSION=1_33_1
FINDER_APP_DIR=$(realpath $(dirname "$0"))
ARCH=arm64
CROSS_COMPILE=aarch64-linux-gnu-

# Parse command line arguments
if [ $# -ge 1 ]; then
    OUTDIR=$1
    echo "Using passed directory ${OUTDIR} for output"
else
    echo "Using default directory ${OUTDIR} for output"
fi

# Ensure OUTDIR exists
mkdir -p "${OUTDIR}" || { echo "Failed to create ${OUTDIR}"; exit 1; }

cd "$OUTDIR"

# Clone and build the kernel
if [ ! -d "${OUTDIR}/linux-stable" ]; then
    echo "Cloning Linux kernel ${KERNEL_VERSION}"
    git clone --depth 1 --branch ${KERNEL_VERSION} ${KERNEL_REPO} linux-stable || { echo "Kernel clone failed"; exit 1; }
fi

if [ ! -e "${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image" ]; then
    echo "Building the Linux kernel"
    cd linux-stable
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} mrproper
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig
    make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} all || { echo "Kernel build failed"; exit 1; }
    cd ..
fi

echo "Copying kernel image to ${OUTDIR}"
cp "${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image" "${OUTDIR}/Image" || { echo "Failed to copy kernel image"; exit 1; }

# Rootfs setup
echo "Creating root filesystem"
cd "$OUTDIR"
sudo rm -rf rootfs
mkdir -p rootfs/{bin,sbin,etc,proc,sys,usr/{bin,sbin},lib,lib64,dev,home,tmp}

# Build and install BusyBox
if [ ! -d "${OUTDIR}/busybox" ]; then
    echo "Cloning BusyBox repository"
    git clone git://busybox.net/busybox.git || { echo "BusyBox clone failed"; exit 1; }
fi
cd busybox
git checkout ${BUSYBOX_VERSION}
make distclean
make defconfig
make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} || { echo "BusyBox build failed"; exit 1; }
make CONFIG_PREFIX="${OUTDIR}/rootfs" ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} install || { echo "BusyBox install failed"; exit 1; }

# Library dependencies
cd "${OUTDIR}/rootfs"
SYSROOT=$(${CROSS_COMPILE}gcc -print-sysroot)
cp -a ${SYSROOT}/lib/* ./lib/ || echo "No libraries found in lib"
cp -a ${SYSROOT}/lib64/* ./lib64/ || echo "No libraries found in lib64"

# Create device nodes
echo "Creating device nodes"
sudo mknod -m 666 dev/null c 1 3 || { echo "Failed to create /dev/null"; exit 1; }
sudo mknod -m 600 dev/console c 5 1 || { echo "Failed to create /dev/console"; exit 1; }

# Build writer app
echo "Building writer application"
cd "${FINDER_APP_DIR}"
make clean
make CROSS_COMPILE=${CROSS_COMPILE} || { echo "Writer app build failed"; exit 1; }

# Copy apps and scripts to rootfs
echo "Copying applications and scripts to root filesystem"
mkdir -p "${OUTDIR}/rootfs/home"
cp writer finder.sh finder-test.sh conf/username.txt conf/assignment.txt autorun-qemu.sh "${OUTDIR}/rootfs/home/" || { echo "Failed to copy files to rootfs"; exit 1; }

# Fix finder-test.sh relative path
sed -i 's|\.\./conf/|conf/|g' "${OUTDIR}/rootfs/home/finder-test.sh"

# Set permissions
echo "Setting permissions for root filesystem"
cd "${OUTDIR}/rootfs"
sudo chown -R root:root . || { echo "Failed to set permissions"; exit 1; }

# Create initramfs
echo "Creating initramfs"
find . | cpio -H newc -ov --owner root:root | gzip > "${OUTDIR}/initramfs.cpio.gz" || { echo "Failed to create initramfs"; exit 1; }

echo "Build completed: ${OUTDIR}/Image and ${OUTDIR}/initramfs.cpio.gz are ready."

