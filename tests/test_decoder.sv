`timescale 1ns/1ps

module test_decoder;

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
  //
  reg [DATA_WIDTH-1:0] instruction;
  wire [2:0] alu_op;
  wire [2:0] imm_op;
  wire mem_write;
  wire reg_write;
  wire mem_read;
  wire [$clog2(DATA_WIDTH)-1:0] rs1;
  wire [$clog2(DATA_WIDTH)-1:0] rs2;
  wire [$clog2(DATA_WIDTH)-1:0] rd;

  // dut instantiation
  decoder #(
    .DATA_WIDTH(DATA_WIDTH)
  ) dut (
    .instruction(instruction),
    .alu_op(alu_op),
    .imm_op(imm_op),
    .mem_write(mem_write),
    .reg_write(reg_write),
    .mem_read(mem_read),
    .rs1(rs1),
    .rs2(rs2),
    .rd(rd)
  );

  initial begin
    $dumpfile("./tests/results/test_decoder.vcd");
    $dumpvars(0, test_decoder);

    // case 1: lw instruction (lw)
    instruction = 32'b000000000000_10101_010_10101_0000011; // lw x21, 0(x21)
    #1; // wait for dut to process
    if (alu_op !== 3'b000 || imm_op !== 3'b000 || mem_write !== 0 || reg_write !== 1 || mem_read !==1 || rs1 !== 5'd21 || rs2 !== 5'd0 || rd !== 5'd21) begin
      test_failed = 1;
      $display("[%0t] error: expected alu_op=000 (got %b), imm_op=000 (got %b), mem_write=0 (got %b), reg_write=1 (got %b), mem_read=1 (got %b), rs1=21 (got %d), rs2=0 (got %d), rd=21 (got %d)",
               $time, alu_op, imm_op, mem_write, reg_write, mem_read, rs1, rs2, rd);
    end else begin
      $display("[%0t] OK: memory load instruction decoded correctly", $time);
    end

    // case 2: invalid instruction (should not match any case)
    instruction = 32'b111111111111_11111_111_11111_1111111; // Invalid instruction
    #1; // wait for dut to process
    if (alu_op !== 3'b111 || imm_op !== 3'b111 || mem_write !== 0 || reg_write !== 0 || mem_read !==0 || rs1 !== 5'd0 || rs2 !== 5'd0 || rd !== 5'd0) begin
      test_failed = 1;
      $display("[%0t] error: expected alu_op=111 (got %b), imm_op=111 (got %b), mem_write=0 (got %b), reg_write=0 (got %b), mem_read=0 (got %b), rs1=0 (got %d), rs2=0 (got %d), rd=0 (got %d)",
               $time, alu_op, imm_op, mem_write, reg_write, mem_read, rs1, rs2, rd);
    end else begin
      $display("[%0t] OK: invalid instruction handled correctly", $time);
    end

    // case 3: 0 instruction (should not match any case)
    instruction = 32'b000000000000_00000_000_00000_0000000; // 0 instruction
    #1; // wait for dut to process
    if (alu_op !== 3'b111 || imm_op !== 3'b111 || mem_write !== 0 || reg_write !== 0 || mem_read !==0 || rs1 !== 5'd0 || rs2 !== 5'd0 || rd !== 5'd0) begin
      test_failed = 1;
      $display("[%0t] error: expected alu_op=111 (got %b), imm_op=111 (got %b), mem_write=0 (got %b), reg_write=0 (got %b), mem_read=0 (got %b), rs1=0 (got %d), rs2=0 (got %d), rd=0 (got %d)",
               $time, alu_op, imm_op, mem_write, reg_write, mem_read, rs1, rs2, rd);
    end else begin
      $display("[%0t] OK: zero instruction handled correctly", $time);
    end

    finish;
  end


endmodule
