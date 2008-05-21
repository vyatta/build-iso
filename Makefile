#!/usr/bin/make
## Top level Makefile for Vyatta System Build

export MAKEFLAGS

UID := $(shell id -u)
ifneq ($(UID),0)
FAKEROOT = fakeroot
FAKEPERMISSIONS = -i .permissions -s .permissions
FAKECHROOT = fakechroot
endif

define mk_iso
@rm -rf livecd/.lock livecd/.permissions
cd livecd && $(FAKEROOT) $(FAKEPERMISSIONS) $(FAKECHROOT) ./mk.livecd
endef

have_linux_kernel_di := $(shell test -e pkgs/linux-kernel-di-i386-2.6/debian/rules && echo -n true)
ifeq ($(have_linux_kernel_di),true)

define clean_udebs
rm -f pkgs/*.udebs
endef

define mk_udebs
cd pkgs/linux-kernel-di-i386-2.6 ; \
$(FAKEROOT) debuild -e SOURCEDIR=../../livecd/chroot -d -us -uc
mkdir -p vyatta-udebs
mv pkgs/*.udeb vyatta-udebs
apt-ftparchive packages vyatta-udebs > Packages
gzip -c9 Packages > Packages.gz
Date=`date`; sed "s/^\(Date:\).*/\1 $$Date/" Release.template > Release
for p in Packages Packages.gz ; do \
	sum=`md5sum $$p | cut -d' ' -f 1` ; \
	sz=`stat -c %s Packages` ; \
	printf " %32s %8s main/debian-installer/binary-i386/%s\n" \
		$$sum $$sz $$p >> Release ; \
done
endef

endif

have_installer := $(shell test -e pkgs/installer/build/Makefile && echo -n true)
ifeq ($(have_installer),true)

inst_builddir = pkgs/installer/build
inst_instdir  = usr/share/vyatta-install
inst_graphicsdir = usr/share/graphics
inst_themesdir = usr/share/themes/vyatta/gtk-2.0
kernelname = $(notdir $(lastword $(wildcard livecd/chroot/boot/vmlinuz-*-vyatta)))
kernelversion = $(subst vmlinuz-,,$(kernelname))

define clean_installer
$(FAKEROOT) make -C $(inst_builddir) --quiet --no-print-directory \
	clean_netboot clean_netboot-gtk
rm -f	$(inst_builddir)/config/local \
	$(inst_builddir)/pkg-lists/netboot/local
rm -rf	$(inst_builddir)/$(inst_instdir) \
	$(inst_builddir)/$(inst_graphicsdir) \
	$(inst_builddir)/$(inst_themesdir)
endef

define mk_installer
mkdir -p $(inst_builddir)/$(inst_instdir)
cp	d-i/vyatta_preseed.cfg \
	d-i/vyatta_early_command \
	d-i/vyatta_late_command \
	d-i/vyatta_grub_theme \
	d-i/vyatta_lower_right_640x480.tga \
	d-i/vyatta_event_ttyS0 \
	livecd/chroot_local-includes/vyatta-pubkey.gpg \
	livecd/binary_local-includes/isolinux/data/vyatta.rle \
	$(inst_builddir)/$(inst_instdir)
mkdir -p $(inst_builddir)/$(inst_themesdir)
cp d-i/vyatta_gtkrc $(inst_builddir)/$(inst_themesdir)/gtkrc
mkdir -p $(inst_builddir)/$(inst_graphicsdir)
cp d-i/vyatta_logo.png $(inst_builddir)/$(inst_graphicsdir)/logo_debian.png
@printf "%s %s %s\n" \
	KERNELNAME = $(kernelname) \
	KERNELVERSION = $(kernelversion) \
	VERSIONED_SYSTEM_MAP = t \
	PRESEED = $(inst_instdir)/vyatta_preseed.cfg \
	SPLASH_RLE  = $(inst_instdir)/vyatta.rle \
	EXTRAFILES += $(inst_instdir)/vyatta_early_command \
	EXTRAFILES += $(inst_instdir)/vyatta_late_command \
	EXTRAFILES += $(inst_instdir)/vyatta_grub_theme \
	EXTRAFILES += $(inst_instdir)/vyatta_lower_right_640x480.tga \
	EXTRAFILES += $(inst_instdir)/vyatta_event_ttyS0 \
	EXTRAFILES += $(inst_instdir)/vyatta-pubkey.gpg \
	EXTRAFILES += $(inst_themesdir)/gtkrc \
	EXTRAFILES += $(inst_graphicsdir)/logo_debian.png \
	> $(inst_builddir)/config/local
@printf "%s\n" \
	'# kvm-qemu' \
	'ata-modules-$${kernel:Version}' \
	'sata-modules-$${kernel:Version}' \
	'scsi-modules-$${kernel:Version}' \
	'scsi-core-modules-$${kernel:Version}' \
	'cdrom-core-modules-$${kernel:Version}' \
	'usb-storage-modules-$${kernel:Version}' \
	'fat-modules-$${kernel:Version}' \
	'ext3-modules-$${kernel:Version}' \
	'' \
	'# serial console' \
	'serial-modules-$${kernel:Version}' \
	> $(inst_builddir)/pkg-lists/netboot/local
$(FAKEROOT) make -C $(inst_builddir) \
	SECOPTS="--allow-unauthenticated --force-yes" \
	CONSOLE="console=ttyS0 DEBIAN_FRONTEND=text" \
	build_netboot
$(FAKEROOT) make -C $(inst_builddir) \
	SECOPTS="--allow-unauthenticated --force-yes" \
	CONSOLE="theme=vyatta" \
	build_netboot-gtk
endef

endif

all :
	tools/submod-mk
	$(mk_iso)

.PHONY : udebs
udebs :
	$(mk_udebs)

.PHONY : installer
installer :
	$(mk_installer)

.PHONY : iso
iso :
	$(mk_iso)

.PHONY : mostlyclean
mostlyclean :
	@for m in proc-live sysfs-live devpts-live ; do \
		if grep -q $$m /proc/mounts ; then umount $$m ; fi \
	 done
	@rm -rf livecd/{.permissions,.stage,binary,*.iso,chroot,config,.lock}
	@ipcs -q | awk '{print $$2}' | egrep [0-9] \
	 	| xargs -L 1 ipcrm -q >& /dev/null || /bin/true

.PHONY : clean
clean :
	@$(MAKE) mostlyclean
	@tools/submod-clean
	@$(clean_udebs)
	@$(clean_installer)
	@rm -rf livecd/cache/stage*

.PHONY : clean-installer
clean-installer :
	@$(clean_installer)

.PHONY : distclean
distclean :
	@$(MAKE) clean
	@rm -rf livecd/{cache,deb-install,deb-install.tar}