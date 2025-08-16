`timescale 1ns/1ps

module test_signext;

  localparam int DATA_WIDTH = 32;

  // dut io
  reg [24:0] instruction;
  reg [2:0] alu_op;
  wire [DATA_WIDTH-1:0] sign_extended_data;

  initial begin
    $dumpfile("./tests/results/test_signext.vcd");
    $dumpvars(0, test_signext);
  end

  // dut instantiation
  signext #(
    .DATA_WIDTH(DATA_WIDTH)
  ) dut (
    .instruction(instruction),
    .alu_op(alu_op),
    .sign_extended_data(sign_extended_data)
  );

  // test cases
  initial begin
    alu_op = dut.LW;

    instruction = 25'b0_0000_0000_0000_0000_0000_0000; // [24:13] = 0x000 (zero immediate)
    #1;
    if (sign_extended_data !== 32'h00000000)
      $display("[%0t] ERROR: expected 0x%h, got 0x%h", $time, 32'h00000000, sign_extended_data);
    else
      $display("[%0t] OK: 0x%h", $time, sign_extended_data);

    instruction = 25'b1_1111_1111_1111_1111_1111_1111; // [24:13] = 0xFFF (negative -1)
    #1;
    if (sign_extended_data !== 32'hFFFFFFFF)
      $display("[%0t] ERROR: expected 0x%h, got 0x%h", $time, 32'hFFFFFFFF, sign_extended_data);
    else
      $display("[%0t] OK: 0x%h", $time, sign_extended_data);

    instruction = 25'b0_1111_1111_1110_0000_0000_0000; // [24:13] = 0x7FF (max positive 2047)
    #1;
    if (sign_extended_data !== 32'h000007FF)
      $display("[%0t] ERROR: expected 0x%h, got 0x%h", $time, 32'h000007FF, sign_extended_data);
    else
      $display("[%0t] OK: 0x%h", $time, sign_extended_data);

    instruction = 25'b1_0000_0000_0000_0000_0000_0000; // [24:13] = 0x800 (min negative -2048)
    #1;
    if (sign_extended_data !== 32'hFFFFF800)
      $display("[%0t] ERROR: expected 0x%h, got 0x%h", $time, 32'hFFFFF800, sign_extended_data);
    else
      $display("[%0t] OK: 0x%h", $time, sign_extended_data);

    instruction = 25'b1_1110_0000_0000_0000_0000_0000; // [24:13] = 0xF00 (mid negative -4096)
    #1;
    // 1111_0000_0000
    if (sign_extended_data !== 32'hFFFFFF00)
      $display("[%0t] ERROR: expected 0x%h, got 0x%h", $time, 32'hFFFFFF00, sign_extended_data);
    else
      $display("[%0t] OK: 0x%h", $time, sign_extended_data);

    $finish; // End simulation
  end

endmodule
