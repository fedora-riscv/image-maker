#!/bin/bash
#
# This script is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2,
# as published by the Free Software Foundation.
#
# This script is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this script; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#

set -x

IMAGE_BUILDER='fedora_image_maker'

# this image includes the pkg we need for building a Fedora image
# dnf install util-linux-ng tar appliance-tools git -y
VERSION='41'
DOCKER_IMAGE="docker.io/fedorariscv/base:$VERSION"

MOCK_CONFIG="fedora-riscv64-template.cfg"
PKGS_LIST='appliance-tools git dnf util-linux-ng wget gdisk'
DNF_REPO_URL="http://openkoji.iscas.ac.cn/kojifiles/repos/f$VERSION-build/latest/riscv64/"
DNF_REPO_NAME='bootstrap-repo'

FEDORA_IMAGE_PATH=/home/tekkamanninja/development/RISC-V/images/Fedora-minimal-sda.raw
#ROOTFS_IMAGE_DIR=fedora_rootfs
ROOTFS_NODE=/dev/sda3

KS_REPO_NAME='fedora-riscv64-kickstarts'
KS_REPO_SITE='https://gitee.com/etux'
KS_REPO_BRANCH='fedora_image_maker'

KS_FILE_NAME='fedora-disk-minimal.ks'
IMAGE_NAME='fedora-disk-minimal'

RELEASE_NUM=`date +%Y%m%d%H%M%S`
TMP_DIR='_image'
LOG_DIR="${IMAGE_BUILDER}_log_${RELEASE_NUM}"

DNS_SERVER=1.1.1.1

function check_sudo() {
	# Check if running with sudo privileges
	if [ $(id -u) -ne 0 ]; then
		echo "This script must be run with sudo privileges."
		exit 1
	fi
	return 0
}

function check_command() {
	if ! command -v "${1}" &> /dev/null; then
		echo "${1} command not found. Please install it first."
		exit 1
	fi
}

function check_requirements() {
	check_sudo

	check_command 'qemu-riscv64-static'

	# Check if loop device is loaded and usable
	if ! modprobe loop &> /dev/null; then
		echo "Failed to load loop device. Please check your system configuration."
#		exit 1
	fi

	return 0
}

# create a rootfs by mock for chroot with this script as ${1}/build.sh
# the mock Fedora roofs with some pkgs:
# util-linux-ng tar appliance-tools git
function create_rootfs_by_mock() {

	cleanup_mock_environment

	mock -r fedora-riscv64-template.cfg \
		--rootdir $PWD/${1} \
		--resultdir $PWD/${1}/tmp \
		--config-opts releasever=$VERSION \
		--config-opts root=fedora-$VERSION-riscv64 \
		--install ${PKGS_LIST}

	cp $0 $PWD/${1}/build.sh
}

# create a rootfs by existed Image for chroot with this script as ${1}/build.sh
# the Image should be minimal Fedora image with some pkgs:
# util-linux-ng tar appliance-tools git
function create_rootfs_by_Image() {
	mkdir -p $PWD/${1}
	guestfish -a ${FEDORA_IMAGE_PATH} -m ${ROOTFS_NODE} tar-out / ./${1}.tar
	# release tarball to dir
	pushd ${1}/
	tar -xpf ../${1}.tar
	rm -f ../${1}.tar
	popd
	cp $0 $PWD/${1}/build.sh
}

# create a rootfs by podman for chroot with this script as ${1}/build.sh
# the $DOCKER_IMAGE should be minimal Fedora image with some pkgs:
# util-linux-ng tar appliance-tools git
function create_rootfs_by_podman() {
	# make ${1} for keeping script
	mkdir -p $PWD/${1}  || true
	cp $0 $PWD/${1}/build.sh

	# create rootfs by podman(will be used later too)
	podman create --privileged -t \
		--volume $PWD/${1}:/${1} \
		--name ${1} \
		$DOCKER_IMAGE \
		/bin/bash
}

