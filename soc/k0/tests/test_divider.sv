`timescale 1ns/1ps
import isa_shared::*;

module test_divider;

  localparam int DATA_WIDTH = 32;
  reg test_failed;

  task finish;
    begin
      if (test_failed) begin
        $display("Test failed!");
      end else begin
        $display("Test passed!");
      end
      $finish; // End simulation
    end
  endtask

  reg clk = 0;
  always #5 clk = ~clk;
  reg rst_n;
  reg run;
  reg [4:0] alu_op;
  reg [DATA_WIDTH-1:0] a;
  reg [DATA_WIDTH-1:0] b;
  wire done;
  wire [DATA_WIDTH-1:0] result;

  divider #(
    .DATA_WIDTH(DATA_WIDTH)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .run(run),
    .alu_op(alu_op),
    .a(a),
    .b(b),
    .done(done),
    .result(result)
  );

  integer cycles;

  // run one divide like control.sv does: run goes high, the core is held until done, the result is read on the clock
  // done is high (that is the clock the instruction retires), then run drops
  task check_div(input [4:0] op, input [DATA_WIDTH-1:0] sa, input [DATA_WIDTH-1:0] sb, input [DATA_WIDTH-1:0] expected);
    begin
      alu_op = op;
      a = sa;
      b = sb;
      run = 1;
      cycles = 0;
      @(negedge clk);
      while (!done && cycles < 100) begin
        @(negedge clk);
        cycles = cycles + 1;
      end
      if (!done) begin
        test_failed = 1;
        $display("[%0t] error: operation=%0d a=0x%08x b=0x%08x never finished", $time, op, sa, sb);
      end else begin
        if (result !== expected) begin
          test_failed = 1;
          $display("[%0t] error: operation=%0d a=0x%08x b=0x%08x expected 0x%08x, got 0x%08x", $time, op, sa, sb, expected, result);
        end
        if (cycles != DATA_WIDTH) begin
          test_failed = 1;
          $display("[%0t] error: a divide was done %0d clocks after run went high, expected %0d", $time, cycles, DATA_WIDTH);
        end
      end
      @(negedge clk); // the retiring clock
      run = 0;
      @(negedge clk);
    end
  endtask

  initial begin
    test_failed = 0;
    run = 0;
    rst_n = 0;
    #(22);
    rst_n = 1;
    @(negedge clk);

    check_div(ALU_DIV, 32'd20, 32'd3, 32'd6);
    check_div(ALU_DIV, -32'sd20, 32'd3, -32'sd6); // rounds toward zero
    check_div(ALU_DIV, 32'd20, -32'sd3, -32'sd6);
    check_div(ALU_DIV, -32'sd20, -32'sd3, 32'd6);
    check_div(ALU_DIV, 32'd20, 32'd0, 32'hFFFF_FFFF); // divide by zero
    check_div(ALU_DIV, 32'h8000_0000, 32'hFFFF_FFFF, 32'h8000_0000); // overflow
    check_div(ALU_DIVU, 32'd20, 32'd3, 32'd6);
    check_div(ALU_DIVU, 32'hFFFF_FFFF, 32'd2, 32'h7FFF_FFFF);
    check_div(ALU_DIVU, 32'd20, 32'd0, 32'hFFFF_FFFF); // divide by zero
    check_div(ALU_REM, 32'd20, 32'd3, 32'd2);
    check_div(ALU_REM, -32'sd20, 32'd3, -32'sd2); // sign follows the dividend
    check_div(ALU_REM, 32'd20, -32'sd3, 32'd2);
    check_div(ALU_REM, -32'sd20, -32'sd3, -32'sd2);
    check_div(ALU_REM, 32'd20, 32'd0, 32'd20); // divide by zero returns the dividend
    check_div(ALU_REM, 32'h8000_0000, 32'hFFFF_FFFF, 32'd0); // overflow
    check_div(ALU_REMU, 32'd20, 32'd3, 32'd2);
    check_div(ALU_REMU, 32'hFFFF_FFFF, 32'd16, 32'd15);
    check_div(ALU_REMU, 32'd7, 32'd0, 32'd7); // divide by zero returns the dividend

    // two divides back to back: run stays high across the retire, done must drop and come again
    alu_op = ALU_DIVU; a = 32'd100; b = 32'd7; run = 1;
    @(negedge clk);
    while (!done) @(negedge clk);
    if (result !== 32'd14) begin test_failed = 1; $display("error: first of two back to back divides got 0x%08x", result); end
    @(negedge clk); // the retiring clock has passed
    if (done) begin test_failed = 1; $display("error: done still high after the instruction retired"); end
    cycles = 0;
    while (!done && cycles < 100) begin @(negedge clk); cycles = cycles + 1; end
    if (!done || result !== 32'd14) begin test_failed = 1; $display("error: second back to back divide: done=%0d result=0x%08x", done, result); end
    run = 0;

    finish;
  end

endmodule
