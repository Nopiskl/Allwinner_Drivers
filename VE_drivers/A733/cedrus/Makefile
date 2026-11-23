# SPDX-License-Identifier: GPL-2.0
ifneq ($(KBUILD_EXTMOD),)
obj-m += sunxi-cedrus.o
else
obj-$(CONFIG_VIDEO_SUNXI_CEDRUS) += sunxi-cedrus.o
endif

sunxi-cedrus-y = cedrus.o cedrus_video.o cedrus_hw.o cedrus_dec.o \
		 cedrus_mpeg2.o cedrus_h264.o cedrus_h265.o \
		 cedrus_vp8.o
