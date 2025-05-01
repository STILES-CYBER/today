#!/bin/bash
# Script outline to install and build kernel.
# Author: Siddhant Jajoo. Updated by OpenAI.

set -e
set -u

OUTDIR=/tmp/aeld
KERNEL_REPO=git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
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

mkdir -p ${OUTDIR}

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/linux-stable" ]; then
	echo "CLONING GIT LINUX STABLE VERSION ${KERNEL_VERSION} IN ${OUTDIR}"
	git clone ${KERNEL_REPO} --depth 1 --single-branch --branch ${KERNEL_VERSION}
fi

if [ ! -e ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ]; then
    cd linux-stable
    echo "Checking out version ${KERNEL_VERSION}"
    git checkout ${KERNEL_VERSION}

    echo "Building kernel..."
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} mrproper
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig
    make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} all
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} modules
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} dtbs
fi

echo "Adding the Image in outdir"
cp ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ${OUTDIR}/

echo "Creating the staging directory for the root filesystem"
cd "$OUTDIR"
if [ -d "${OUTDIR}/rootfs" ]; then
	echo "Deleting rootfs directory at ${OUTDIR}/rootfs and starting over"
    sudo rm -rf ${OUTDIR}/rootfs
fi

mkdir -p rootfs/{bin,dev,etc,home,lib,lib64,proc,sbin,sys,tmp,usr,var}
mkdir -p rootfs/usr/{bin,sbin}
mkdir -p rootfs/var/log

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/busybox" ]; then
	git clone git://busybox.net/busybox.git
	cd busybox
	git checkout ${BUSYBOX_VERSION}
else
	cd busybox
fi

echo "Configuring and installing busybox..."
make distclean
make defconfig
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE}
make CONFIG_PREFIX=${OUTDIR}/rootfs ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} install

echo "Library dependencies"
cd ${OUTDIR}/rootfs
SYSROOT=$(${CROSS_COMPILE}gcc -print-sysroot)

cp -a ${SYSROOT}/lib/ld-linux-aarch64.so.1 lib/
cp -a ${SYSROOT}/lib64/libc.so.6 lib64/
cp -a ${SYSROOT}/lib64/libm.so.6 lib64/
cp -a ${SYSROOT}/lib64/libresolv.so.2 lib64/
cp -a ${SYSROOT}/lib64/ld-linux-aarch64.so.1 lib64/

echo "Creating device nodes"
sudo mknod -m 666 dev/null c 1 3
sudo mknod -m 600 dev/console c 5 1

echo "Building writer utility"
cd ${FINDER_APP_DIR}
make clean
make CROSS_COMPILE=${CROSS_COMPILE}

echo "Copying finder scripts and executables to rootfs"
cp writer ${OUTDIR}/rootfs/home/
cp finder.sh finder-test.sh conf/username.txt conf/assignment.txt ${OUTDIR}/rootfs/home/
sed -i 's|\.\./conf/assignment.txt|conf/assignment.txt|' ${OUTDIR}/rootfs/home/finder-test.sh
cp autorun-qemu.sh ${OUTDIR}/rootfs/home/

echo "Changing ownership to root"
cd ${OUTDIR}/rootfs
sudo chown -R root:root *

echo "Creating initramfs"
find . | cpio -H newc -ov --owner root:root > ${OUTDIR}/initramfs.cpio
gzip -f ${OUTDIR}/initramfs.cpio

echo "Kernel and initramfs build complete in ${OUTDIR}"
