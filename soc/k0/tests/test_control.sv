`timescale 1ns/1ps

// runs a short hand-assembled program on the whole core and checks the architectural result.
// broader instruction coverage comes from the riscv-tests suite, see ./riscv/run.sh
module test_control;

  localparam real CLK_PERIOD = 10.0; // 100 MHz clock
  localparam real CLK_HALF_PERIOD = CLK_PERIOD / 2.0;
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
  reg clk;
  reg rst_n;

  // memory port, backed by a ram
  wire [1:0] mem_error;
  wire mem_read;
  wire mem_write;
  wire [1:0] mem_access_type;
  wire [31:0] mem_addr;
  wire [31:0] mem_data_out;
  wire [31:0] mem_data_in;

  control #(
    .IMEM_INIT("") // the program is written below
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

  cache #(
    .CACHE_SIZE(64)
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

  // clock
  initial begin
    clk = 0;
    forever begin
      #(CLK_HALF_PERIOD) clk = !clk;
    end
  end

  // reset, released before the first clock edge so the memories keep what is written below
  initial begin
    rst_n = 0;
    #2;
    rst_n = 1;
  end

  task expect_reg(input integer index, input [31:0] expected);
    begin
      if (dut.regfile_inst.regs[index] !== expected) begin
        test_failed = 1;
        $display("[%0t] error: x%0d expected=0x%08x, got=0x%08x", $time, index, expected, dut.regfile_inst.regs[index]);
      end else begin
        $display("[%0t] OK: x%0d=0x%08x", $time, index, expected);
      end
    end
  endtask

  // test cases
  initial begin
    $dumpfile("./tests/results/test_control.vcd");
    $dumpvars(0, dut);
    test_failed = 0;

    #1;
    dut.cache_inst.mem[0]  = 32'h00500093; // addi x1, x0, 5
    dut.cache_inst.mem[1]  = 32'h00700113; // addi x2, x0, 7
    dut.cache_inst.mem[2]  = 32'h002081b3; // add  x3, x1, x2
    dut.cache_inst.mem[3]  = 32'h00302023; // sw   x3, 0(x0)
    dut.cache_inst.mem[4]  = 32'h00002203; // lw   x4, 0(x0)
    dut.cache_inst.mem[5]  = 32'h00418463; // beq  x3, x4, +8  (taken, skips the next instruction)
    dut.cache_inst.mem[6]  = 32'h00100293; // addi x5, x0, 1   (must not execute)
    dut.cache_inst.mem[7]  = 32'h00900313; // addi x6, x0, 9
    dut.cache_inst.mem[8]  = 32'h022083b3; // mul  x7, x1, x2
    dut.cache_inst.mem[9]  = 32'h0211c433; // div  x8, x3, x1
    dut.cache_inst.mem[10] = 32'h0211e4b3; // rem  x9, x3, x1
    dut.cache_inst.mem[11] = 32'h0000006f; // jal  x0, 0       (spin)

    repeat (30) @(negedge clk);

    expect_reg(1, 32'd5);
    expect_reg(2, 32'd7);
    expect_reg(3, 32'd12);
    expect_reg(4, 32'd12); // read back what was stored
    expect_reg(5, 32'd0);  // skipped by the taken branch
    expect_reg(6, 32'd9);
    expect_reg(7, 32'd35); // mul 5*7
    expect_reg(8, 32'd2);  // div 12/5
    expect_reg(9, 32'd2);  // rem 12%5

    if (ram.mem[0] !== 32'd12) begin
      test_failed = 1;
      $display("[%0t] error: data memory[0] expected=0x0000000c, got=0x%08x", $time, ram.mem[0]);
    end
    if (dut.pc !== 32'h2c) begin
      test_failed = 1;
      $display("[%0t] error: pc expected to spin at 0x2c, got=0x%08x", $time, dut.pc);
    end
    if (dut.csrfile_inst.csr_array[isa_shared::CSR_MCAUSE] !== 32'd0) begin
      test_failed = 1;
      $display("[%0t] error: unexpected trap, mcause=0x%08x", $time, dut.csrfile_inst.csr_array[isa_shared::CSR_MCAUSE]);
    end

    finish;
  end

endmodule
