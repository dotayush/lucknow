`timescale 1ns/1ps
import isa_shared::*;

module test_signext;

  localparam int DATA_WIDTH = 32;
  reg [DATA_WIDTH-1:0] expected_immediate;
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
  reg [24:0] instruction;
  reg [2:0] imm_op;
  wire [DATA_WIDTH-1:0] sign_extended_data;

  // dut instantiation
  signext #(
    .DATA_WIDTH(DATA_WIDTH)
  ) dut (
    .instruction(instruction),
    .imm_op(imm_op),
    .sign_extended_data(sign_extended_data)
  );

  // test cases
  initial begin
    $dumpfile("./tests/results/test_signext.vcd");
    $dumpvars(0, test_signext);

    imm_op = isa_shared::IMM_3120;

    repeat (1000) begin
      instruction = {$random};
      expected_immediate = {{(DATA_WIDTH-12){instruction[24]}}, instruction[24:13]};
      #1; // wait for sign_extended_data to be updated
      if (sign_extended_data !== expected_immediate) begin
        test_failed = 0;
        $display("[%0t] error: expected 0b%b, got 0b%b", $time, expected_immediate, sign_extended_data);
      end else begin
        $display("[%0t] OK: 0b%b", $time, sign_extended_data);
      end
    end

    instruction = 25'b000000000000_10101_010_10101; // [24:13] = 0x000 (zero immediate)
    #1;
    if (sign_extended_data !== 32'h00000000) begin
      test_failed = 1;
      $display("[%0t] error: expected 0x%h, got 0x%h", $time, 32'h00000000, sign_extended_data);
    end else begin
      $display("[%0t] OK: 0x%h", $time, sign_extended_data);
    end

    finish; // End simulation
  end

endmodule
