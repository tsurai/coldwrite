.section .text
.code16
# Canonicalize CS:EIP register
ljmp $0x0000, $start
start:
    # Save drive number of the booting device
    mov %dl, drive

    # Initialize register
    xor %ax, %ax
    mov %ax, %ss

    # Initialize stack
    mov $0x7c00, %sp

    # Load and store the VGA font 8x16 font at offset
    # 0x500 which is guaranteed free conventional memory
    call save_vga_font

    # Try to enter a higher VBE mode and store the
    # ModeInfoBlock at 0x1500 in memory
    call vbe_change_mode

    # Get the system memory map and store it at
    # offset 0x1600 in memory
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
    mov $0x1602, %di

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

vbe_change_mode:
    # Set VBEInfoBlock save location
    # 0x1500 is ~30KiB of guaranteed free conventional memory
    xor %ax, %ax
    mov %ax, %es
    mov $0x1600, %di

    # Indicate that we want VBE 3.0 information by setting
    # the signature to VBE2
    movl $0x32454256, 0x1600

    # Get VBE controller informations
    mov $0x4f00, %ax
    int $0x10

    # Check the return status code
    cmp $0x004f, %ax
    jne vbe_error

    # Check the VESA signature
    movl 0x1600, %eax
    cmp $0x41534556, %eax
    jne vbe_error

    # Check for a VESA version higher than 1.x
    movb 0x1604, %al
    cmp $0x01, %al
    je vbe_error

    call vbe_iterate_modes
    ret

vbe_iterate_modes:
    # Set ds:si to point to the VBE mode list
    xor %eax, %eax
    mov %ax, %ds
    movw 0x160e, %si

    # Iterate over the mode list
    .loop:
    lodsw
    # Stop at the delimiter element
    cmp $0xffff, %ax
    je .end

    # Query mode specific info
    call vbe_get_mode_info
    cmp $0x01, %bx
    jne .loop

    # Set the VBE mode
    call vbe_set_mode

    .end:
    ret

vbe_get_mode_info:
    # Clear return status
    xor %bx, %bx

    # Save the mode info block right after the
    # controller info block
    mov $0x1500, %di

    # Get the VBE mode info for a specific mode
    mov %ax, %cx
    mov $0x4f01, %ax
    int $0x10

    # Check the return status code
    cmp $0x004f, %ax
    jne vbe_error

    # Load attribute word into ax
    # Check for graphics mode and linear buffer
    movw 0x1500, %ax
    and $0xb8, %ax
    cmp $0xb8, %ax
    jne .skip

    # Check for 1920x1080 resolution
    movl 0x1512, %eax
    cmp $0x04380780, %eax
    jne .skip

    # Check for 32bit colors resolution
    movb 0x1519, %al
    cmp $0x20, %al
    jne .skip

    # Indicate that the right mode has been found
    mov $0x01, %bx

    .skip:
    ret

vbe_set_mode:
    # set the new VBE mode
    mov %cx, %bx
    mov $0x4f02, %ax
    int $0x10

    # check the return status code
    cmp $0x004f, %ax
    jne throw_error
    ret

load:
    mov drive, %dl
    xor %ax, %ax
    mov %ax, %ds
    mov $dapack, %si
    mov $0x42, %ah
    int $0x13
    jc throw_error
    ret

throw_error:
    mov $error_str, %si
    call print16
    mov %cl, %al
    int $0x10
    cli
    hlt

read_error:
    mov $0x31, %cl
    jmp throw_error

magic_error:
    mov $0x32, %cl
    jmp throw_error

vbe_error:
    mov $0x33, %cl
    jmp throw_error

print16:
    lodsb
    test %al, %al
    jz .done
    mov $0x07, %bl 
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
    .word 128
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
