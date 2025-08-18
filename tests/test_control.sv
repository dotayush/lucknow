`timescale 1ns/1ps

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

  control dut (
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

  // reset
  initial begin
    rst_n = 0;
    #(2 * CLK_PERIOD); // hold reset for 2 clock cycles
    rst_n = 1; // release reset
  end

  // test cases
  initial begin
    $dumpfile("./tests/results/test_control.vcd");
    $dumpvars(0, dut);

    @(posedge rst_n); // wait for reset to be released
    repeat (64) @(posedge clk);

    // Finish the test
    finish;
  end

endmodule
