`timescale 1ns/1ps

// runs one riscv-tests image to completion. the test reports its result by
// writing to `tohost`: 1 means pass, anything else is (failing test number << 1) | 1.
// the image is linked at the ram base and loaded straight into the ram, the core
// boots through the boot rom like it would on a board.
module test_riscv;

  parameter IMAGE = "";                // hex image (one 32-bit word per line)
  parameter logic [31:0] TOHOST = 0;   // address of the tohost symbol
  parameter WORDS = 8192;              // 32 KiB of ram
  parameter MAX_CYCLES = 400000;
  parameter FETCH_WAIT = 0;            // wait states on the memories, see bus
  parameter DATA_WAIT = 0;

  localparam real CLK_HALF_PERIOD = 5.0;
  localparam [31:0] RAM_BASE = 32'h8000_0000;

  reg clk;
  reg rst_n;

  soc #(
    .RAM_INIT(IMAGE),
    .RAM_WORDS(WORDS),
    .FETCH_WAIT(FETCH_WAIT),
    .DATA_WAIT(DATA_WAIT)
  ) dut (
    .clk(clk),
    .rst_n(rst_n)
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

  wire [31:0] tohost_word = dut.bus_inst.ram_inst.mem[(TOHOST - RAM_BASE) >> 2];

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
        $display("FAIL: timeout after %0d cycles, pc=0x%08x", cycles, dut.core_inst.pc);
        $finish;
      end
    end
  end

endmodule
