OUTPUT_ARCH( "riscv" )
ENTRY(_start)

/* one flat image: the same hex is loaded into both instruction and data memory */
SECTIONS
{
  . = 0x0;
  .text.init : { *(.text.init) }
  . = ALIGN(0x40);
  .tohost : { *(.tohost) }
  . = ALIGN(0x40);
  .text : { *(.text) }
  . = ALIGN(0x40);
  .data : { *(.data) }
  .bss : { *(.bss) }
  _end = .;
}
