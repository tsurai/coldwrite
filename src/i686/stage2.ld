ENTRY(start)

SECTIONS
{
    . = 0x7e00;

    .init :
    {
        KEEP(*(.magic))
    }

    .text :
    {
        *(.text)
    }

    .data :
    {
        *(.data)
    }

    .rodata :
    {
        *(.rodata)
    }

    .bss :
    {
        *(.bss)
    }
}
