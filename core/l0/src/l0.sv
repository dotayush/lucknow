`ifndef ISA_SHARED_IMPORT
  `define ISA_SHARED_IMPORT
  import isa_shared::*;
`endif

// the l0 core with its own instruction and data memory. this is what the tests and the simulation
// use. a design that brings its own memory instantiates l0_core (control.sv) instead.
module control #(
  parameter DATA_WIDTH = 32,
  parameter WORDS = 64,
  parameter IMEM_INIT = "./memory/test_rom.hex", // program image loaded into instruction memory
  parameter DMEM_INIT = "" // optional image preloaded into data memory
) (
    input wire clk,
    input wire rst_n
);

  wire [DATA_WIDTH-1:0] imem_addr, imem_data;
  wire [1:0] imem_err;
  wire [DATA_WIDTH-1:0] dmem_addr, dmem_wdata, dmem_rdata;
  wire [1:0] dmem_size, dmem_err;
  wire dmem_read, dmem_write;

  l0_core #(
    .DATA_WIDTH(DATA_WIDTH)
  ) core_inst (.*);

  // data memory (ram)
  memory #(
    .DATA_WIDTH(DATA_WIDTH),
    .MEM_INIT(DMEM_INIT),
    .WORDS(WORDS)
  ) data_memory_inst (
    .clk(clk),
    .rst_n(rst_n),
    .addr(dmem_addr),
    .data_in(dmem_wdata),
    .mem_read(dmem_read),
    .mem_write(dmem_write),
    .data_out(dmem_rdata),
    .mem_access_type(dmem_size),
    .mem_error(dmem_err)
  );

  // instruction memory (rom)
  memory #(
    .DATA_WIDTH(DATA_WIDTH),
    .MEM_INIT(IMEM_INIT),
    .WORDS(WORDS)
  ) instruction_memory_inst (
    .clk(clk),
    .rst_n(rst_n),
    .addr(imem_addr),
    .data_in(0), // No write to instruction memory
    .mem_read('1), // Always read from instruction memory
    .mem_write('0), // No write to instruction memory
    .data_out(imem_data),
    .mem_access_type(isa_shared::WORD_MEM_ACCESS),
    .mem_error(imem_err)
  );

endmodule
