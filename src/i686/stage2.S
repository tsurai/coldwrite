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

    # Test if A20 line is already enabled
    in $0x92, %al
    test $2, %al

    # Skip if its already enabled because it might
    # cause problems on some legacy hardware
    jnz .a20set
    or $2, %al
    and $0xfe, %al
    out %al, $0x92
    .a20set:

    # set data transfer data
    mov $0x8, %ebx          # count of sectors to be read
    mov $0x2, %ecx          # LBA offset
    mov $0x100000, %edi     # destination buffer memory address

    # read data from disk into memory
    call ata_pio28_read

    cli
    hlt

ata_pio28_read:
    # select master and set highest 4 bits of the LBA
    mov $0x1f6, %dx
    mov %ecx, %eax
    shr $24, %eax
    and $0x0F, %al
    or $0xe0, %al
    out %al, %dx

    # waste some time to wait for the controller
    mov $0x1f1, %dx
    mov $0x00, %al
    out %al, %dx

    # set sector count to be read
    mov $0x1f2, %dx
    mov %bl, %al
    out %al, %dx

    # set lowest bytw of LBA
    mov $0x1f3, %dx
    mov %ecx, %eax
    out %al, %dx

    # set second lowest bytw of LBA
    mov $0x1f4, %dx
    mov %ah, %al
    out %al, %dx

    #set third lowest bytw of LBA
    mov $0x1f5, %dx
    shr $16, %eax
    out %al, %dx

    # send read sectors command
    mov $0x1f7, %dx
    mov $0x20, %al
    out %al, %dx

    mov $0x4, %ecx
    .lp1:
    in %dx, %al
    test $0x80, %al
    jne .retry
    test $0x8, %al
    jne .data_rdy
    .retry:
    dec %ecx
    jg .lp1

    .prior:
    mov $0x1f7, %dx
    in %dx, %al
    test $0x80, %al
    jne .prior

    .data_rdy:
    mov $0x100, %ecx
    mov $0x1f0, %dx
    rep insw

    dec %ebx
    test %bl, %bl
    jne .prior

    ret
