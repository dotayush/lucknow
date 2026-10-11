`timescale 1ns/1ps

// runs a short program on the whole soc, once with zero wait states and once with slow
// memories. the architectural result must be identical, only later: this exercises the
// core's stall logic (nothing retires, no store lands twice, no csr is applied twice).
// the program lives in ram, the core gets there through the boot rom.
// broader instruction coverage comes from the riscv-tests suite, see ./riscv/run.sh
module test_control;

  localparam real CLK_PERIOD = 10.0; // 100 MHz clock
  localparam real CLK_HALF_PERIOD = CLK_PERIOD / 2.0;
  localparam [31:0] SPIN_PC = 32'h8000_0048; // the jal x0, 0 at the end of the program
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

  reg clk;
  reg rst_n;

  soc fast (
    .clk(clk),
    .rst_n(rst_n)
  );

  soc #(
    .FETCH_WAIT(2),
    .DATA_WAIT(3)
  ) slow (
    .clk(clk),
    .rst_n(rst_n)
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

  // cycles until the program reaches its final spin
  integer cycle;
  integer fast_done;
  integer slow_done;
  initial begin
    cycle = 0;
    fast_done = -1;
    slow_done = -1;
  end
  always @(posedge clk) if (rst_n) begin
    cycle <= cycle + 1;
    if (fast_done < 0 && fast.core_inst.pc === SPIN_PC) fast_done <= cycle;
    if (slow_done < 0 && slow.core_inst.pc === SPIN_PC) slow_done <= cycle;
  end

  task load_program;
    begin
      fast.bus_inst.ram_inst.mem[0]  = 32'h00500093; // addi x1, x0, 5
      fast.bus_inst.ram_inst.mem[1]  = 32'h00700113; // addi x2, x0, 7
      fast.bus_inst.ram_inst.mem[2]  = 32'h002081b3; // add  x3, x1, x2
      fast.bus_inst.ram_inst.mem[3]  = 32'h80000537; // lui  x10, 0x80000      (ram base)
      fast.bus_inst.ram_inst.mem[4]  = 32'h10352023; // sw   x3, 256(x10)
      fast.bus_inst.ram_inst.mem[5]  = 32'h10052203; // lw   x4, 256(x10)
      fast.bus_inst.ram_inst.mem[6]  = 32'h00418463; // beq  x3, x4, +8        (taken, skips the next instruction)
      fast.bus_inst.ram_inst.mem[7]  = 32'h00100713; // addi x14, x0, 1        (must not execute)
      fast.bus_inst.ram_inst.mem[8]  = 32'h00900313; // addi x6, x0, 9
      fast.bus_inst.ram_inst.mem[9]  = 32'h022083b3; // mul  x7, x1, x2
      fast.bus_inst.ram_inst.mem[10] = 32'h0211c433; // div  x8, x3, x1
      fast.bus_inst.ram_inst.mem[11] = 32'h0211e4b3; // rem  x9, x3, x1
      fast.bus_inst.ram_inst.mem[12] = 32'h3404d5f3; // csrrwi x11, mscratch, 9
      fast.bus_inst.ram_inst.mem[13] = 32'h34002673; // csrrs  x12, mscratch, x0
      fast.bus_inst.ram_inst.mem[14] = 32'h101500a3; // sb   x1, 257(x10)
      fast.bus_inst.ram_inst.mem[15] = 32'h10150683; // lb   x13, 257(x10)
      fast.bus_inst.ram_inst.mem[16] = 32'h00178793; // addi x15, x15, 1       (counts: retiring twice would show)
      fast.bus_inst.ram_inst.mem[17] = 32'h00178793; // addi x15, x15, 1
      fast.bus_inst.ram_inst.mem[18] = 32'h0000006f; // jal  x0, 0             (spin)
      for (int i = 0; i <= 18; i = i + 1) slow.bus_inst.ram_inst.mem[i] = fast.bus_inst.ram_inst.mem[i];
    end
  endtask

  task expect_regs(input string who);
    begin
      check_reg(who, 1, 32'd5);
      check_reg(who, 2, 32'd7);
      check_reg(who, 3, 32'd12);
      check_reg(who, 4, 32'd12); // read back what was stored
      check_reg(who, 5, 32'h8000_0000); // left by the boot rom's jump
      check_reg(who, 14, 32'd0); // skipped by the taken branch
      check_reg(who, 6, 32'd9);
      check_reg(who, 7, 32'd35); // mul 5*7
      check_reg(who, 8, 32'd2);  // div 12/5
      check_reg(who, 9, 32'd2);  // rem 12%5
      check_reg(who, 10, 32'h8000_0000);
      check_reg(who, 11, 32'd0); // old mscratch
      check_reg(who, 12, 32'd9); // new mscratch
      check_reg(who, 13, 32'd5); // lb of the stored byte
      check_reg(who, 15, 32'd2); // each addi retired exactly once, however long it waited
    end
  endtask

  task check_reg(input string who, input integer index, input [31:0] expected);
    reg [31:0] got;
    begin
      got = (who == "fast") ? fast.core_inst.regfile_inst.regs[index] : slow.core_inst.regfile_inst.regs[index];
      if (got !== expected) begin
        test_failed = 1;
        $display("[%0t] error: %s x%0d expected=0x%08x, got=0x%08x", $time, who, index, expected, got);
      end
    end
  endtask

  // test cases
  initial begin
    $dumpfile("./tests/results/test_control.vcd");
    $dumpvars(0, fast);
    test_failed = 0;

    #1;
    load_program();

    repeat (400) @(negedge clk);

    expect_regs("fast");
    expect_regs("slow");

    // the word at ram base + 256: stored 12, then byte 1 replaced by 5
    if (fast.bus_inst.ram_inst.mem[64] !== 32'h0000_050c || slow.bus_inst.ram_inst.mem[64] !== 32'h0000_050c) begin
      test_failed = 1;
      $display("[%0t] error: ram word 64 expected=0x0000050c, fast=0x%08x slow=0x%08x", $time, fast.bus_inst.ram_inst.mem[64], slow.bus_inst.ram_inst.mem[64]);
    end

    // both reached the spin, the slow one later, and neither trapped
    if (fast_done < 0 || slow_done < 0) begin
      test_failed = 1;
      $display("[%0t] error: program didn't finish, fast=%0d slow=%0d", $time, fast_done, slow_done);
    end else if (slow_done <= fast_done) begin
      test_failed = 1;
      $display("[%0t] error: wait states had no effect, fast=%0d slow=%0d cycles", $time, fast_done, slow_done);
    end else begin
      $display("[%0t] OK: fast finished in %0d cycles, slow in %0d", $time, fast_done, slow_done);
    end
    if (fast.core_inst.csrfile_inst.csr_array[isa_shared::CSR_MCAUSE] !== 32'd0 ||
        slow.core_inst.csrfile_inst.csr_array[isa_shared::CSR_MCAUSE] !== 32'd0) begin
      test_failed = 1;
      $display("[%0t] error: unexpected trap", $time);
    end

    finish;
  end

endmodule
