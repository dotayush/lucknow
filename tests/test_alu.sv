`timescale 1ns/1ps
import isa_shared::*;

module test_alu;

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

  // dut io
  reg [DATA_WIDTH-1:0] a;
  reg [DATA_WIDTH-1:0] b;
  alu_ops_e alu_op; // ALU operation code

  wire [DATA_WIDTH-1:0] result;
  wire zero; // zero flag
  wire carry; // carry flag
  wire overflow; // overflow flag

  // dut instantiation
  alu #(
    .DATA_WIDTH(DATA_WIDTH)
  ) dut (
    .a(a),
    .b(b),
    .alu_op(alu_op),
    .result(result),
    .zero(zero),
    .carry(carry),
    .overflow(overflow)
  );

  // test cases
  initial begin
    $dumpfile("./tests/results/test_alu.vcd");
    $dumpvars(0, test_alu);

    repeat (1000) begin
      a = {$random};
      b = {$random};
      alu_op = ALU_ADD; // addition operation

      #1; // wait for result

      if (result !== (a + b)) begin
        test_failed = 1;
        $display("[%0t] error: expected result 0x%h, got 0x%h", $time, (a + b), result);
      end else begin
        $display("[%0t] OK: result is 0x%h", $time, result);
      end
    end

    finish; // End simulation
  end

endmodule
