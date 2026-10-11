// the core and its memory system, wired together.
module soc #(
  parameter DATA_WIDTH = 32,
  parameter ROM_INIT = "./memory/bootrom.hex",
  parameter RAM_INIT = "", // program image, loaded at the ram base
  parameter int RAM_WORDS = 8192,
  parameter int FETCH_WAIT = 0, // see bus
  parameter int DATA_WAIT = 0,
  parameter int UART_CLKS_PER_BIT = 8,
  parameter bit UART_ECHO = 0 // print what the uart sends, in simulation
)(
  input wire clk,
  input wire rst_n,
  output wire uart_tx
);

  wire [DATA_WIDTH-1:0] imem_addr;
  wire [DATA_WIDTH-1:0] imem_data;
  wire imem_ready;
  wire [1:0] imem_error;

  wire mem_read;
  wire mem_write;
  wire [1:0] mem_access_type;
  wire [DATA_WIDTH-1:0] mem_addr;
  wire [DATA_WIDTH-1:0] mem_data_out;
  wire [DATA_WIDTH-1:0] mem_data_in;
  wire mem_ready;
  wire [1:0] mem_error;

  wire [63:0] mtime;
  wire msip;
  wire mtip;

  control #(
    .DATA_WIDTH(DATA_WIDTH)
  ) core_inst (
    .clk(clk),
    .rst_n(rst_n),
    .core_id(5'd0),
    .imem_addr(imem_addr),
    .imem_data(imem_data),
    .imem_ready(imem_ready),
    .imem_error(imem_error),
    .mem_read(mem_read),
    .mem_write(mem_write),
    .mem_access_type(mem_access_type),
    .mem_addr(mem_addr),
    .mem_data_out(mem_data_out),
    .mem_data_in(mem_data_in),
    .mem_ready(mem_ready),
    .mem_error(mem_error),
    .irq_software(msip),
    .irq_timer(mtip),
    .time_value(mtime)
  );

  bus #(
    .DATA_WIDTH(DATA_WIDTH),
    .ROM_INIT(ROM_INIT),
    .RAM_INIT(RAM_INIT),
    .RAM_WORDS(RAM_WORDS),
    .FETCH_WAIT(FETCH_WAIT),
    .DATA_WAIT(DATA_WAIT),
    .UART_CLKS_PER_BIT(UART_CLKS_PER_BIT),
    .UART_ECHO(UART_ECHO)
  ) bus_inst (
    .clk(clk),
    .rst_n(rst_n),
    .imem_addr(imem_addr),
    .imem_data(imem_data),
    .imem_ready(imem_ready),
    .imem_error(imem_error),
    .mem_read(mem_read),
    .mem_write(mem_write),
    .mem_access_type(mem_access_type),
    .mem_addr(mem_addr),
    .mem_wdata(mem_data_out),
    .mem_rdata(mem_data_in),
    .mem_ready(mem_ready),
    .mem_error(mem_error),
    .uart_tx(uart_tx),
    .mtime(mtime),
    .msip(msip),
    .mtip(mtip)
  );

endmodule
