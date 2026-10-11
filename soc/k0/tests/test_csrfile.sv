`timescale 1ns/1ps

module test_csrfile;

  localparam real CLK_PERIOD = 10.0; // 100 MHz clock
  localparam real CLK_HALF_PERIOD = CLK_PERIOD / 2.0;
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
  reg clk;
  reg rst_n;
  reg [11:0] csr_addr;
  reg [31:0] csr_wdata;
  wire [31:0] csr_rdata;
  reg [1:0] csr_op;

  reg trap;
  reg trap_interrupt;
  reg [3:0] trap_cause;
  reg [31:0] trap_value;
  reg [31:0] trap_pc;
  reg mret;
  reg [31:0] mcycle_before;
  wire [31:0] trap_vector;
  wire mtvec_vectored;
  wire priv_user;
  wire [31:0] mcounteren;
  reg irq_software;
  reg irq_timer;
  reg irq_external;
  wire irq_pending;
  wire [3:0] irq_code;
  reg [63:0] time_value;
  reg retire;

  csrfile dut (
    .clk(clk),
    .rst_n(rst_n),
    .csr_addr(csr_addr),
    .csr_wdata(csr_wdata),
    .csr_rdata(csr_rdata),
    .csr_op(csr_op),
    .trap(trap),
    .trap_interrupt(trap_interrupt),
    .trap_cause(trap_cause),
    .trap_value(trap_value),
    .trap_pc(trap_pc),
    .mret(mret),
    .trap_vector(trap_vector),
    .mtvec_vectored(mtvec_vectored),
    .priv_user(priv_user),
    .mcounteren(mcounteren),
    .irq_software(irq_software),
    .irq_timer(irq_timer),
    .irq_external(irq_external),
    .irq_pending(irq_pending),
    .irq_code(irq_code),
    .time_value(time_value),
    .retire(retire)
  );

  // write a csr through the instruction interface, then leave the port idle
  task write_csr(input [11:0] addr, input [1:0] op, input [31:0] data);
    begin
      @(negedge clk);
      csr_addr = addr;
      csr_wdata = data;
      csr_op = op;
      @(negedge clk);
      csr_op = CSR_NOP;
    end
  endtask

  task expect_csr(input string what, input [11:0] addr, input [31:0] expected);
    begin
      csr_addr = addr;
      csr_op = CSR_NOP;
      #1;
      if (csr_rdata !== expected) begin
        test_failed = 1;
        $display("[%0t] error: %s expected=0x%08x, got=0x%08x", $time, what, expected, csr_rdata);
      end else begin
        $display("[%0t] OK: %s = 0x%08x", $time, what, csr_rdata);
      end
    end
  endtask

  task expect_irq(input string what, input pending, input [3:0] code);
    begin
      #1;
      if (irq_pending !== pending || (pending && irq_code !== code)) begin
        test_failed = 1;
        $display("[%0t] error: %s expected pending=%0d code=%0d, got pending=%0d code=%0d",
                 $time, what, pending, code, irq_pending, irq_code);
      end else begin
        $display("[%0t] OK: %s (pending=%0d code=%0d)", $time, what, irq_pending, irq_code);
      end
    end
  endtask

  // clock
  initial begin
    clk = 0;
    csr_addr = 0;
    csr_wdata = 0;
    csr_op = 0;
    trap = 0;
    trap_interrupt = 0;
    irq_software = 0;
    irq_timer = 0;
    irq_external = 0;
    time_value = 64'h0123_4567_89AB_CDEF;
    retire = 0;
    trap_cause = 0;
    trap_value = 0;
    trap_pc = 0;
    mret = 0;
    test_failed = 0;
    forever begin
      #(CLK_HALF_PERIOD) clk = !clk;
    end
  end

  // reset
  initial begin
    rst_n = 0;
    #(1 * CLK_PERIOD); // hold reset for 1 clock cycles
    rst_n = 1; // release reset
  end

  // test cases
  initial begin
    $dumpfile("./tests/results/test_csrfile.vcd");
    $dumpvars(0, dut);

    @(posedge rst_n); // wait for reset to be released

    // test read
    @(negedge clk);
    csr_addr = CSR_ISA;
    csr_op = CSR_NOP;
    #1;
    if (csr_rdata !== 32'h40101101) begin
      test_failed = 1;
      $display("[%0t] error: read CSR_MISA failed: expected=0x%08x, got=0x%08x", $time, 32'h40101101, csr_rdata);
    end else begin
      $display("[%0t] OK: read CSR_MISA data=0x%08x", $time, csr_rdata);
    end

    @(negedge clk);
    csr_addr = CSR_MSTATUS;
    csr_op = CSR_NOP;
    #1;
    if (csr_rdata !== 32'h00001800) begin
      test_failed = 1;
      $display("[%0t] error: read CSR_MSTATUS failed: expected=0x%08x, got=0x%08x", $time, 32'h00001800, csr_rdata);
    end else begin
      $display("[%0t] OK: read CSR_MSTATUS data=0x%08x", $time, csr_rdata);
    end

    // test write
    @(negedge clk);
    csr_addr = CSR_MTVEC;
    csr_wdata = 32'h00000010;
    csr_op = CSR_WRITE;
    @(negedge clk); // wait for write to complete
    csr_op = CSR_NOP;
    #1;
    if (csr_rdata !== 32'h00000010) begin
      test_failed = 1;
      $display("[%0t] error: read CSR_MTVEC failed: expected=0x%08x, got=0x%08x", $time, 32'h00000010, csr_rdata);
    end else begin
      $display("[%0t] OK: read CSR_MTVEC data=0x%08x", $time, csr_rdata);
    end
    // test set
    @(negedge clk);
    csr_addr = CSR_MTVEC;
    csr_wdata = 32'h00000003;
    csr_op = CSR_SET;
    @(negedge clk); // wait for write to complete
    csr_op = CSR_NOP;
    #1;
    if (csr_rdata !== 32'h00000011) begin // bit 1 (the upper mode bit) is hardwired to 0
      test_failed = 1;
      $display("[%0t] error: read CSR_MTVEC failed: expected=0x%08x, got=0x%08x", $time, 32'h00000011, csr_rdata);
    end else begin
      $display("[%0t] OK: read CSR_MTVEC data=0x%08x", $time, csr_rdata);
    end
    // test clear
    @(negedge clk);
    csr_addr = CSR_MTVEC;
    csr_wdata = 32'h00000002;
    csr_op = CSR_CLEAR;
    @(negedge clk); // wait for write to complete
    csr_op = CSR_NOP;
    #1;
    if (csr_rdata !== 32'h00000011) begin
      test_failed = 1;
      $display("[%0t] error: read CSR_MTVEC failed: expected=0x%08x, got=0x%08x", $time, 32'h00000011, csr_rdata);
    end else begin
      $display("[%0t] OK: read CSR_MTVEC data=0x%08x", $time, csr_rdata);
    end

    // test trap
    @(negedge clk);
    trap = 1;
    trap_cause = TRAP_ECALL_M;
    trap_value = 32'hDEADBEEF;
    trap_pc = 32'h00000020;
    @(negedge clk); // wait for trap to be handled
    trap = 0;
    #1;
    if (trap_vector !== 32'h00000010) begin // mtvec = 0x11, low two bits are masked
      test_failed = 1;
      $display("[%0t] error: trap_vector expected=0x%08x, got=0x%08x", $time, 32'h00000010, trap_vector);
    end else begin
      $display("[%0t] OK: trap_vector=0x%08x", $time, trap_vector);
    end
    @(negedge clk);
    csr_addr = CSR_MEPC;
    csr_op = CSR_NOP;
    #1;
    if (csr_rdata !== 32'h00000020) begin
      test_failed = 1;
      $display("[%0t] error: read CSR_MEPC failed: expected=0x%08x, got=0x%08x", $time, 32'h00000020, csr_rdata);
    end else begin
      $display("[%0t] OK: read CSR_MEPC data=0x%08x", $time, csr_rdata);
    end
    @(negedge clk);
    csr_addr = CSR_MCAUSE;
    csr_op = CSR_NOP;
    #1;
    if (csr_rdata !== 32'h0000000b) begin
      test_failed = 1;
      $display("[%0t] error: read CSR_MCAUSE failed: expected=0x%08x, got=0x%08x", $time, 32'h0000000b, csr_rdata);
    end else begin
      $display("[%0t] OK: read CSR_MCAUSE data=0x%08x", $time, csr_rdata);
    end
    @(negedge clk);
    csr_addr = CSR_MTVAL;
    csr_op = CSR_NOP;
    #1;
    if (csr_rdata !== 32'hDEADBEEF) begin
      test_failed = 1;
      $display("[%0t] error: read CSR_MTVAL failed: expected=0x%08x, got=0x%08x", $time, 32'hDEADBEEF, csr_rdata);
    end else begin
      $display("[%0t] OK: read CSR_MTVAL data=0x%08x", $time, csr_rdata);
    end
    @(negedge clk);
    csr_addr = CSR_MSTATUS;
    csr_op = CSR_NOP;
    #1;
    if (csr_rdata !== 32'h00001800) begin // MPIE = 0 since MIE was 0 before trap
      test_failed = 1;
      $display("[%0t] error: read CSR_MSTATUS failed: expected=0x%08x, got=0x%08x", $time, 32'h00001800, csr_rdata);
    end else begin
      $display("[%0t] OK: read CSR_MSTATUS data=0x%08x", $time, csr_rdata);
    end
    // trap with MIE = 1 stacks it into MPIE and clears MIE
    @(negedge clk);
    csr_addr = CSR_MSTATUS;
    csr_wdata = 32'h00000008;
    csr_op = CSR_SET;
    @(negedge clk);
    csr_op = CSR_NOP;
    trap = 1;
    trap_cause = TRAP_EBREAK;
    @(negedge clk);
    trap = 0;
    #1;
    if (csr_rdata !== 32'h00001880) begin // MPP = 11, MPIE = 1, MIE = 0
      test_failed = 1;
      $display("[%0t] error: mstatus after trap expected=0x%08x, got=0x%08x", $time, 32'h00001880, csr_rdata);
    end else begin
      $display("[%0t] OK: trap stacked MIE into MPIE, mstatus=0x%08x", $time, csr_rdata);
    end

    // mret unstacks it: MIE = MPIE, MPIE = 1
    @(negedge clk);
    mret = 1;
    @(negedge clk);
    mret = 0;
    #1;
    if (csr_rdata !== 32'h00000088) begin // MPP = user now, the mret itself stayed in machine mode (MPP was 11)
      test_failed = 1;
      $display("[%0t] error: mstatus after mret expected=0x%08x, got=0x%08x", $time, 32'h00000088, csr_rdata);
    end else begin
      $display("[%0t] OK: mret restored MIE, mstatus=0x%08x", $time, csr_rdata);
    end

    // mret with MPIE = 0 leaves interrupts disabled
    @(negedge clk);
    csr_wdata = 32'h00000088;
    csr_op = CSR_CLEAR;
    @(negedge clk);
    csr_op = CSR_NOP;
    mret = 1;
    @(negedge clk);
    mret = 0;
    #1;
    if (csr_rdata !== 32'h00000080) begin // MIE = 0 (copied from MPIE = 0), MPIE = 1, MPP = user
      test_failed = 1;
      $display("[%0t] error: mstatus after second mret expected=0x%08x, got=0x%08x", $time, 32'h00000080, csr_rdata);
    end else begin
      $display("[%0t] OK: mret with MPIE=0 keeps MIE=0, mstatus=0x%08x", $time, csr_rdata);
    end

    // mcycle counts every clock
    @(negedge clk);
    csr_addr = CSR_MCYCLE;
    csr_op = CSR_NOP;
    #1;
    mcycle_before = csr_rdata;
    repeat (4) @(negedge clk);
    #1;
    if (csr_rdata !== mcycle_before + 4) begin
      test_failed = 1;
      $display("[%0t] error: read CSR_MCYCLE failed: expected=0x%08x, got=0x%08x", $time, mcycle_before + 4, csr_rdata);
    end else begin
      $display("[%0t] OK: read CSR_MCYCLE data=0x%08x", $time, csr_rdata);
    end

    // the second mret went to user mode (MPP was 0): a trap brings the hart back to machine mode
    if (priv_user !== 1'b1) begin
      test_failed = 1;
      $display("[%0t] error: mret with MPP = 0 should enter user mode", $time);
    end
    trap = 1;
    trap_cause = TRAP_ILLEGAL_INSTRUCTION;
    @(negedge clk);
    trap = 0;
    #1;
    if (priv_user !== 1'b0) begin
      test_failed = 1;
      $display("[%0t] error: a trap should enter machine mode", $time);
    end
    expect_csr("MPP is the mode the trap came from (user)", CSR_MSTATUS, 32'h0000_0000);

    // mstatus keeps MIE, MPIE and MPP only; MPP is user (00) or machine (11), the supervisor encoding is not supported
    write_csr(CSR_MSTATUS, CSR_WRITE, 32'hFFFF_FFFF);
    expect_csr("mstatus keeps MIE, MPIE and MPP only", CSR_MSTATUS, 32'h0000_1888);
    write_csr(CSR_MSTATUS, CSR_CLEAR, 32'h0000_1800);
    expect_csr("MPP can be cleared (user)", CSR_MSTATUS, 32'h0000_0088);
    write_csr(CSR_MSTATUS, CSR_WRITE, 32'h0);
    expect_csr("mstatus all clear", CSR_MSTATUS, 32'h0000_0000);
    write_csr(CSR_MSTATUS, CSR_WRITE, 32'h0000_0800);
    expect_csr("MPP = supervisor is not legal: reads user", CSR_MSTATUS, 32'h0000_0000);
    write_csr(CSR_MSTATUS, CSR_WRITE, 32'h0);

    // ---- interrupts ----
    // mstatus.MIE = 0 from the last mret: nothing is taken, but mip still shows what is pending
    write_csr(CSR_MIE, CSR_WRITE, 32'hFFFF_FFFF);
    expect_csr("mie keeps only the implemented bits", CSR_MIE, 32'h0000_0888);
    irq_timer = 1;
    expect_csr("mip shows the timer", CSR_MIP, 32'h0000_0080);
    expect_irq("MIE clear blocks the interrupt", 0, 0);
    write_csr(CSR_MSTATUS, CSR_SET, 32'h8);
    expect_irq("timer interrupt", 1, 4'd7);
    irq_software = 1;
    expect_csr("mip shows both", CSR_MIP, 32'h0000_0088);
    expect_irq("software wins over timer", 1, 4'd3);
    write_csr(CSR_MIE, CSR_CLEAR, 32'h8);
    expect_irq("a disabled interrupt is not taken", 1, 4'd7);
    write_csr(CSR_MIE, CSR_CLEAR, 32'h80);
    expect_irq("nothing enabled", 0, 0);
    write_csr(CSR_MIE, CSR_SET, 32'h88);
    irq_software = 0;
    irq_timer = 0;
    irq_external = 0;
    expect_irq("nothing pending", 0, 0);
    write_csr(CSR_MIP, CSR_SET, 32'h88); // mip cannot be written from software
    expect_csr("mip ignores writes", CSR_MIP, 32'h0);

    // the external interrupt (plic meip): mip bit 11, enabled by mie bit 11, wins over the others
    write_csr(CSR_MIE, CSR_CLEAR, 32'h800);
    irq_external = 1;
    expect_csr("mip shows the external interrupt", CSR_MIP, 32'h0000_0800);
    expect_irq("MEIE clear: not taken", 0, 0);
    write_csr(CSR_MIE, CSR_SET, 32'h800);
    expect_irq("external interrupt", 1, 4'd11);
    irq_software = 1;
    irq_timer = 1;
    expect_csr("mip shows all three", CSR_MIP, 32'h0000_0888);
    expect_irq("external wins over software and timer", 1, 4'd11);
    irq_external = 0;
    expect_irq("software next", 1, 4'd3);
    irq_software = 0;
    irq_timer = 0;
    expect_irq("nothing pending again", 0, 0);

    // an interrupt trap records the interrupt bit in mcause
    @(negedge clk);
    trap = 1;
    trap_interrupt = 1;
    trap_cause = 4'd7;
    trap_pc = 32'h0000_0040;
    @(negedge clk);
    trap = 0;
    trap_interrupt = 0;
    expect_csr("mcause of a timer interrupt", CSR_MCAUSE, 32'h8000_0007);
    expect_csr("mepc of an interrupt", CSR_MEPC, 32'h0000_0040);

    // mtvec mode: only 0 (direct) and 1 (vectored)
    write_csr(CSR_MTVEC, CSR_WRITE, 32'h0000_0103);
    expect_csr("mtvec mode bit 1 is not writable", CSR_MTVEC, 32'h0000_0101);
    #1;
    if (mtvec_vectored !== 1'b1 || trap_vector !== 32'h0000_0100) begin
      test_failed = 1;
      $display("[%0t] error: vectored mtvec: vectored=%0d vector=0x%08x", $time, mtvec_vectored, trap_vector);
    end
    write_csr(CSR_MTVEC, CSR_WRITE, 32'h0000_0100);
    #1;
    if (mtvec_vectored !== 1'b0) begin
      test_failed = 1;
      $display("[%0t] error: direct mtvec reported as vectored", $time);
    end

    // ---- counters ----
    expect_csr("time", CSR_TIME, 32'h89AB_CDEF);
    expect_csr("timeh", CSR_TIMEH, 32'h0123_4567);

    write_csr(CSR_MINSTRET, CSR_WRITE, 32'h0);
    write_csr(CSR_MINSTRETH, CSR_WRITE, 32'h0);
    repeat (2) @(negedge clk);
    expect_csr("minstret does not count without retire", CSR_MINSTRET, 32'h0);
    retire = 1;
    repeat (3) @(negedge clk);
    retire = 0;
    expect_csr("minstret counts retired instructions", CSR_MINSTRET, 32'd3);
    expect_csr("instret is a read only alias", CSR_INSTRET, 32'd3);
    write_csr(CSR_INSTRET, CSR_WRITE, 32'd99);
    expect_csr("instret ignores writes", CSR_INSTRET, 32'd3);

    // the low half carries into the high half
    write_csr(CSR_MINSTRET, CSR_WRITE, 32'hFFFF_FFFF);
    retire = 1;
    @(negedge clk);
    retire = 0;
    expect_csr("minstret wraps", CSR_MINSTRET, 32'h0);
    expect_csr("minstreth carries", CSR_MINSTRETH, 32'h1);
    write_csr(CSR_MCYCLE, CSR_WRITE, 32'hFFFF_FFFE);
    repeat (3) @(negedge clk);
    expect_csr("mcycleh carries", CSR_MCYCLEH, 32'h1);
    expect_csr("cycleh is an alias", CSR_CYCLEH, 32'h1);

    // writing a half drops that cycle's increment, so a pending carry can't leak into the other half
    write_csr(CSR_MINSTRET, CSR_WRITE, 32'hFFFF_FFFF);
    @(negedge clk);
    csr_addr = CSR_MINSTRETH;
    csr_wdata = 32'hFFFF_FFFF;
    csr_op = CSR_WRITE;
    retire = 1; // the csrw itself retires in the cycle it writes
    @(negedge clk);
    csr_op = CSR_NOP;
    retire = 0;
    expect_csr("minstret after a minstreth write", CSR_MINSTRET, 32'hFFFF_FFFF);
    expect_csr("minstreth after its own write", CSR_MINSTRETH, 32'hFFFF_FFFF);

    // ---- user mode ----
    // machine interrupts are always enabled there, whatever mstatus.MIE says
    write_csr(CSR_MSTATUS, CSR_WRITE, 32'h0); // MIE = 0, MPP = user
    write_csr(CSR_MIE, CSR_WRITE, 32'h80);
    irq_software = 0;
    irq_external = 0;
    irq_timer = 1;
    expect_irq("machine mode, MIE clear: blocked", 0, 0);
    mret = 1;
    @(negedge clk);
    mret = 0;
    expect_irq("user mode, MIE clear: taken", 1, 7);
    trap = 1;
    trap_interrupt = 1;
    trap_cause = 4'd7;
    @(negedge clk);
    trap = 0;
    trap_interrupt = 0;
    expect_irq("back in machine mode: MIE was cleared by the trap", 0, 0);
    expect_csr("trap from user mode: MPP = user", CSR_MSTATUS, 32'h0000_0000);
    irq_timer = 0;

    // Finish the test
    repeat (5) @(posedge clk);
    finish;
  end
endmodule
