.section .text
.code16
# Canonicalize CS:EIP register
ljmp $0x0000, $start
start:
    # Save drive number of the booting device
    mov %dl, drive

    # Initialize register
    xor %ax, %ax
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %ss

    # Initialize stack
    mov $0x7c00, %sp

    # Load and store the VGA font 8x16 font at offset
    # 0x500 which is guaranteed free conventional memory
    call save_vga_font

    # Get the system memory map and store it at
    # offset 0x1500 in memory
    call save_memory_map

    mov $loading_str, %si
    call print16

    # Load the second stage at 0x7e00
    # In the x86 memory map 0x7e00 - 0x7fff (480.5 KiB)
    # is guaranteed free conventional memory
    call load

    # Check second stage magic
    movl 0x7e00, %eax
    cmp $0x41495241, %eax
    jne magic_error

    mov $success_str, %si
    call print16

    # Moving to protected mode
    # Disable interrupts
    cli

    # Load 32bit gdt
    lgdt gdtptr

    # Set protected mode bit in CR0
    mov %cr0, %eax
    or $1, %eax
    mov %eax, %cr0

    ljmp $0x0008, $0x7e04

save_vga_font:
    push %ds
    push $0x0500
    push $0x00

    # get the pointer to the 8x16 VGA font
    mov $0x1130, %ax
    mov $0x06, %bh
    int $0x10

    # setup the source pointer ds:si for movsd
    push %es
    pop %ds
    mov %bp, %si

    # set the destination pointer es:di to 0x0:0x500
    pop %es
    pop %di

    # Copy 4096 bytes in 1024 x 4 byte moves
    mov $0x0400, %cx
    rep movsd
    pop %ds
    ret

save_memory_map:
    # Set the save location for the memory map
    xor %ax, %ax
    mov %ax, %es
    mov $0x1500, %di

    # Set the initial offset to zero
    xor %ebx, %ebx
    xor %bp, %bp

    .map_loop:
    # Set edx to the magic value SMP
    mov $0x534d4150, %edx

    # Set function code with the high 16 bit cleared
    # earlier
    xor %eax, %eax
    mov $0xe820, %eax

    # Copy 24 bytes at a time
    mov $0x14, %ecx
    int $0x15
    jc .map_end

    # Increment the entry counter dl
    inc %bp

    # Increment di by the map entry size of 24 bytes
    add $0x14, %di

    # Test for more entries
    test %ebx, %ebx
    jne .map_loop

    .map_end:
    movw %bp, 0x1600
    clc
    ret

load:
    # read from disk using BIOS int 13h
    mov drive, %dl
    mov $dapack, %si
    mov $0x42, %ah
    int $0x13
    jc .retry
    ret

    # retry to read from a different drive
    .retry:

    # test if drive #0 has been tried
    test $0x00, %dl
    jne load_error

    # and use 0x80 instead
    movb $0x80, drive

    # try to read again
    jmp load

throw_error:
    mov $error_str, %si
    call print16
    mov %cl, %al
    int $0x10
    cli
    hlt

load_error:
    mov $0x31, %cl
    jmp throw_error

magic_error:
    mov $0x32, %cl
    jmp throw_error

print16:
    lodsb
    test %al, %al
    jz .done
    mov $0x0e, %ah
    int $0x10
    jmp print16
.done:
    ret

drive:
    .byte 0

.section .rodata
loading_str:
    .string "Loading second stage... "
success_str:
    .string "success\r\n"
error_str:
    .string "Error: "

dapack:
    .byte 0x10
    .byte 0
    .word 2
    .word 0x7e00
    .word 0
    .long 1
    .long 0

.globl gdt
gdt:
    # NULL entry
    .quad 0x0
    # Code segment
    .word 0xffff     # limit low
    .word 0x0        # base low
    .byte 0x0        # base middle
    .byte 0b10011010 # present | code | readable
    .byte 0b11001111 # granularity | 32bit flag
    .byte 0x0        # base high
    # Data segment
    .word 0xffff     # limit low
    .word 0x0        # base low
    .byte 0x0        # base middle
    .byte 0b10010010 # present | readable
    .byte 0b11001111 # granularity | 32bit flag
    .byte 0x0        # base high
gdtptr:
    .word (gdtptr - gdt - 1)
    .long gdt
