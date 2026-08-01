sec_ts-y := sec_ts_main.o sec_ts_fw.o sec_ts_fn.o sec_ts_selftest.o
obj-m += sec_ts.o

KERNELRELEASE ?= $(shell uname -r)
KDIR ?= /lib/modules/$(KERNELRELEASE)/build
PWD := $(shell pwd)

all:
	make -C $(KDIR) M=$(PWD) modules

clean:
	make -C $(KDIR) M=$(PWD) clean