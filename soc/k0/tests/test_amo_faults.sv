`timescale 1ns/1ps

// atomics that fault: misaligned, to the read only rom (the read half works, the write faults)
// and to an unmapped address. every one must trap with the right cause and mtval, leave rd
// alone and not write memory. run on a fast and a slow soc, a fault arrives with ready.
module test_amo_faults;

  localparam real CLK_HALF_PERIOD = 5.0;
  localparam [31:0] RAM_BASE = 32'h8000_0000;
  localparam [31:0] SPIN_PC = 32'h8000_0050;

  reg test_failed;
  task finish;
    begin
      if (test_failed) begin
        $display("Test failed!");
      end else begin
        $display("Test passed!");
      end
      $finish;
    end
  endtask

  reg clk;
  reg rst_n;

  soc fast (.clk(clk), .rst_n(rst_n), .uart_rx(1'b1));
  soc #(.FETCH_WAIT(1), .DATA_WAIT(2)) slow (.clk(clk), .rst_n(rst_n), .uart_rx(1'b1));

  initial begin
    clk = 0;
    forever #(CLK_HALF_PERIOD) clk = !clk;
  end

  initial begin
    rst_n = 0;
    #2;
    rst_n = 1;
  end

  // the program (see the comments for what each faulting instruction is) and the trap handler,
  // which counts, and stores mcause at ram base + 0x200 + 4n and mtval at + 0x240 + 4n
  reg [31:0] program_words [0:20];
  reg [31:0] handler_words [0:10];
  initial begin
    program_words[0]  = 32'h800000b7; // lui   x1, 0x80000
    program_words[1]  = 32'h10008193; // addi  x3, x1, 0x100
    program_words[2]  = 32'h30519073; // csrw  mtvec, x3
    program_words[3]  = 32'h00100113; // addi  x2, x0, 1
    program_words[4]  = 32'h05500293; // addi  x5, x0, 0x55   sentinels
    program_words[5]  = 32'h05500313; // addi  x6, x0, 0x55
    program_words[6]  = 32'h05500393; // addi  x7, x0, 0x55
    program_words[7]  = 32'h05500413; // addi  x8, x0, 0x55
    program_words[8]  = 32'h05500693; // addi  x13, x0, 0x55
    program_words[9]  = 32'h05500793; // addi  x15, x0, 0x55
    program_words[10] = 32'h00208213; // addi  x4, x1, 2      misaligned word address
    program_words[11] = 32'h40000493; // addi  x9, x0, 0x400
    program_words[12] = 32'h000014b7; // lui   x9, 1          x9 = 0x1000, the rom
    program_words[13] = 32'h20000737; // lui   x14, 0x20000   x14 = 0x2000_0000, unmapped
    program_words[14] = 32'h100222af; // lr.w  x5, (x4)       load misaligned
    program_words[15] = 32'h1822232f; // sc.w  x6, x2, (x4)   store/amo misaligned
    program_words[16] = 32'h002223af; // amoadd.w x7, x2, (x4) store/amo misaligned
    program_words[17] = 32'h0024a42f; // amoadd.w x8, x2, (x9) rom: read fine, write faults
    program_words[18] = 32'h082726af; // amoswap.w x13, x2, (x14) unmapped, the read faults
    program_words[19] = 32'h100727af; // lr.w  x15, (x14)     load access fault
    program_words[20] = 32'h0000006f; // jal   x0, 0          spin
    handler_words[0]  = 32'h001a0a13; // addi  x20, x20, 1
    handler_words[1]  = 32'h002a1a93; // slli  x21, x20, 2
    handler_words[2]  = 32'h01508b33; // add   x22, x1, x21
    handler_words[3]  = 32'h34202573; // csrr  x10, mcause
    handler_words[4]  = 32'h20ab2023; // sw    x10, 0x200(x22)
    handler_words[5]  = 32'h343025f3; // csrr  x11, mtval
    handler_words[6]  = 32'h24bb2023; // sw    x11, 0x240(x22)
    handler_words[7]  = 32'h34102673; // csrr  x12, mepc
    handler_words[8]  = 32'h00460613; // addi  x12, x12, 4
    handler_words[9]  = 32'h34161073; // csrw  mepc, x12
    handler_words[10] = 32'h30200073; // mret
  end

  task load_program;
    begin
      for (int i = 0; i <= 20; i = i + 1) begin
        fast.bus_inst.ram_inst.mem[i] = program_words[i];
        slow.bus_inst.ram_inst.mem[i] = program_words[i];
      end
      for (int i = 0; i <= 10; i = i + 1) begin
        fast.bus_inst.ram_inst.mem[64 + i] = handler_words[i];
        slow.bus_inst.ram_inst.mem[64 + i] = handler_words[i];
      end
    end
  endtask

  task expect_word(input string who, input [31:0] got, input [31:0] exp, input string what);
    begin
      if (got !== exp) begin
        test_failed = 1;
        $display("[%0t] error: %s %s expected 0x%08x, got 0x%08x", $time, who, what, exp, got);
      end
    end
  endtask

  reg [31:0] exp_cause [1:6];
  reg [31:0] exp_mtval [1:6];
  integer n;

  initial begin
    $dumpfile("./tests/results/test_amo_faults.vcd");
    $dumpvars(0, fast);
    test_failed = 0;
    exp_cause[1] = 4; exp_mtval[1] = RAM_BASE + 2;   // lr.w misaligned: load address misaligned
    exp_cause[2] = 6; exp_mtval[2] = RAM_BASE + 2;   // sc.w misaligned: store/amo address misaligned, even without reservation
    exp_cause[3] = 6; exp_mtval[3] = RAM_BASE + 2;   // amoadd.w misaligned
    exp_cause[4] = 7; exp_mtval[4] = 32'h0000_1000;  // amoadd.w to the rom: store/amo access fault
    exp_cause[5] = 7; exp_mtval[5] = 32'h2000_0000;  // amoswap.w unmapped
    exp_cause[6] = 5; exp_mtval[6] = 32'h2000_0000;  // lr.w unmapped: load access fault

    #1;
    load_program();
    repeat (500) @(negedge clk);

    if (fast.core_inst.pc !== SPIN_PC || slow.core_inst.pc !== SPIN_PC) begin
      test_failed = 1;
      $display("[%0t] error: program did not reach its spin, fast pc=0x%08x slow pc=0x%08x", $time, fast.core_inst.pc, slow.core_inst.pc);
    end

    expect_word("fast", fast.core_inst.regfile_inst.regs[20], 32'd6, "trap count");
    expect_word("slow", slow.core_inst.regfile_inst.regs[20], 32'd6, "trap count");
    for (n = 1; n <= 6; n = n + 1) begin
      expect_word("fast", fast.bus_inst.ram_inst.mem[128 + n], exp_cause[n], $sformatf("mcause of fault %0d", n));
      expect_word("slow", slow.bus_inst.ram_inst.mem[128 + n], exp_cause[n], $sformatf("mcause of fault %0d", n));
      expect_word("fast", fast.bus_inst.ram_inst.mem[144 + n], exp_mtval[n], $sformatf("mtval of fault %0d", n));
      expect_word("slow", slow.bus_inst.ram_inst.mem[144 + n], exp_mtval[n], $sformatf("mtval of fault %0d", n));
    end

    // rd of a faulting instruction is not written
    for (n = 0; n < 32; n = n + 1) begin
      if (n == 5 || n == 6 || n == 7 || n == 8 || n == 13 || n == 15) begin
        expect_word("fast", fast.core_inst.regfile_inst.regs[n], 32'h55, $sformatf("sentinel x%0d", n));
        expect_word("slow", slow.core_inst.regfile_inst.regs[n], 32'h55, $sformatf("sentinel x%0d", n));
      end
    end

    // the rom is untouched, the read half of the faulting amoadd must not have written back
    expect_word("fast", fast.bus_inst.rom_inst.mem[0], 32'h800002b7, "rom word 0");
    expect_word("slow", slow.bus_inst.rom_inst.mem[0], 32'h800002b7, "rom word 0");

    finish;
  end

endmodule
