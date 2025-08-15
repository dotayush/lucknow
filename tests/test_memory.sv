`timescale 1ns/1ps

module test_memory;

  localparam int ADDR_WIDTH = 8;
  localparam int DATA_WIDTH = 32;
  localparam real CLK_PERIOD = 10.0; // 100 MHz clock
  localparam real CLK_HALF_PERIOD = CLK_PERIOD / 2.0;

  // dut io
  reg clk;
  reg rst_n;
  reg [ADDR_WIDTH-1:0] addr;
  reg [DATA_WIDTH-1:0] data_in;
  reg write_enable;
  wire [DATA_WIDTH-1:0] data_out;

  initial begin
    $dumpfile("waves.vcd");
    $dumpvars(0, test_memory);
  end

  // dut instantiation
  memory #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .addr(addr),
    .data_in(data_in),
    .write_enable(write_enable),
    .data_out(data_out)
  );

  // clock
  initial begin
    clk = 0;
    forever begin
      #(CLK_HALF_PERIOD) clk = !clk;
    end
  end

  task write_word(input [ADDR_WIDTH-1:0] wad, input [DATA_WIDTH-1:0] wdt);
    begin
      @(negedge clk);
      addr = wad;
      data_in = wdt;
      write_enable = 1;
      @(negedge clk); // wait for write to complete
      write_enable = 0;
      data_in = '0;
    end
  endtask

  task read_word(input [ADDR_WIDTH-1:0] rad, input [DATA_WIDTH-1:0] rexp);
    begin
      @(negedge clk);
      addr = rad;
      #1; // wait for data_out to be updated
      if (data_out !== rexp) begin
        $display("[%0t] error: addr=0x%0h expected=0x%08x, got=0x%08x", $time, addr, rexp, data_out);
      end else begin
        $display("[%0t] OK: addr=0x%0h data=0x%08x", $time, addr, data_out);
      end
    end
  endtask

  initial begin
    addr = '0;
    data_in = '0;
    write_enable = 0;

    rst_n = 0; // pull reset low
    repeat (2) @(posedge clk); // @ second posedge clk
    rst_n = 1; // release reset
    @(posedge clk);

    read_word(8'h04, 32'h0); // read uninitialized memory
    read_word(8'h00, 32'h0); // read uninitialized memory
    read_word(8'h08, 32'h0); // read uninitialized memory


    write_word(8'h04, 32'hcafebabe); // write to address 0x04
    read_word(8'h04, 32'hcafebabe); // read back the value

    write_word(8'h00, 32'hdeadbeef); // write to address 0x00
    read_word(8'h00, 32'hdeadbeef); // read back the value


    write_word(8'h08, 32'h12345678); // write to address 0x08
    read_word(8'h08, 32'h12345678); // read back the value

    write_word(8'h02, 32'h11111111); // write to address 0x02 (should not write, misaligned)
    read_word(8'h00, 32'hdeadbeef); // read back the value (should be unchanged)

    write_word(8'h04, 32'h22222222); // write to address 0x04 (should write)
    read_word(8'h04, 32'h22222222); // read back the value

    repeat (10) begin
      reg [ADDR_WIDTH-1:0] rs;
      reg [DATA_WIDTH-1:0] rd;

      rs = {$random} & !(8'h03);
      rd = {$random};
      write_word(rs, rd); // write random data to random address
      read_word(rs, rd); // read back the value
    end

    repeat (2) @(posedge clk); // wait for clock edges to capture the last event.
    $display("all tests passed");
    $finish;
  end

endmodule
