#!/bin/bash
set -e
set -x

NUM_CPUS=`nproc`
echo "###############"
echo "### Using ${NUM_CPUS} cores"

# setup some build variables
BUILD_USER=vagrant
BUILD_GROUP=vagrant
BUILD_ROOT=/var/kernel_build
BUILD_CACHE=$BUILD_ROOT/cache
KERNEL=kernel8
LINUX_KERNEL=$BUILD_CACHE/linux-kernel
LINUX_KERNEL_COMMIT=6f921e98008589258f97243fb6658d09750f0a2f # Linux 5.15.32 raspberrypi-kernel_1.20220331-1
# LINUX_KERNEL_COMMIT=36612d5d7a88672a3e7dd6cb458dbbbca0d75efe # Linux 4.14.79 raspberrypi-kernel_1.20181112-1
# LINUX_KERNEL_COMMIT=675e29ff7124059cb3b8b56fd7ae0ea131196982 # Linux 4.14.70 raspberrypi-kernel_1.20180919-1
# LINUX_KERNEL_COMMIT=f70eae405b5d75f7c41ea300b9f790656f99a203 # Linux 4.14.34
# LINUX_KERNEL_COMMIT=be97febf4aa42b1d019ad24e7948739da8557f66 # Linux 4.9.80
# LINUX_KERNEL_COMMIT=6820d0cbec64cfee481b961833feffec8880111e # Linux 4.9.59
# LINUX_KERNEL_COMMIT=04c8e47067d4873c584395e5cb260b4f170a99ea # Linux 4.4.50
# LINUX_KERNEL_COMMIT=04c8e47067d4873c584395e5cb260b4f170a99ea # Linux 4.4.50
# LINUX_KERNEL_COMMIT=1ebe8d4a4c96cd6a90805c74233a468854960f67 # Linux 4.4.43
# LINUX_KERNEL_COMMIT=5e46914b3417fe9ff42546dcacd0f41f9a0fb172 # Linux 4.4.39
# LINUX_KERNEL_COMMIT=1c8b82bcb72f95d8f9d606326178192a2abc9c9c # Linux 4.4.27
# LINUX_KERNEL_COMMIT=e14824ba0cc70de7cbb7b34c28a00cf755ceb0dc # Linux 4.4.24
# LINUX_KERNEL_COMMIT=4eda74f2dfcc8875482575c79471bde6766de3ad # Linux 4.4.15
# LINUX_KERNEL_COMMIT=52261e73a34f9ed7f1d049902842895a2c433a50 # Linux 4.4.10
# LINUX_KERNEL_COMMIT=36311a9ec4904c080bbdfcefc0f3d609ed508224 # Linux 4.1.8
# LINUX_KERNEL_COMMIT="59e76bb7e2936acd74938bb385f0884e34b91d72"
# LINUX_KERNEL_COMMIT=1f58c41a5aba262958c2869263e6fdcaa0aa3c00
RASPBERRY_FIRMWARE=$BUILD_CACHE/rpi_firmware

if [ -d /vagrant ]; then
  # running in vagrant VM
  SRC_DIR=/vagrant
else
  # running in Circle build
  SRC_DIR=`pwd`
  BUILD_USER=`id -u -n`
  BUILD_GROUP=`id -g -n`
fi

LINUX_KERNEL_CONFIGS=$SRC_DIR/kernel_configs

NEW_VERSION=`date +%Y%m%d-%H%M%S`

BUILD_RESULTS=$BUILD_ROOT/results/kernel-$NEW_VERSION

declare -A CCPREFIX
CCPREFIX["rpi2_3"]=aarch64-linux-gnu-

declare -A ORIGDEFCONFIG
#ORIGDEFCONFIG["rpi1"]=bcmrpi_defconfig
ORIGDEFCONFIG["rpi2_3"]=bcm2711_defconfig

declare -A DEFCONFIG
#DEFCONFIG["rpi1"]=rpi1_docker_defconfig
DEFCONFIG["rpi2_3"]=rpi2_3_docker_defconfig

declare -A IMAGE_NAME
#IMAGE_NAME["rpi1"]=kernel.img
IMAGE_NAME["rpi2_3"]=kernel8.img

function create_dir_for_build_user () {
    local target_dir=$1

    mkdir -p $target_dir
    chown $BUILD_USER:$BUILD_GROUP $target_dir
}

function setup_build_dirs () {
  for dir in $BUILD_ROOT $BUILD_CACHE $BUILD_RESULTS $LINUX_KERNEL $RASPBERRY_FIRMWARE; do
    create_dir_for_build_user $dir
  done
}

