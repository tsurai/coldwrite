SECTIONS
{
    . = 0x7c00;

    .text :
    {
       *(.text)
    }

    .rodata :
    {
        KEEP(*(.rodata))
    }

    . += (466 - SIZEOF(.text) - SIZEOF(.rodata));
}
