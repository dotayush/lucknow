`timescale 1ns/1ps

// runs one riscv-tests image to completion. the test reports its result by
// writing to `tohost`: 1 means pass, anything else is (failing test number << 1) | 1.
module test_riscv;

  parameter IMAGE = "";                // hex image (one 32-bit word per line)
  parameter logic [31:0] TOHOST = 0;   // address of the tohost symbol
  parameter WORDS = 8192;              // 32 KiB
  parameter MAX_CYCLES = 200000;

  localparam real CLK_HALF_PERIOD = 5.0;

  reg clk;
  reg rst_n;

  wire [1:0] mem_error;
  wire mem_read;
  wire mem_write;
  wire [1:0] mem_access_type;
  wire [31:0] mem_addr;
  wire [31:0] mem_data_out;
  wire [31:0] mem_data_in;

  control #(
    .CACHE_SIZE(WORDS),
    .IMEM_INIT(IMAGE)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .core_id(5'd0),
    .mem_error(mem_error),
    .mem_read(mem_read),
    .mem_write(mem_write),
    .mem_access_type(mem_access_type),
    .mem_addr(mem_addr),
    .mem_data_out(mem_data_out),
    .mem_data_in(mem_data_in)
  );

  // data memory, holds the same image as the instruction cache
  cache #(
    .CACHE_SIZE(WORDS),
    .MEM_INIT(IMAGE)
  ) ram (
    .clk(clk),
    .rst_n(rst_n),
    .mem_write(mem_write),
    .mem_read(mem_read),
    .mem_access_type(mem_access_type),
    .addr(mem_addr),
    .data_in(mem_data_out),
    .data_out(mem_data_in),
    .mem_error(mem_error)
  );

  initial begin
    clk = 0;
    forever #(CLK_HALF_PERIOD) clk = !clk;
  end

  initial begin
    rst_n = 0;
    repeat (2) @(posedge clk);
    #1 rst_n = 1;
  end

  wire [31:0] tohost_word = ram.mem[TOHOST >> 2];

  integer cycles;
  initial begin
    cycles = 0;
    forever begin
      @(posedge clk);
      cycles = cycles + 1;
      if (tohost_word !== 32'h0) begin
        if (tohost_word === 32'h1) begin
          $display("PASS (%0d cycles)", cycles);
        end else begin
          $display("FAIL: test number %0d (tohost=0x%08x, %0d cycles)", tohost_word >> 1, tohost_word, cycles);
        end
        $finish;
      end
      if (cycles >= MAX_CYCLES) begin
        $display("FAIL: timeout after %0d cycles, pc=0x%08x", cycles, dut.pc);
        $finish;
      end
    end
  end

endmodule
