include /usr/share/dpkg/pkg-info.mk

PACKAGE=pve-container

GITVERSION:=$(shell git rev-parse HEAD)
BUILDDIR ?= $(PACKAGE)-$(DEB_VERSION_UPSTREAM)

DEB=$(PACKAGE)_$(DEB_VERSION_UPSTREAM_REVISION)_all.deb
DSC=$(PACKAGE)_$(DEB_VERSION_UPSTREAM_REVISION).dsc

all: $(DEB)

.PHONY: dinstall
dinstall: $(DEB)
	dpkg -i $(DEB)

$(BUILDDIR): src debian
	rm -rf $(BUILDDIR) $(BUILDDIR).tmp; mkdir $(BUILDDIR).tmp
	cp -t $(BUILDDIR).tmp -a debian src/*
	echo "git clone https://github.com/jiangcuo/pve-container\\ngit checkout $(GITVERSION)" >$(BUILDDIR).tmp/debian/SOURCE
	mv $(BUILDDIR).tmp $(BUILDDIR)

.PHONY: deb
deb: $(DEB)
$(DEB): $(BUILDDIR)
	cd $(BUILDDIR); dpkg-buildpackage -b -us -uc
	lintian $(DEB)


.PHONY: dsc
dsc: $(DSC)
$(DSC): $(BUILDDIR)
	cd $(BUILDDIR); dpkg-buildpackage -S -us -uc -d
	lintian $(DSC)

.PHONY: sbuild
sbuild: $(DSC)
	sbuild $(DSC)

.PHONY: clean
clean:
	$(MAKE) -C src clean
	rm -rf $(PACKAGE)-[0-9]*/
	rm -f *.deb *.changes *.build *.buildinfo *.dsc $(PACKAGE)*.tar*

.PHONY: distclean
distclean: clean

.PHONY: upload
upload: UPLOAD_DIST ?= $(DEB_DISTRIBUTION)
upload: $(DEB)
	tar cf - $(DEB) | ssh -X repoman@repo.proxmox.com -- upload --product pve --dist $(UPLOAD_DIST)
