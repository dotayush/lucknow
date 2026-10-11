/* a flat file: text, rodata and data are contiguous from address 0 (the 64 byte header goes in front) */
ENTRY(_start)
SECTIONS {
  . = 0;
  .text : { *(.text.start) *(.text .text.*) }
  .rodata : { *(.rodata .rodata.* .srodata .srodata.*) }
  .data : { *(.data .data.* .sdata .sdata.*) }
  _data_end = .;
  .bss : { *(.bss .bss.* .sbss .sbss.* COMMON) }
  _bss_end = .;
}