function create_rootfs_by_dnf() {
	mkdir -p $PWD/${1}  || true
	sudo dnf --installroot $PWD/${1} \
		--repofrompath $DNF_REPO_NAME,$DNF_REPO_URL \
		--repo $DNF_REPO_NAME \
		--nodocs \
		--forcearch riscv64 \
		--nogpgcheck \
		--releasever $VERSION -y install \
		${PKGS_LIST}

	rm -f $PWD/${1}/etc/yum.repos.d/*.repo
	cat > $PWD/${1}/etc/yum.repos.d/bootstrap.repo << EOF
[$DNF_REPO_NAME]
name=$DNF_REPO_NAME
baseurl=$DNF_REPO_URL
gpgcheck=0
EOF

	cp $0 $PWD/${1}/build.sh

}

# export a rootfs by podman for chroot 
function export_rootfs_for_chroot() {
	# export rootfs to tarball
	mkdir -p $PWD/${1}  || true
	podman export ${1} -o ${1}.tar

	# release tarball to dir
	pushd ${1}/
	tar -xpf ../${1}.tar
	rm -f ../${1}.tar
	popd
}

# start a Fedora container for making a Fedora rootfs dir
function startup_podman() {
	podman start ${1}
	podman exec ${1} \
		/bin/bash /${1}/build.sh --podman ${1}
}


function chroot_build() {
	mount -n -o bind /dev ${1}/dev
	chroot ${1} /bin/bash /build.sh --chroot ${2}
	umount ${1}/dev
}

IMGCREATE_CREATOR_PY=/usr/lib/python3.12/site-packages/imgcreate/creator.py
function __hack_selinux() {
	echo "hacking selinux"
	sed -i 's|/sys/fs/selinux|/sys/fs/selinuxfake|g'  \
	${IMGCREATE_CREATOR_PY}
}

function make_image() {
	set -e

	# make loop file node 
	LOOP_FILE=$(losetup -f)
	LOOP_MAJOR=$(printf "%d" 0x$(stat -c %t $LOOP_FILE))
	LOOP_MINOR=$(printf "%d" 0x$(stat -c %T $LOOP_FILE))
	if [ ! -e "$LOOP_FILE" ]; then
		echo "Making $LOOP_FILE node..."
		mknod -m640 $LOOP_FILE b $LOOP_MAJOR $LOOP_MINOR
		echo "Made $LOOP_FILE node "
	else
		echo "$LOOP_FILE node file exists."
	fi

	# setup dns server
	rm -f /etc/resolv.conf
	echo "nameserver ${DNS_SERVER}" > /etc/resolv.conf

	#make sure we have all the tools we need
	dnf install util-linux-ng tar appliance-tools git -y

	if [ "$1" = "hack" ]; then
		__hack_selinux
	fi

	# get kickstart repo
	git clone ${KS_REPO_SITE}/${KS_REPO_NAME}
	cd ${KS_REPO_NAME}
	git switch ${KS_REPO_BRANCH}

	# build image by the given ks file
	mkdir $TMP_DIR
	appliance-creator \
		-c ${KS_FILE_NAME} \
		--name ${IMAGE_NAME} \
		--version f${VERSION} \
		--release ${RELEASE_NUM} \
		-o ${TMP_DIR} \
		-d -v --no-compress
}

function make_image_in_chroot() {

	# INSIDE chroot
	mount -t proc none /proc

	if [ "$1" = "hack" ]; then
		mount -t sysfs none /sys
	fi

	make_image $1

	umount /proc

	if [ "$1" = "hack" ]; then
		umount /sys
	fi
}

# cleanup functions
function cleanup_podman_environment() {
	podman stop ${1}
	podman rm ${1}
}

function cleanup_mock_environment() {
	mock -r fedora-riscv64-template.cfg \
		--config-opts releasever=$VERSION \
		--config-opts root=fedora-$VERSION-riscv64 \
		--scrub=all
}

function move_results_directory() {
	mv $PWD/${1}/${KS_REPO_NAME}/$TMP_DIR/${IMAGE_NAME} \
	$PWD/${IMAGE_NAME}_f${VERSION}_${RELEASE_NUM}
	chmod -R 777 $PWD/${IMAGE_NAME}_f${VERSION}_${RELEASE_NUM}
}

function cleanup_external_environment() {
	MOUNT_POINTS=$(mount | grep $PWD/${1} | awk '{print $3}' | sort -r)

	for mp in $MOUNT_POINTS; do
		umount $mp
	done
	
	rm -rf $PWD/${1}
}

# Create log directory
mkdir -v $LOG_DIR

# Main script execution
case "$1" in
	--podman)
		chroot_build $IMAGE_BUILDER
		;;
	--chroot)
		make_image_in_chroot ${2}
		;;
	--clean)
		check_command 'podman' && cleanup_podman_environment $IMAGE_BUILDER
		check_command 'mock' && cleanup_mock_environment 
		cleanup_external_environment $IMAGE_BUILDER
		;;
	--test)
		#test function can be here
		move_results_directory $IMAGE_BUILDER
		;;
	--image)
		(
			check_sudo
			create_rootfs_by_Image $IMAGE_BUILDER
			chroot_build $IMAGE_BUILDER 'hack'
			move_results_directory $IMAGE_BUILDER
			cleanup_external_environment $IMAGE_BUILDER
			echo "The image is in $PWD/${IMAGE_NAME}_f${VERSION}_${RELEASE_NUM}"
		) |& tee -a "$LOG_DIR/image_build.log"
		;;
	--mock)
		(
			check_sudo
			check_command 'mock'
			create_rootfs_by_mock $IMAGE_BUILDER
			chroot_build $IMAGE_BUILDER 'hack'
			move_results_directory $IMAGE_BUILDER
			cleanup_mock_environment
			cleanup_external_environment $IMAGE_BUILDER
			echo "The image is in $PWD/${IMAGE_NAME}_f${VERSION}_${RELEASE_NUM}"
		) |& tee -a "$LOG_DIR/mock_build.log"
		;;
	--dnf)
		(
			check_sudo
			check_command 'dnf'
			create_rootfs_by_dnf $IMAGE_BUILDER
			chroot_build $IMAGE_BUILDER 'hack'
			move_results_directory $IMAGE_BUILDER
			cleanup_external_environment $IMAGE_BUILDER
			echo "The image is in $PWD/${IMAGE_NAME}_f${VERSION}_${RELEASE_NUM}"
		) |& tee -a "$LOG_DIR/dnf_build.log"
		;;
	--hack)
		(
			check_sudo
			create_rootfs_by_podman $IMAGE_BUILDER
			export_rootfs_for_chroot $IMAGE_BUILDER
			cleanup_podman_environment $IMAGE_BUILDER
			chroot_build $IMAGE_BUILDER 'hack'
			move_results_directory $IMAGE_BUILDER
			cleanup_external_environment $IMAGE_BUILDER
			echo "The image is in $PWD/${IMAGE_NAME}_f${VERSION}_${RELEASE_NUM}"
		) |& tee -a "$LOG_DIR/hack_build.log"
		;;
	*)
		(
			#default build mode: chroot in podman
			check_requirements
			create_rootfs_by_podman $IMAGE_BUILDER
			export_rootfs_for_chroot $IMAGE_BUILDER
			startup_podman $IMAGE_BUILDER
			cleanup_podman_environment $IMAGE_BUILDER
			move_results_directory $IMAGE_BUILDER
			cleanup_external_environment $IMAGE_BUILDER
			echo "The image is in $PWD/${IMAGE_NAME}_f${VERSION}_${RELEASE_NUM}"
		) |& tee -a "$LOG_DIR/build.log"
		;;
esac
