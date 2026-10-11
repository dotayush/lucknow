`ifndef ISA_SHARED_IMPORT
  `define ISA_SHARED_IMPORT
  import isa_shared::*;
`endif

// holds the wait for one port: ready is low for WAIT cycles after a new request shows up
// and stays high for as long as the same request is held.
module wait_states #(
  parameter int WAIT = 0,
  parameter int ID_WIDTH = 32
)(
  input wire clk,
  input wire rst_n,
  input wire req,
  input wire [ID_WIDTH-1:0] req_id, // what is requested, the wait starts over when it changes
  output wire ready
);

  reg last_req;
  reg [ID_WIDTH-1:0] last_id;
  reg [31:0] waited; // cycles this request has already been held

  wire same = req && last_req && (req_id == last_id);
  wire [31:0] held = same ? waited : 32'd0;

  assign ready = !req || (held >= WAIT);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      last_req <= 0;
      last_id <= '0;
      waited <= 0;
    end
    else begin
      last_req <= req;
      last_id <= req_id;
      waited <= req ? (same ? waited + 1 : 32'd1) : 32'd0;
    end
  end

endmodule

// address decoder between the core and the memories. one memory map for both ports:
//
//   ROM_BASE  boot rom, read only
//   RAM_BASE  ram, the instruction port and the data port see the same words
//   UART_BASE uart (16550 register layout, UART_SIZE bytes, registers repeat), byte accesses
//             only, data port only
//
// anything else is an access fault (OUT_OF_BOUNDS), as is a store to the rom, a word or
// halfword access to the uart and a fetch that isn't word aligned. the ports mirror
// control's: imem_* for fetch, mem_* for data.
module bus #(
  parameter DATA_WIDTH = 32,
  parameter [DATA_WIDTH-1:0] ROM_BASE = 32'h0000_1000,
  parameter int ROM_WORDS = 1024,
  parameter [DATA_WIDTH-1:0] RAM_BASE = 32'h8000_0000,
  parameter int RAM_WORDS = 8192,
  parameter [DATA_WIDTH-1:0] UART_BASE = 32'h1000_0000,
  parameter int UART_SIZE = 256,
  parameter int UART_CLKS_PER_BIT = 8,
  parameter bit UART_ECHO = 0,
  parameter ROM_INIT = "./memory/bootrom.hex",
  parameter RAM_INIT = "",
  parameter int FETCH_WAIT = 0, // wait cycles added to every new fetch
  parameter int DATA_WAIT = 0 // wait cycles added to every new data access
)(
  input wire clk,
  input wire rst_n,

  // instruction port
  input wire [DATA_WIDTH-1:0] imem_addr,
  output reg [DATA_WIDTH-1:0] imem_data,
  output wire imem_ready,
  output reg [1:0] imem_error,

  // data port
  input wire mem_read,
  input wire mem_write,
  input wire [1:0] mem_access_type,
  input wire [DATA_WIDTH-1:0] mem_addr,
  input wire [DATA_WIDTH-1:0] mem_wdata,
  output reg [DATA_WIDTH-1:0] mem_rdata,
  output wire mem_ready,
  output reg [1:0] mem_error,

  // serial console
  output wire uart_tx
);

  // fetch side regions
  wire f_rom = (imem_addr >= ROM_BASE) && ((imem_addr - ROM_BASE) < ROM_WORDS * 4);
  wire f_ram = (imem_addr >= RAM_BASE) && ((imem_addr - RAM_BASE) < RAM_WORDS * 4);
  // data side regions
  wire d_rom = (mem_addr >= ROM_BASE) && ((mem_addr - ROM_BASE) < ROM_WORDS * 4);
  wire d_ram = (mem_addr >= RAM_BASE) && ((mem_addr - RAM_BASE) < RAM_WORDS * 4);
  wire d_uart = (mem_addr >= UART_BASE) && ((mem_addr - UART_BASE) < UART_SIZE);

  wire [DATA_WIDTH-1:0] rom_rdata, ram_rdata, rom_fdata, ram_fdata;
  wire [1:0] rom_error, ram_error, rom_ferror, ram_ferror;

  wait_states #(.WAIT(FETCH_WAIT), .ID_WIDTH(DATA_WIDTH)) fetch_wait (
    .clk(clk), .rst_n(rst_n), .req(1'b1), .req_id(imem_addr), .ready(imem_ready)
  );

  wait_states #(.WAIT(DATA_WAIT), .ID_WIDTH(DATA_WIDTH + 4)) data_wait (
    .clk(clk), .rst_n(rst_n), .req(mem_read || mem_write),
    .req_id({mem_write, mem_read, mem_access_type, mem_addr}), .ready(mem_ready)
  );

  cache #(
    .DATA_WIDTH(DATA_WIDTH),
    .CACHE_SIZE(ROM_WORDS),
    .MEM_INIT(ROM_INIT)
  ) rom_inst (
    .clk(clk),
    .rst_n(rst_n),
    .mem_write(1'b0),
    .mem_read(mem_read && d_rom),
    .mem_access_type(mem_access_type),
    .addr(mem_addr - ROM_BASE),
    .data_in('0),
    .data_out(rom_rdata),
    .mem_error(rom_error),
    .fetch_addr(imem_addr - ROM_BASE),
    .fetch_data(rom_fdata),
    .fetch_error(rom_ferror)
  );

  cache #(
    .DATA_WIDTH(DATA_WIDTH),
    .CACHE_SIZE(RAM_WORDS),
    .MEM_INIT(RAM_INIT)
  ) ram_inst (
    .clk(clk),
    .rst_n(rst_n),
    .mem_write(mem_write && d_ram && mem_ready), // lands once, on the edge where the transfer completes
    .mem_read(mem_read && d_ram),
    .mem_access_type(mem_access_type),
    .addr(mem_addr - RAM_BASE),
    .data_in(mem_wdata),
    .data_out(ram_rdata),
    .mem_error(ram_error),
    .fetch_addr(imem_addr - RAM_BASE),
    .fetch_data(ram_fdata),
    .fetch_error(ram_ferror)
  );

  // uart: register access completes on the edge that completes the transfer, like a ram write
  wire [7:0] uart_rdata;
  wire uart_byte = (mem_access_type == BYTE_MEM_ACCESS);
  uart #(
    .CLKS_PER_BIT(UART_CLKS_PER_BIT),
    .ECHO(UART_ECHO)
  ) uart_inst (
    .clk(clk),
    .rst_n(rst_n),
    .sel((mem_read || (mem_write && mem_ready)) && d_uart && uart_byte),
    .write(mem_write),
    .reg_addr(mem_addr[2:0]),
    .wdata(mem_wdata[7:0]),
    .rdata(uart_rdata),
    .tx(uart_tx)
  );

  always @* begin
    imem_data = '0;
    imem_error = OUT_OF_BOUNDS; // unmapped
    if (f_ram) begin
      imem_data = ram_fdata;
      imem_error = ram_ferror;
    end
    else if (f_rom) begin
      imem_data = rom_fdata;
      imem_error = rom_ferror;
    end
  end

  always @* begin
    mem_rdata = '0;
    mem_error = NO_MEM_ERROR;
    if (mem_read || mem_write) begin
      mem_error = OUT_OF_BOUNDS; // unmapped
      if (d_ram) begin
        mem_rdata = ram_rdata;
        mem_error = ram_error;
      end
      else if (d_rom) begin
        mem_rdata = rom_rdata;
        mem_error = mem_write ? OUT_OF_BOUNDS : rom_error; // read only
      end
      else if (d_uart && uart_byte) begin
        mem_rdata = {24'h0, uart_rdata};
        mem_error = NO_MEM_ERROR;
      end
    end
  end

endmodule
