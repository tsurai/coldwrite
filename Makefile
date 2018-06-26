ARCH ?= i686

ifeq ($(ARCH),i686)
	TRIPLE ?= i686-elf
	QEMU := qemu-system-i386
else
	$(error Unsupported architecture $(ARCH))
endif

LD := $(TRIPLE)-ld
AS := $(TRIPLE)-as
OBJDUMP := $(TRIPLE)-objdump
OBJCOPY := $(TRIPLE)-objcopy

BUILD := build/$(ARCH)/
STAGE1LINKSCRIPT := src/$(ARCH)/stage1.ld
STAGE2LINKSCRIPT := src/$(ARCH)/stage2.ld

# compiler options
ASFLAGS += -I src/$(ARCH)
LINKFLAGS += -Map $(BUILD)map.txt
LINKFLAGS += -n --gc-sections
LINKFLAGS += -z max-page-size=0x1000

# objects
OBJS := stage2.o
OBJS := $(OBJS:%=$(BUILD)%)
DISK := disk.img
STAGE1 := stage1.bin
STAGE2 := stage2.elf

.PHONY: all clean

all: $(DISK) $(STAGE1) $(STAGE2)
	dd if=stage1.bin of=disk.img conv=notrunc
	dd if=stage2.bin of=disk.img obs=512 seek=1 conv=notrunc
	dd if=payload.bin of=disk.img obs=1024 seek=1 conv=notrunc

clean:
	$(RM) -rf $(STAGE1) $(STAGE2) stage2.bin *.dsm *.sym $(DISK) $(BUILD)

test: all
	$(QEMU) -no-reboot -d int -drive file=disk.img,format=raw

$(DISK):
	# create a 100mb disk image with a valid boot partition and MBR
	dd if=/dev/zero of=disk.img bs=1000 count=100000
	(echo o; echo n; echo p; echo 1; echo ""; echo ""; echo a; echo w; echo q) | sudo fdisk disk.img

$(STAGE1): $(BUILD)stage1.o src/$(ARCH)/stage1.S src/$(ARCH)/stage1.ld
	$(LD) -o $@ -T $(STAGE1LINKSCRIPT) $(LINKFLAGS) --oformat binary build/$(ARCH)/stage1.o
	$(OBJDUMP) -S -D -h -b binary -mi8086 $@ > $@.dsm
	test `wc -c < $(STAGE1)` -le 446

$(STAGE2): $(BUILD)stage2.o $(OBJS) src/$(ARCH)/stage2.ld
	$(LD) -T $(STAGE2LINKSCRIPT) $(LINKFLAGS) $(OBJS) -o $@
	$(OBJCOPY) -O binary $@ stage2.bin
	$(OBJDUMP) -S -D -h -b binary -mi8086 $@ > $@.dsm
	$(OBJCOPY) --only-keep-debug $@ $@.sym
	@$(RM) $(STAGE2)

$(BUILD)stage1.o: src/$(ARCH)/stage1.S Makefile
	@mkdir -p $(dir $@)
	$(AS) $(ASFLAGS) -o $@ $<

$(BUILD)stage2.o: src/$(ARCH)/stage2.S Makefile
	$(AS) $(ASFLAGS) -o $@ $<
