OUTPUT_ARCH( "riscv" )
ENTRY(_start)

/* one flat image: loaded into the ram (and, for the harvard l0, into both memories) */
SECTIONS
{
  . = DEFINED(RAM_BASE) ? RAM_BASE : 0x0; /* --defsym=RAM_BASE=.. for cores whose ram doesn't start at 0 */
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
