coldwrite
===
Simple bootable tool for writing a given payload into the physical memory of a machine for demonstration of a [cold boot attack].
Having a known payload at a known location helps calculating and showcasing the degration of random access memory over time.

### Features
* i686 assembler code
* Tiny image (excluding the payload)
* Bootloader code to prevent memory corruption by other hardware or software components
* Automatic search for a suitable, guaranteed usable save location

### Usage
```bash
cd coldwrite

# copy the payload into the directory
cp $PAYLOAD ./payload.bin

# build the image
make

# copy the image to a bootable device e.g. USB drive
dd if=coldwrite.img of=/dev/sdx
```

[cold boot attack]: https://en.wikipedia.org/wiki/Cold_boot_attack
