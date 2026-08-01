# Top-level build for out-of-tree modules (local builds and DKMS).
KERNELRELEASE ?= $(shell uname -r)
KDIR ?= /lib/modules/$(KERNELRELEASE)/build

.PHONY: all clean modules_install install

all: modules

modules:
	$(MAKE) -C $(KDIR) M=$(CURDIR)/drivers/sec_ts modules
	$(MAKE) -C $(KDIR) M=$(CURDIR)/drivers/backlight modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR)/drivers/sec_ts clean
	$(MAKE) -C $(KDIR) M=$(CURDIR)/drivers/backlight clean

modules_install:
	$(MAKE) -C $(KDIR) M=$(CURDIR)/drivers/sec_ts modules_install
	$(MAKE) -C $(KDIR) M=$(CURDIR)/drivers/backlight modules_install

install: modules_install

# Build Debian/Ubuntu binary package (install debhelper, build-essential, dpkg-dev, fakeroot first).
.PHONY: deb
deb:
	dpkg-buildpackage -us -uc -b