.section .magic, "a"
magic:
    .align 8
    .long 0x41495241

.section .text
.globl start
.code32
start:
    # Set up segment registers
    mov $0x10, %ax
    mov %ax, %ss
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %fs
    mov %ax, %gs

    # Enable A20 line to address high memory
    in $0x92, %al
    test $2, %al

    # Skip if its already enabled because it might
    # cause problems on some legacy hardware
    jnz .a20set
    or $2, %al
    and $0xfe, %al
    out %al, $0x92
    .a20set:

    // TODO: write payload to memory

    hlt

.section .data
gdt:
    # NULL entry
    .quad 0
    # Code segment
    .word 0xffff     # limit low
    .word 0          # base low
    .byte 0          # base middle
    .byte 0b10011010 # present | code | readable
    .byte 0b11001111 # granularity | 32bit flag
    .byte 0          # base high
    # Data segment
    .word 0xffff     # limit low
    .word 0          # base low
    .byte 0          # base middle
    .byte 0b10010010 # present | readable
    .byte 0b11001111 # granularity | 32bit flag
    .byte 0          # base high
gdtptr:
    .word gdtptr - gdt
    .long gdt
