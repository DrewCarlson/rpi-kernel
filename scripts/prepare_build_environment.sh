#!/bin/bash

apt-get update

# needed by compile-kernel
for package in git build-essential libncurses-dev bc tree fakeroot devscripts binfmt-support qemu qemu-user-static debootstrap kpartx lvm2 dosfstools apt-cacher-ng debhelper quilt bison flex gcc-aarch64-linux-gnu crossbuild-essential-arm64 libssl-dev devscripts dh-make; do
  apt-get install -y $package
done
