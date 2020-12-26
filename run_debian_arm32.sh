#!/bin/bash

LROOT=$PWD
JOBCOUNT=${JOBCOUNT=$(nproc)}
export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabi-
export INSTALL_PATH=$LROOT/rootfs_debian_arm32/boot/
export INSTALL_MOD_PATH=$LROOT/rootfs_debian_arm32/
export INSTALL_HDR_PATH=$LROOT/rootfs_debian_arm32/usr/

kernel_build=$PWD/rootfs_debian_arm32/usr/src/linux/
rootfs_path=$PWD/rootfs_debian_arm32
rootfs_image=$PWD/rootfs_debian_arm32.ext4

rootfs_size=1024

SMP="-smp 4"

if [ $# -lt 1 ]; then
	echo "Usage: $0 [arg]"
	echo "build_kernel: build the kernel image."
	echo "build_rootfs: build the rootfs image."
	echo " run:  run debian system."
fi

if [ $# -eq 2 ] && [ $2 == "debug" ]; then
	echo "Enable qemu debug server"
	DBG="-s -S"
	SMP=""
fi

make_kernel_image(){
		echo "start build kernel image..."
		make debian_defconfig
		make -j $JOBCOUNT
}

prepare_rootfs(){
		if [ ! -d $rootfs_path ]; then
			echo "decompressing rootfs..."
			tar -Jxf rootfs_debian_arm32.tar.xz
		fi
}

build_kernel_devel(){
	kernver="$(make -s kernelrelease)"
	echo "kernel version: $kernver"

	mkdir -p $kernel_build
	rm rootfs_debian_arm32/lib/modules/$kernver/build
	cp -a include $kernel_build
	cp Makefile .config Module.symvers System.map $kernel_build
	mkdir -p $kernel_build/arch/arm/
	mkdir -p $kernel_build/arch/arm/kernel/

	cp -a arch/arm/include $kernel_build/arch/arm/
	cp -a arch/arm/Makefile $kernel_build/arch/arm/
	cp arch/arm/kernel/modules.order $kernel_build/arch/arm/kernel/

	ln -s /usr/src/linux rootfs_debian_arm32/lib/modules/$kernver/build

	# ln to debian linux-kbuild-4.19 package
	ln -s /usr/src/linux-kbuild/scripts rootfs_debian_arm32/usr/src/linux/scripts
	ln -s /usr/src/linux-kbuild/tools rootfs_debian_arm32/usr/src/linux/tools
}

check_root(){
		if [ "$(id -u)" != "0" ];then
			echo "superuser privileges are required to run"
			echo "sudo ./run_debian_arm32.sh build_rootfs"
			exit 1
		fi
}

build_rootfs(){
		if [ ! -f $rootfs_image ]; then
			make install
			make modules_install -j $JOBCOUNT
			#make headers_install

			build_kernel_devel

			echo "making image..."
			dd if=/dev/zero of=rootfs_debian_arm32.ext4 bs=1M count=$rootfs_size
			mkfs.ext4 rootfs_debian_arm32.ext4
			mkdir -p tmpfs
			echo "copy data into rootfs..."
			mount -t ext4 rootfs_debian_arm32.ext4 tmpfs/ -o loop
			cp -af rootfs_debian_arm32/* tmpfs/
			umount tmpfs
			chmod 777 rootfs_debian_arm32.ext4
		fi

}

run_qemu_debian(){
		qemu-system-arm -m 1024 -M virt\
			-nographic $SMP -kernel arch/arm/boot/zImage \
			-append "crashkernel=128M root=/dev/vda rootfstype=ext4 rw"\
			-drive if=none,file=rootfs_debian_arm32.ext4,id=hd0 \
			-device virtio-blk-device,drive=hd0 \
			-netdev user,id=mynet\
			-device virtio-net-device,netdev=mynet\
			--fsdev local,id=kmod_dev,path=./kmodules,security_model=none\
			-device virtio-9p-device,fsdev=kmod_dev,mount_tag=kmod_mount\
			$DBG

}

case $1 in
	build_kernel)
		make_kernel_image
		#prepare_rootfs
		#build_rootfs
		;;
	
	build_rootfs)
		#make_kernel_image
		check_root
		prepare_rootfs
		build_rootfs
		;;
	run)

		if [ ! -f $LROOT/arch/arm/boot/Image ]; then
			echo "canot find kernel image, pls run build_kernel command firstly!!"
			exit 1
		fi

		if [ ! -f $rootfs_image ]; then
			echo "canot find rootfs image, pls run build_rootfs command firstly!!"
			exit 1
		fi

		#prepare_rootfs
		#build_rootfs
		run_qemu_debian
		;;
esac

