.section .magic, "a"
magic:
    .align 8
    .long 0x41495241

.set sector_offset, 0x3
# set automatically by make
.set sector_count, 1954

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

    # get the vga test buffer address and cursor position
    call get_vga_info

    # get a valid save location for the payload
    call get_save_location

    mov $writing_str, %esi
    call print_str

    mov $destination, %esi
    call print_hex_32

    mov $dots_str, %esi
    call print_str

    # initialize all necessary register to zero
    xor %eax, %eax
    mov %eax, %ebx
    mov %eax, %ecx
    mov %eax, %edi

    # set data transfer data
    mov $sector_count, %ebx      # count of sectors to be read
    mov $sector_offset, %ecx     # LBA offset
    mov destination, %edi        # destination memory address

    # read data from disk into memory
    call ata_pio28_read

    mov $done_str, %esi
    call print_str

    cli
    hlt

get_save_location:
    # get the number of memory map entries
    xor %ecx, %ecx
    movw (0x1500), %cx

    # make esi point to the start of the memory map
    mov $0x1502, %esi

    # get the region type of the current entry
    .next_entry:
    movl 16(%esi), %eax
    test $0x1, %eax
    jz .get_next

    # get the start address of the memory block
    mov (%esi), %eax

    # get the block size
    mov 8(%esi), %ebx

    # skip if it is part of the BDA or EBDA
    # A memory block may start within the BDA and still be long enough to
    # contain the payload after the BDA end at 0x100000

    # get the difference between the block starting address and the BDA end
    mov %eax, %ecx
    sub $0x100000, %ecx

    # skip ahead if they don't overlap
    jns .check_size

    # check if the block size is large enough to include the difference
    neg %ecx
    cmp %ecx, %ebx
    jb .get_next

    # adjust the block start and size with the difference to the BDA
    sub %ecx, %ebx
    add %ecx, %eax

    # calculate the size of the payload in bytes
    .check_size:
    mov $sector_count, %ecx
    imul $0x200, %ecx

    # check if the memory block is large enough for the payload
    cmp %ebx, %ecx
    ja .get_next

    # save the payload destination address and return
    mov %eax, destination
    ret

    # check if there are more entries in the memory map and process next
    .get_next:
    inc %bx
    add $0x14, %esi
    cmp %bx, %cx
    jne .next_entry

    # no suitable destination for the payload has been found
    .map_end:
    mov $no_save_location_str, %esi
    call throw_error
    ret

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

    # set lowest byte of LBA
    mov $0x1f3, %dx
    mov %ecx, %eax
    out %al, %dx

    # set second lowest byte of LBA
    mov $0x1f4, %dx
    mov %ah, %al
    out %al, %dx

    #set third lowest byte of LBA
    mov $0x1f5, %dx
    shr $16, %eax
    out %al, %dx

    # set sector count to be read
    # PIO can only read 255 sectors at once
    xor %eax, %eax
    mov $0x1f2, %dx

    # split into chunks of <= 255 sectors
    mov $0xff, %al
    cmp $0xff, %bx
    jg .skip
    mov %bl, %al
    .skip:

    # increase LBA
    add %eax, %ecx

    # decrease sectors to read
    sub %eax, %ebx

    # set sectors to be read from disk
    out %al, %dx

    # save LBA, sector count and the current chunk size on the stack
    push %ebx
    push %ecx
    push %ax

    # send read sectors command
    mov $0x1f7, %dx
    mov $0x20, %al
    out %al, %dx

    # ignore error bit the first four times as the ATA specs suggest a
    # 400ms delay before trying to send a command
    mov $0x4, %ecx
    .delay_loop:

    # read the status flag
    in %dx, %al

    # is BUSY set
    test $0x80, %al
    jne .retry

    # is DRQ set
    test $0x8, %al
    jne .data_rdy

    # retry up to four times
    .retry:
    dec %ecx
    jg .delay_loop

    # pop the chunk size into bx
    xor %ebx, %ebx
    pop %bx

    # read the status flag
    .prior:
    mov $0x1f7, %dx
    in %dx, %al

    # is still busy
    test $0x80, %al
    jne .prior

    # is ERR or DF
    test $0x21, %al
    jne .read_error

    # copy 256 16-bit words from the I/O port into memory at edi
    .data_rdy:
    mov $0x100, %ecx
    mov $0x1f0, %dx
    rep insw
    mov $0x1f7, %dx

    # decrease the current chunk count and read more if there is more
    dec %bx
    test %bx, %bx
    jne .prior

    # restore the LBA and sector count
    pop %ecx
    pop %ebx

    # repeat until all sectors have been read
    test %ebx, %ebx
    jnz ata_pio28_read
    ret

    .read_error:
    mov $failed_str, %esi
    call throw_error

    ret

