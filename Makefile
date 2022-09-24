.SUFFIXES:
.ONESHELL:
.DEFAULT_GOAL:=all

ARCH:=amd64 i386
DISTRO:=bullseye
REVISION:=1
DEBIAN_APT_REPO:=http://opensource.nchc.org.tw/debian
WAYLAND_OPTS:=-Ddocumentation=false
MESA_OPTS:=-Dplatforms=x11,wayland -Dgallium-drivers=radeonsi,swrast -Dvulkan-drivers=amd -Ddri-drivers= -Dgallium-vdpau=true -Dlmsensors=enabled -Dglvnd=true


MESA_SRC_FILE:=$(shell find -maxdepth 1 -name mesa-\*.tar.\* | sort -r -V | head -1)
MESA_VERSION:=$(shell echo "$(MESA_SRC_FILE)"| grep -o '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*')
LIBDRM_SRC_FILE:=$(shell find -maxdepth 1 -name libdrm-\*.tar.\* | sort -r -V | head -1)
LIBDRM_VERSION:=$(shell echo "$(LIBDRM_SRC_FILE)" | grep -o '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*')
WAYLAND_SRC_FILE:=$(shell find -maxdepth 1 -name wayland-[0-9]\*.tar.\* | sort -r -V | head -1)
WAYLAND_VERSION:=$(shell echo "$(WAYLAND_SRC_FILE)" | grep -o '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*')
WAYLAND_PROTOCOLS_SRC_FILE:=$(shell find -maxdepth 1 -name wayland-protocols-\*.tar.\* | sort -r -V | head -1)
WAYLAND_PROTOCOLS_VERSION:=$(shell echo "$(WAYLAND_PROTOCOLS_SRC_FILE)" | grep -o '[0-9][0-9]*\.[0-9][0-9]*')
BUILDDEPS:=$(shell cat builddeps.txt | tr '\n' ',')
DEB_OUTPUTS:=$(foreach arch,$(ARCH),mesa_$(MESA_VERSION)-$(REVISION)_$(arch).deb)
MOUNT_OVERLAYS:=$(foreach arch,$(ARCH),mount_overlay_$(arch))


$(foreach arch,$(ARCH),rootfs/$(arch)): rootfs/%:
	@mkdir -p $@
	debootstrap --arch=$$(basename $@) --variant=minbase --include=$(BUILDDEPS) $(DISTRO) $@ $(DEBIAN_APT_REPO)

$(foreach arch,$(ARCH),overlay/diff/$(arch)) $(foreach arch,$(ARCH),overlay/work/$(arch)) $(foreach arch,$(ARCH),overlay/build/$(arch)):
	@mkdir -p $@

$(foreach arch,$(ARCH),debian/$(arch)): debian/%:
	@mkdir -p $@/DEBIAN
	cp control $@/DEBIAN/control
	sed -i "s/\$${MESA_ARCH}/$$(basename $@)/g" $@/DEBIAN/control
	sed -i 's/$${MESA_VERSION}/$(MESA_VERSION)-$(REVISION)/g' $@/DEBIAN/control
	sed -i 's/$${LIBDRM_VERSION}/$(LIBDRM_VERSION)-$(REVISION)/g' $@/DEBIAN/control
	sed -i 's/$${WAYLAND_VERSION}/$(WAYLAND_VERSION)-$(REVISION)/g' $@/DEBIAN/control
	sed -i 's/$${WAYLAND_PROTOCOLS_VERSION}/$(WAYLAND_PROTOCOLS_VERSION)-$(REVISION)/g' $@/DEBIAN/control

$(ARCH): %: | rootfs/% overlay/diff/% overlay/work/% overlay/build/%
	@mount -t overlay -o lowerdir=rootfs/$@,upperdir=overlay/diff/$@,workdir=overlay/work/$@ overlay-$@ overlay/build/$@
	mkdir overlay/build/$@/target
	tar xf $(WAYLAND_SRC_FILE) -C overlay/build/$@
	tar xf $(WAYLAND_PROTOCOLS_SRC_FILE) -C overlay/build/$@
	tar xf $(LIBDRM_SRC_FILE) -C overlay/build/$@
	tar xf $(MESA_SRC_FILE) -C overlay/build/$@
	chroot overlay/build/$@ sh -c "cd wayland-$(WAYLAND_VERSION); meson build/ --prefix=/usr --buildtype=release $(WAYLAND_OPTS) ; cd build ; ninja ; DESTDIR=/target ninja install ; ninja install"
	chroot overlay/build/$@ sh -c "cd wayland-protocols-$(WAYLAND_PROTOCOLS_VERSION); meson build/ --prefix=/usr --buildtype=release; cd build ; ninja ; DESTDIR=/target ninja install ; ninja install"
	chroot overlay/build/$@ sh -c "cd libdrm-$(LIBDRM_VERSION); meson build/ --prefix=/usr --buildtype=release; cd build ; ninja ; DESTDIR=/target ninja install ; ninja install"
	chroot overlay/build/$@ sh -c "cd mesa-$(MESA_VERSION); meson build/ --prefix=/usr --buildtype=release $(MESA_OPTS) ; cd build ; ninja ; DESTDIR=/target ninja install"
	umount overlay/build/$@

$(foreach arch,$(ARCH),prepare_$(arch)): prepare_%: % debian/%
	@ARCH=$<
	cp -r overlay/diff/$${ARCH}/target/usr debian/$${ARCH}/
	LIBPATH=$$(ls debian/$${ARCH}/usr/lib)
	mv debian/$${ARCH}/usr/lib/$${LIBPATH}/dri/radeonsi_dri.so debian/$${ARCH}/usr/lib/$${LIBPATH}/dri/libgallium_dri.so
	ln -sf libgallium_dri.so debian/$${ARCH}/usr/lib/$${LIBPATH}/dri/kms_swrast_dri.so
	ln -sf libgallium_dri.so debian/$${ARCH}/usr/lib/$${LIBPATH}/dri/radeonsi_dri.so
	ln -sf libgallium_dri.so debian/$${ARCH}/usr/lib/$${LIBPATH}/dri/swrast_dri.so
	[ "$${ARCH}" = "i386" ] && rm -rf debian/$${ARCH}/usr/include debian/$${ARCH}/usr/share/* debian/$${ARCH}/usr/bin/*
	[ "$${ARCH}" = "i386" ] && cp -r overlay/diff/$${ARCH}/target/usr/share/vulkan debian/$${ARCH}/usr/share/
	exit 0

$(DEB_OUTPUTS): mesa_$(MESA_VERSION)-$(REVISION)_%.deb: prepare_%
	@ARCH=$$(echo $< | sed 's/prepare_//g')
	fakeroot dpkg-deb -b debian/$${ARCH} $@

all: $(DEB_OUTPUTS)

clean:
	@rm -rf *.deb overlay debian
