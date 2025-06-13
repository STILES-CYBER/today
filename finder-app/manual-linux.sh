#!/bin/bash
# Script to build kernel and rootfs for QEMU ARM64
# Author: Siddhant Jajoo. 

set -e
set -u

git config --global http.postBuffer 524288000
git config --global core.compression 0

OUTDIR=/tmp/aeld
KERNEL_REPO=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
KERNEL_VERSION=v5.15.163
BUSYBOX_VERSION=1_33_1
FINDER_APP_DIR=$(realpath $(dirname $0))
ARCH=arm64
CROSS_COMPILE=aarch64-none-linux-gnu-

if [ $# -lt 1 ]
then
    echo "Using default directory ${OUTDIR} for output"
else
    OUTDIR=$1
    echo "Using passed directory ${OUTDIR} for output"
fi

mkdir -p "${OUTDIR}" || { echo "Failed to create outdir ${OUTDIR}"; exit 1; }

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/linux-stable" ]; then
    echo "CLONING GIT LINUX STABLE VERSION ${KERNEL_VERSION} IN ${OUTDIR}"
    for i in {1..3}; do
        rm -rf linux-stable
        git clone ${KERNEL_REPO} --depth 1 --single-branch --branch ${KERNEL_VERSION} linux-stable && break
        echo "Clone failed, retrying in 10 seconds... ($i/3)"
        sleep 10
    done
    if [ ! -d "${OUTDIR}/linux-stable" ]; then
        echo "Failed to clone linux-stable after 3 attempts."
        exit 1
    fi
fi

if [ ! -e "${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image" ]; then
    cd linux-stable
    echo "Checking out version ${KERNEL_VERSION}"
    git checkout ${KERNEL_VERSION}

    # Kernel build steps
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} mrproper
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig
    make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} all
    cd "$OUTDIR"
fi

# Fail fast if image is missing
if [ ! -e "${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image" ]; then
    echo "Kernel build failed: Image not found at ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image"
    exit 1
fi

# Copy kernel image to outdir
cp "${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image" "${OUTDIR}/"

echo "Adding the Image in outdir"

echo "Creating the staging directory for the root filesystem"
if [ -d "${OUTDIR}/rootfs" ]
then
    echo "Deleting rootfs directory at ${OUTDIR}/rootfs and starting over"
    sudo rm -rf "${OUTDIR}/rootfs"
fi

# Create necessary base directories
mkdir -p "${OUTDIR}/rootfs"/{bin,dev,etc,home,lib,proc,sbin,sys,tmp,usr/bin,usr/sbin,var}
cd "${OUTDIR}"

# Clone and build busybox
if [ ! -d "${OUTDIR}/busybox" ]
then
    git clone git://busybox.net/busybox.git
fi
cd busybox
git checkout ${BUSYBOX_VERSION}
make distclean
make defconfig

# AUTOMATICALLY DISABLE 'tc' utility in BusyBox to avoid tc build errors
sed -i '/CONFIG_TC/d' .config
echo "# CONFIG_TC is not set" >> .config

make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE}
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} CONFIG_PREFIX="${OUTDIR}/rootfs" install

echo "Library dependencies"
cd "${OUTDIR}/rootfs"
${CROSS_COMPILE}readelf -a bin/busybox | grep "program interpreter" || true
${CROSS_COMPILE}readelf -a bin/busybox | grep "Shared library" || true

# Add library dependencies to rootfs
SYSROOT=$(${CROSS_COMPILE}gcc -print-sysroot)
NEEDED_LIBS=$(${CROSS_COMPILE}readelf -a bin/busybox | grep "Shared library" | awk '{print $NF}' | tr -d '[]')
for LIB in $NEEDED_LIBS; do
    # Only copy if not already present (avoid "are the same file" error)
    if [ ! -e "lib/$LIB" ]; then
        LIBPATH=$(find $SYSROOT -name "$LIB" 2>/dev/null | head -n 1)
        if [ -n "$LIBPATH" ]; then
            cp -a "$LIBPATH" lib/
        fi
    fi
done
INTERP=$(${CROSS_COMPILE}readelf -a bin/busybox | grep "program interpreter" | awk -F ':' '{print $2}' | tr -d '[] ')
if [ -n "$INTERP" ] && [ ! -e "lib/$(basename $INTERP)" ]; then
    INTERP_PATH=$(find $SYSROOT -name "$(basename $INTERP)" 2>/dev/null | head -n 1)
    if [ -n "$INTERP_PATH" ]; then
        cp -a "$INTERP_PATH" lib/
    fi
fi

# Make device nodes
sudo mknod -m 666 dev/null c 1 3 || true
sudo mknod -m 600 dev/console c 5 1 || true

# Clean and build the writer utility
cd "${FINDER_APP_DIR}"
make clean
make CROSS_COMPILE=${CROSS_COMPILE}

# Copy the finder related scripts and executables to the /home directory on the target rootfs
cp writer "${OUTDIR}/rootfs/home/"
cp finder.sh "${OUTDIR}/rootfs/home/"
cp writer.sh "${OUTDIR}/rootfs/home/"
cp finder-test.sh "${OUTDIR}/rootfs/home/"
cp autorun-qemu.sh "${OUTDIR}/rootfs/home/"
mkdir -p "${OUTDIR}/rootfs/home/conf"
cp conf/username.txt "${OUTDIR}/rootfs/home/conf/"
cp conf/assignment.txt "${OUTDIR}/rootfs/home/conf/"
# Fix path in finder-test.sh
sed -i 's|\.\./conf/assignment.txt|conf/assignment.txt|' "${OUTDIR}/rootfs/home/finder-test.sh"

chmod +x "${OUTDIR}/rootfs/home/writer"
chmod +x "${OUTDIR}/rootfs/home/"*.sh

# Chown the root directory
cd "${OUTDIR}/rootfs"
sudo chown -R root:root . || true

# Create initramfs.cpio.gz, suppress find permission denied errors
find . 2>/dev/null | cpio -H newc -ov --owner root:root | gzip > "${OUTDIR}/initramfs.cpio.gz"

echo "Kernel and rootfs images are ready:"
echo "  Kernel: ${OUTDIR}/Image"
echo "  Initramfs: ${OUTDIR}/initramfs.cpio.gz"

mkdir -p /tmp/aesd-autograder

# Only copy if source and destination are not the same file
if [ "${OUTDIR}/Image" != "/tmp/aesd-autograder/Image" ]; then
    cp "${OUTDIR}/Image" /tmp/aesd-autograder/Image
fi
if [ "${OUTDIR}/initramfs.cpio.gz" != "/tmp/aesd-autograder/initramfs.cpio.gz" ]; then
    cp "${OUTDIR}/initramfs.cpio.gz" /tmp/aesd-autograder/initramfs.cpio.gz
fi

exit 0
