`timescale 1ns/1ps

module test_alu;

  localparam int DATA_WIDTH = 32;

  // dut io
  reg [DATA_WIDTH-1:0] a;
  reg [DATA_WIDTH-1:0] b;
  reg [2:0] alu_op; // ALU operation code

  wire [DATA_WIDTH-1:0] result;
  wire zero; // zero flag
  wire carry; // carry flag
  wire overflow; // overflow flag

  initial begin
    $dumpfile("./tests/results/test_alu.vcd");
    $dumpvars(0, test_alu);
  end

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

    for (int i = 0; i < 1000; i++) begin
      a = {$random};
      b = {$random};
      alu_op = dut.LW; // Load Word operation

      #1; // wait for result

      if (result !== (a + b)) begin
        $display("[%0t] error: expected result 0x%h, got 0x%h", $time, (a + b), result);
      end else begin
        $display("[%0t] OK: result is 0x%h", $time, result);
      end
    end

    $finish; // End simulation
  end

endmodule
