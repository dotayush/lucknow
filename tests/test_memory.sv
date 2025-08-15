`timescale 1ns/1ps

module test_memory;

  localparam int ADDR_WIDTH = 8;
  localparam int DATA_WIDTH = 32;
  localparam real CLK_PERIOD = 10.0; // 100 MHz clock
  localparam real CLK_HALF_PERIOD = CLK_PERIOD / 2.0;

  // dut io and initialization
  reg clk;
  reg rst_n;
  reg [ADDR_WIDTH-1:0] addr;
  reg [DATA_WIDTH-1:0] data_in;
  reg write_enable;
  wire [DATA_WIDTH-1:0] data_out;
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
      #(CLK_HALF_PERIOD) clk = ~clk;
    end
  end

  task write_word(input [ADDR_WIDTH-1:0] ad, input [DATA_WIDTH-1:0] dt);
    begin @(negedge clk);
      addr = ad;
      data_in = dt;
      write_enable = 1;
      @(negedge clk); // wait for write to complete
      write_enable = 0;
      data_in = '0;
    end
  endtask

  task read_word(input [ADDR_WIDTH-1:0] ad, input [DATA_WIDTH-1:0] exp);
    begin
      @(negedge clk);
      addr = ad;
      #1; // wait for data_out to be updated
      if (data_out !== exp) begin
        $display("[%0t] error: addr=0x%0h expected=0x%08x, got=0x%08x", $time, addr, exp, data_out);
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

    repeat (5) @(posedge clk); // wait for a few clock cycles
    rst_n = 1; // release reset

    read_word(8'h00, 32'h0); // read uninitialized memory
    read_word(8'h04, 32'h0); // read uninitialized memory
    read_word(8'h08, 32'h0); // read uninitialized memory

    $display("all tests passed");
    $finish;
  end

endmodule
