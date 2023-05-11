#!/bin/sh

REVISION=1

APT_MIRROR_URL=http://ftp.tw.debian.org/debian

MESA_SRC_FILE=$(find -maxdepth 1 -name mesa-\*.tar.\* | sort -r -V | head -1)
MESA_VERSION=$(echo "${MESA_SRC_FILE}"| grep -o '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*')
MESA_OPTIONS='-Dplatforms=x11,wayland -Dgallium-drivers=radeonsi,swrast -Dvulkan-drivers=amd,swrast -Dgallium-vdpau=enabled -Dlmsensors=enabled -Dglvnd=true -Dosmesa=true -Dvideo-codecs=vc1dec,h264dec,h264enc,h265dec,h265enc'

prepare_rootfs ()
{
	ARCH=$1
	BUILDDEPS=$(cat builddeps.txt | tr '\n' ',')

	mkdir -p rootfs/${ARCH}
	unshare -m debootstrap --variant=minbase --arch=${ARCH} --include=${BUILDDEPS} bookworm rootfs/${ARCH} ${APT_MIRROR_URL}
}

build_mesa ()
{
	ARCH=$1
	prepare_rootfs ${ARCH}
	tar xf ${MESA_SRC_FILE} -C rootfs/${ARCH}
	chroot rootfs/${ARCH} sh -c "cd mesa-${MESA_VERSION} ; meson build/ --prefix=/usr --buildtype=release ${MESA_OPTIONS} ; cd build ; ninja ; DESTDIR=/target ninja install "
	chroot rootfs/${ARCH} sh -c "cd target/usr/lib/*/dri && mv swrast_dri.so libgallium_dri.so"
	chroot rootfs/${ARCH} sh -c "cd target/usr/lib/*/dri && ln -sf libgallium_dri.so swrast_dri.so"
	chroot rootfs/${ARCH} sh -c "cd target/usr/lib/*/dri && ln -sf libgallium_dri.so radeonsi_dri.so"
	chroot rootfs/${ARCH} sh -c "cd target/usr/lib/*/dri && ln -sf libgallium_dri.so kms_swrast_dri.so"
}

build_package ()
{
	ARCH=$1

	CONTROL_FILE=rootfs/${ARCH}/target/DEBIAN/control

	mkdir -p rootfs/${ARCH}/target/DEBIAN
	cp control rootfs/${ARCH}/target/DEBIAN/

	sed -i "s/\${MESA_ARCH}/${ARCH}/g" ${CONTROL_FILE}
	sed -i "s/\${MESA_VERSION}/${MESA_VERSION}-${REVISION}/g" ${CONTROL_FILE}

	cat remove-${ARCH}.txt | xargs -i rm -rf "rootfs/${ARCH}/target/{}"

	fakeroot dpkg-deb -b rootfs/${ARCH}/target/ mesa_${MESA_VERSION}-${REVISION}_${ARCH}.deb
}

build_mesa amd64
build_mesa i386

build_package amd64
build_package i386
