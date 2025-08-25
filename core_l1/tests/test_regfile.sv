`timescale 1ns/1ps

module test_regfile;

  localparam int DATA_WIDTH = 32;
  localparam int REG_BUS_WIDTH = $clog2(DATA_WIDTH);
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
  reg [REG_BUS_WIDTH-1:0] rs1;
  reg [REG_BUS_WIDTH-1:0] rs2;
  wire [DATA_WIDTH-1:0] rs1_data;
  wire [DATA_WIDTH-1:0] rs2_data;
  reg reg_write;
  reg [REG_BUS_WIDTH-1:0] rd;
  reg [DATA_WIDTH-1:0] rd_data;

  // dut instantiation
  regfile #(
    .DATA_WIDTH(DATA_WIDTH)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .rs1(rs1),
    .rs2(rs2),
    .rs1_data(rs1_data),
    .rs2_data(rs2_data),
    .reg_write(reg_write),
    .rd(rd),
    .rd_data(rd_data)
  );

  // clock
  initial begin
    clk = 0;
    forever begin
      #(CLK_HALF_PERIOD) clk = !clk;
    end
  end

  task write_reg(input [REG_BUS_WIDTH-1:0] wad, input [DATA_WIDTH-1:0] wdt);
    begin
      @(negedge clk);
      rd = wad;
      rd_data = wdt;
      reg_write = 1;
      @(negedge clk); // wait for write to complete
      reg_write = 0;
      rd_data = '0;
    end
  endtask

  task read_reg(input [REG_BUS_WIDTH-1:0] rad, input [DATA_WIDTH-1:0] rexp, input [1:0] rg_sel = 2'b00);
    begin
      @(negedge clk);
      if (rg_sel == 2'b00) begin
        rs1 = rad; // read from rs1
      end else if (rg_sel == 2'b01) begin
        rs2 = rad; // read from rs2
      end else begin
        test_failed = 1;
        $display("[%0t] error: invalid register select 0x%0h", $time, rg_sel);
      end
      #1; // wait for selected register data to be updated
      if (rs1_data !== rexp) begin
        test_failed = 1;
        $display("[%0t] error: read from %s failed: expected=0x%08x, got=0x%08x", $time, (rg_sel == 2'b00 ? "rs1" : "rs2"), rexp, rs1_data);
      end else begin
        $display("[%0t] OK: read from %s addr=0x%0h data=0x%08x", $time, (rg_sel == 2'b00 ? "rs1" : "rs2"), rad, rs1_data);
      end
    end
  endtask

  initial begin
    $dumpfile("./tests/results/test_regfile.vcd");
    $dumpvars(0, test_regfile);

    rs1 = '0;
    rs2 = '0;
    reg_write = 0;
    rd = '0;
    rd_data = '0;

    rst_n = 0; // pull reset low
    repeat (2) @(posedge clk); // @ second posedge clk
    rst_n = 1; // release reset
    @(posedge clk);

    // all registers should be initialized to zero
    for (int i = 0; i < 32; i = i + 1) begin
      read_reg(i, 0, 2'b00); // read uninitialized registers
      read_reg(i, 0, 2'b01); // read uninitialized registers
    end

    #1; // wait for data to stabilize

    repeat (10) begin
      reg [REG_BUS_WIDTH-1:0] rr;
      reg [DATA_WIDTH-1:0] rd;

      rr = $urandom_range(0, 31); // random register from x0
      rd = {$random}; // random data

      write_reg(rr, rd);
      if (rr == 0) begin
        read_reg(rr, 0, 2'b00); // x0 should always read as zero
      end else begin
        read_reg(rr, rd, 2'b00); // read from rs1
      end
    end

    repeat (2) @(posedge clk); // wait for clock edges to capture the last event.
    finish; // end simulation
  end

endmodule
