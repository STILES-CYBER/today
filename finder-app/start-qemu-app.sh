#!/bin/bash
# Script to open QEMU terminal.
# Author: Siddhant Jajoo.

set -e

OUTDIR=${1:-/tmp/aeld}

KERNEL_IMAGE=${OUTDIR}/Image
INITRD_IMAGE=${OUTDIR}/initramfs.cpio.gz

if [ ! -e ${KERNEL_IMAGE} ]; then
    echo "Missing kernel image at ${KERNEL_IMAGE}"
    exit 1
fi
if [ ! -e ${INITRD_IMAGE} ]; then
    echo "Missing initrd image at ${INITRD_IMAGE}"
    exit 1
fi

echo "Booting the kernel..."
qemu-system-aarch64 \
    -m 256M \
    -M virt \
    -cpu cortex-a53 \
    -nographic \
    -smp 1 \
    -kernel ${KERNEL_IMAGE} \
    -chardev stdio,id=char0,mux=on,logfile=${OUTDIR}/serial.log,signal=off \
    -serial chardev:char0 -mon chardev=char0 \
    -append "rdinit=/home/autorun-qemu.sh console=ttyAMA0" \
    -initrd ${INITRD_IMAGE}