function clone_or_update_repo_for () {
  local repo_url=$1
  local repo_path=$2
  local repo_commit=$3

  if [ ! -z "${repo_commit}" ]; then
    rm -rf $repo_path
  fi
  if [ -d ${repo_path}/.git ]; then
    pushd $repo_path
    #git reset --hard HEAD
    #git pull
    popd
  else
    echo "Cloning $repo_path with commit $repo_commit"
    git clone --depth=1 $repo_url $repo_path
  fi
}

function setup_linux_kernel_sources () {
  echo "### Check if Raspberry Pi Linux Kernel repository at ${LINUX_KERNEL} is still up to date"
  clone_or_update_repo_for 'https://github.com/raspberrypi/linux.git' $LINUX_KERNEL $LINUX_KERNEL_COMMIT
  echo "### Cleaning .version file for deb packages"
  rm -f $LINUX_KERNEL/.version
}

function setup_rpi_firmware () {
  echo "### Check if Raspberry Pi Firmware repository at ${LINUX_KERNEL} is still up to date"
  clone_or_update_repo_for 'https://github.com/RPi-Distro/firmware' $RASPBERRY_FIRMWARE ""
}

function prepare_kernel_building () {
  setup_build_dirs
  setup_linux_kernel_sources
  setup_rpi_firmware
}


