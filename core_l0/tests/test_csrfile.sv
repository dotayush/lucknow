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
  reg [3:0] trap_cause;
  reg [31:0] trap_value;
  reg [31:0] trap_pc;
  wire trap_handled;
  wire [31:0] trap_target_pc;

  csrfile dut (
    .clk(clk),
    .rst_n(rst_n),
    .csr_addr(csr_addr),
    .csr_wdata(csr_wdata),
    .csr_rdata(csr_rdata),
    .csr_op(csr_op),
    .trap(trap),
    .trap_cause(trap_cause),
    .trap_value(trap_value),
    .trap_pc(trap_pc),
    .trap_handled(trap_handled),
    .trap_target_pc(trap_target_pc)
  );

  // clock
  initial begin
    clk = 0;
    csr_addr = 0;
    csr_wdata = 0;
    csr_op = 0;
    trap = 0;
    trap_cause = 0;
    trap_value = 0;
    trap_pc = 0;
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
    if (csr_rdata !== 32'h40000100) begin
      test_failed = 1;
      $display("[%0t] error: read CSR_MISA failed: expected=0x%08x, got=0x%08x", $time, 32'h40000100, csr_rdata);
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
    if (csr_rdata !== 32'h00000013) begin
      test_failed = 1;
      $display("[%0t] error: read CSR_MTVEC failed: expected=0x%08x, got=0x%08x", $time, 32'h00000013, csr_rdata);
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
    if (!trap_handled) begin
      test_failed = 1;
      $display("[%0t] error: trap not handled", $time);
    end else begin
      $display("[%0t] OK: trap handled, target_pc=0x%08x", $time, trap_target_pc);
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
    if (csr_rdata !== 32'h00000003) begin
      test_failed = 1;
      $display("[%0t] error: read CSR_MCAUSE failed: expected=0x%08x, got=0x%08x", $time, 32'h00000003, csr_rdata);
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
      $display("[%0t] error: read CSR_MSTATUS failed: expected=0x%08x, got=0x%08x", $time, 32'h00001880, csr_rdata);
    end else begin
      $display("[%0t] OK: read CSR_MSTATUS data=0x%08x", $time, csr_rdata);
    end
    @(negedge clk);
    csr_addr = CSR_MCYCLE;
    csr_op = CSR_NOP;
    #1;
    if (csr_rdata !== 32'h0000000f) begin // 15 cycles have passed since reset
      test_failed = 1;
      $display("[%0t] error: read CSR_MCYCLE failed: expected=0x%08x, got=0x%08x", $time, 32'h0000000A, csr_rdata);
    end else begin
      $display("[%0t] OK: read CSR_MCYCLE data=0x%08x", $time, csr_rdata);
    end

    // Finish the test
    repeat (5) @(posedge clk);
    finish;
  end
endmodule