get_vga_info:
    # read the equipment word from the BDA
    mov (0x410), %ax

    # bit 4-5 signal the VGA display mode
    and $0x30, %ax
    cmp $0x20, %ax
    jg .monochrome

    # use color mode buffer address
    movl $0xb8000, video_memory
    jmp .get_pos

    # use monochrome mode buffer address
    .monochrome:
    movl $0xb0000, video_memory

    .get_pos:
    call get_cursor_pos
    ret

get_cursor_pos:
    # select high cursor position register
    mov $0x3d4, %dx
    mov $0x0e, %al
    out %al, %dx

    # get low cursor position byte
    mov $0x3d5, %dx
    in %dx, %al
    mov %al, %bh

    # select high cursor position register
    mov $0x3d4, %dx
    mov $0x0f, %al
    out %al, %dx

    # get high cursor position byte
    mov $0x3d5, %dx
    in %dx, %al
    mov %al, %bl

    # save the buffer cursor offset
    mov %bx, video_offset
    ret

set_cursor_pos:
    # select high cursor position register
    mov $0x3d4, %dx
    mov $0x0e, %al
    out %al, %dx

    # set high cursor position byte
    mov $0x3d5, %dx
    mov %bh, %al
    out %al, %dx

    # select high cursor postition register
    mov $0x3d4, %dx
    mov $0x0f, %al
    out %al, %dx

    # set high cursor position byte
    mov $0x3d5, %dx
    mov %bl, %al
    out %al, %dx

    # save the buffer cursor offset
    mov %bx, video_offset
    ret

print_str:
    # clear ecx
    xor %ecx, %ecx

    mov video_memory, %edi
    mov video_offset, %cx

    # set black background with light grey foreground color
    mov $0x07, %ah

    # load the first character
    movb (%esi), %al

    .next_char:
    movw %ax, (%edi,%ecx,2)

    # increase source and offset pointer
    inc %esi
    inc %ecx

    # load the next byte
    movb (%esi), %al

    # continue until it's a NULL byte
    test %al, %al
    jnz .next_char

    # set the new cursor position
    mov %ecx, %ebx
    call set_cursor_pos
    ret

print_hex_16:
     push %ecx

    # iterate over all four bytes
    mov $0x1, %ecx
    call print_hex_x

    pop %ecx
    ret

print_hex_32:
    push %ecx

    # iterate over all four bytes
    mov $0x3, %ecx
    call print_hex_x

    pop %ecx
    ret

print_hex_x:
    push %ebx
    push %ax
    push %bx

    # get the load byte
    .next_byte:
    mov (%esi, %ecx, 1), %bl

    call print_byte_as_hex

    # iterate until all bytes have been printed
    dec %ecx
    cmp $0x0, %ecx
    jge .next_byte

    # set the new cursor position
    mov video_offset, %ebx
    call set_cursor_pos

    pop %bx
    pop %ax
    pop %ebx

    ret

print_byte_as_hex:
    push %ecx

    xor %ecx, %ecx

    mov video_memory, %edi
    mov video_offset, %cx

    mov $0x07, %ah

    # print the upper hex symbol
    mov %bl, %al
    shr $0x4, %al
    call dec_to_hex_ascii
    movw %ax, (%edi,%ecx,2)

    inc %cx

    # print the lower hex symbol
    mov %bl, %al
    and $0xf, %al
    call dec_to_hex_ascii
    movw %ax, (%edi,%ecx,2)

    # advance the offset counter without changing the cursor position
    # it is the callees responsibility to set the cursor after all hex
    # values have been printed
    inc %cx
    mov %cx, video_offset

    pop %ecx
    ret

dec_to_hex_ascii:
    cmp $0xA, %al
    jl .decimal
    add $0x7, %al

    .decimal:
    add $0x30, %al
    ret

throw_error:
    call print_str
    cli
    hlt

.section .rodata
writing_str:
    .string "Writing payload into memory at 0x"
dots_str:
    .string "... "
done_str:
    .string "done"
failed_str:
    .string "failed"
no_save_location_str:
    .string "Failed to find a valid save location"

.section .bss
destination:
    .quad 0
video_memory:
    .quad 0
video_offset:
    .word 0