create_kernel_for () {
  echo "###############"
  echo "### START building kernel for ${PI_VERSION}"

  local PI_VERSION=$1

  cd $LINUX_KERNEL

  # add kernel branding for HypriotOS
  sed -i 's/^EXTRAVERSION =.*/EXTRAVERSION = -hypriotos/g' Makefile

  # save git commit id of this build
  local KERNEL_COMMIT=`git rev-parse HEAD`
  echo "### git commit id of this kernel build is ${KERNEL_COMMIT}"

  # clean build artifacts
  make ARCH=arm64 clean

  # copy kernel configuration file over
  cp $LINUX_KERNEL/arch/arm64/configs/${ORIGDEFCONFIG[${PI_VERSION}]} $LINUX_KERNEL/arch/arm64/configs/${DEFCONFIG[${PI_VERSION}]}
  cat $LINUX_KERNEL_CONFIGS/docker_delta_defconfig >> $LINUX_KERNEL/arch/arm64/configs/${DEFCONFIG[${PI_VERSION}]}

  echo "### building kernel"
  mkdir -p $BUILD_RESULTS/$PI_VERSION
  echo $KERNEL_COMMIT > $BUILD_RESULTS/kernel-commit.txt
  if [ ! -z "${MENUCONFIG}" ]; then
    cp $LINUX_KERNEL/arch/arm64/configs/${DEFCONFIG[${PI_VERSION}]} $LINUX_KERNEL/.config
    echo "### starting menuconfig"
    ARCH=arm64 CROSS_COMPILE=${CCPREFIX[$PI_VERSION]} make menuconfig
    echo "### saving new config back to $LINUX_KERNEL_CONFIGS/${PI_VERSION}_docker_kernel_config"
    cp $LINUX_KERNEL/.config $LINUX_KERNEL_CONFIGS/${PI_VERSION}_docker_kernel_config
    ARCH=arm64 CROSS_COMPILE=${CCPREFIX[$PI_VERSION]} make savedefconfig
    cp $LINUX_KERNEL/defconfig $LINUX_KERNEL_CONFIGS/${PI_VERSION}_docker_defconfig
    return
  fi

  echo "### building kernel and deb packages"
  ARCH=arm64 CROSS_COMPILE=${CCPREFIX[${PI_VERSION}]} make ${DEFCONFIG[${PI_VERSION}]} deb-pkg -j$NUM_CPUS

  version=$(/vagrant/scripts/mkknlimg --ddtk $LINUX_KERNEL/arch/arm64/boot/Image $BUILD_RESULTS/$PI_VERSION/${IMAGE_NAME[${PI_VERSION}]} | head -1 | sed 's/Version: //')
  suffix=""
  if [ "$PI_VERSION" == "rpi2_3" ]; then
    suffix="8"
  fi
  echo "$version" > $RASPBERRY_FIRMWARE/extra/uname_string$suffix

  echo "### installing kernel modules"
  mkdir -p $BUILD_RESULTS/$PI_VERSION/modules
  ARCH=arm64 CROSS_COMPILE=${CCPREFIX[${PI_VERSION}]} INSTALL_MOD_PATH=$BUILD_RESULTS/$PI_VERSION/modules make modules_install -j$NUM_CPUS

  echo "### Listing $BUILD_RESULTS/$PI_VERSION/modules"
  ls -l $BUILD_RESULTS/$PI_VERSION/modules

  # remove symlinks, mustn't be part of raspberrypi-bootloader*.deb
  echo "### removing symlinks"
  rm -f $BUILD_RESULTS/$PI_VERSION/modules/lib/modules/*/build
  rm -f $BUILD_RESULTS/$PI_VERSION/modules/lib/modules/*/source

  if [[ ! -z $CIRCLE_ARTIFACTS ]]; then
    cp ../*.deb $CIRCLE_ARTIFACTS
  fi
  mv ../*.deb $BUILD_RESULTS
  echo "###############"
  echo "### END building kernel for ${PI_VERSION}"
  echo "### Check the $BUILD_RESULTS/$PI_VERSION/kernel.img and $BUILD_RESULTS/$PI_VERSION/modules directory on your host machine."
}

function create_kernel_deb_packages () {
  echo "###############"
  echo "### START building kernel DEBIAN PACKAGES"

  PKG_TMP=`mktemp -d`

  NEW_KERNEL=$PKG_TMP/raspberrypi-kernel-${NEW_VERSION}

  create_dir_for_build_user $NEW_KERNEL

  # copy over source files for building the packages
  echo "copying firmware from $RASPBERRY_FIRMWARE to $NEW_KERNEL"
  # skip modules directory from standard tree, because we will our on modules below
  tar --exclude=modules --exclude=headers --exclude=.git -C $RASPBERRY_FIRMWARE -cf - . | tar -C $NEW_KERNEL -xvf -
  # create an empty modules directory, because we have skipped this above
  mkdir -p $NEW_KERNEL/modules/
  cp -r $SRC_DIR/debian $NEW_KERNEL/debian
  touch $NEW_KERNEL/debian/files

  mkdir -p $NEW_KERNEL/headers/
  for deb in $BUILD_RESULTS/linux-headers-*.deb; do
    dpkg -x $deb $NEW_KERNEL/headers/
  done

  for pi_version in ${!CCPREFIX[@]}; do
    cp $BUILD_RESULTS/$pi_version/${IMAGE_NAME[${pi_version}]} $NEW_KERNEL/boot
    cp -R $BUILD_RESULTS/$pi_version/modules/lib/modules/* $NEW_KERNEL/modules
  done
  echo "copying dtb files to $NEW_KERNEL/boot"
  cp $LINUX_KERNEL/arch/arm64/boot/dts/broadcom/bcm27*.dtb $NEW_KERNEL/boot
  # build debian packages
  cd $NEW_KERNEL

  (cd $NEW_KERNEL/debian ; ./gen_bootloader_postinst_preinst.sh)

  dch --check-dirname-level=0 -b -v ${NEW_VERSION} --package raspberrypi-firmware 'add Hypriot custom kernel'
  ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- debuild --check-dirname-level=0 --no-lintian -ePATH="${PATH}:/usr/aarch64-linux-gnu/bin/" -b -aarm64 -us -uc
  cp ../*.deb $BUILD_RESULTS
  if [[ ! -z $CIRCLE_ARTIFACTS ]]; then
    cp ../*.deb $CIRCLE_ARTIFACTS
  fi

  echo "###############"
  echo "### FINISH building kernel DEBIAN PACKAGES"
}


##############
###  main  ###
##############

echo "*** all parameters are set ***"
echo "*** the kernel timestamp is: $NEW_VERSION ***"
echo "#############################################"

# clear build cache to fetch the current raspberry/firmware
rm -fr $RASPBERRY_FIRMWARE

# setup necessary build environment: dir, repos, etc.
prepare_kernel_building

# create kernel, associated modules
for pi_version in ${!CCPREFIX[@]}; do
  create_kernel_for $pi_version
done

# create kernel packages
create_kernel_deb_packages

# running in vagrant VM
if [ -d /vagrant ]; then
  # copy build results to synced vagrant host folder
  FINAL_BUILD_RESULTS=/vagrant/build_results/$NEW_VERSION
else
  # running in Circle build
  FINAL_BUILD_RESULTS=$SRC_DIR/output/$NEW_VERSION
fi

echo "###############"
echo "### Copy deb packages to $FINAL_BUILD_RESULTS"
mkdir -p $FINAL_BUILD_RESULTS
cp $BUILD_RESULTS/*.deb $FINAL_BUILD_RESULTS
cp $BUILD_RESULTS/*.txt $FINAL_BUILD_RESULTS

ls -lh $FINAL_BUILD_RESULTS
echo "*** kernel build done"
