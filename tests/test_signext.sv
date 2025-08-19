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
  reg [DATA_WIDTH-1:0] unextended_data;
  reg [2:0] sx_op;
  wire [DATA_WIDTH-1:0] sign_extended_data;

  // dut instantiation
  signext #(
    .DATA_WIDTH(DATA_WIDTH)
  ) dut (
    .unextended_data(unextended_data),
    .sx_op(sx_op),
    .sign_extended_data(sign_extended_data)
  );

  // test cases
  initial begin
    $dumpfile("./tests/results/test_signext.vcd");
    $dumpvars(0, test_signext);

    sx_op = isa_shared::SX_1100;
    repeat (10) begin
      unextended_data = {$random};
      expected_immediate = {{(DATA_WIDTH-12){unextended_data[11]}}, unextended_data[11:0]};
      #1; // wait for sign_extended_data to be updated
      if (sign_extended_data !== expected_immediate) begin
        test_failed = 1;
        $display("[%0t] error: expected 0b%b, got 0b%b", $time, expected_immediate, sign_extended_data);
      end else begin
        $display("[%0t] OK: 0b%b", $time, sign_extended_data);
      end
    end

    sx_op = isa_shared::SX_3100;
    repeat (10) begin
      unexpected_data = {$random};
      expected_immediate = unextended_data; // since unextended_data [31:0] = sign_extended_data
      #1; // wait for sign_extended_data to be updated
      if (sign_extended_data !== expected_immediate) begin
        test_failed = 1;
        $display("[%0t] error: expected 0b%b, got 0b%b", $time, expected_immediate, sign_extended_data);
      end else begin
        $display("[%0t] OK: 0b%b", $time, sign_extended_data);
      end

    sx_op = isa_shared::SX_1500;
    repeat (10) begin
      unextended_data = {$random};
      expected_immediate = {{(DATA_WIDTH-12){unextended_data[15]}}, unextended_data[15:0]};
      #1; // wait for sign_extended_data to be updated
      if (sign_extended_data !== expected_immediate) begin
        test_failed = 1;
        $display("[%0t] error: expected 0b%b, got 0b%b", $time, expected_immediate, sign_extended_data);
      end else begin
        $display("[%0t] OK: 0b%b", $time, sign_extended_data);
      end
    end

    finish; // End simulation
  end

endmodule
