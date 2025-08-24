`timescale 1ns/1ps

module test_memory;

  localparam int WORDS = 1024; // 64 words of memory
  localparam int DATA_WIDTH = 32;
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
  reg [DATA_WIDTH-1:0] addr;
  reg [DATA_WIDTH-1:0] data_in;
  reg mem_write;
  reg mem_read;
  reg [1:0] mem_access_type;
  wire [DATA_WIDTH-1:0] data_out;

  // dut instantiation
  memory #(
    .WORDS(WORDS),
    .DATA_WIDTH(DATA_WIDTH)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .addr(addr),
    .data_in(data_in),
    .mem_write(mem_write),
    .mem_read(mem_read),
    .mem_access_type(mem_access_type),
    .data_out(data_out)
  );

  // clock
  initial begin
    clk = 0;
    forever begin
      #(CLK_HALF_PERIOD) clk = !clk;
    end
  end

  task write_word(input [DATA_WIDTH-1:0] wad, input [DATA_WIDTH-1:0] wdt, input [1:0] access_type);
    begin
      @(negedge clk);
      addr = wad;
      data_in = wdt;
      mem_write = 1;
      mem_access_type = access_type;
      @(negedge clk); // wait for write to complete
      mem_write = 0;
      data_in = '0;
    end
  endtask

  task read_word(input [DATA_WIDTH-1:0] rad, input [DATA_WIDTH-1:0] rexp, input [1:0] access_type);
    begin
      @(negedge clk);
      addr = rad;
      mem_read = 1;
      mem_access_type = access_type;
      #1; // wait for data_out to be updated
      if (data_out !== rexp) begin
        test_failed = 1;
        $display("[%0t] read error: addr=0x%0h expected=0x%08x, got=0x%08x, access_type=0x%h", $time, addr, rexp, data_out, access_type);
      end
      mem_read = 0;
      addr = '0; // reset address
    end
  endtask

  initial begin
    $dumpfile("./tests/results/test_memory.vcd");
    $dumpvars(0, test_memory);

    // initial state
    addr = '0;
    data_in = '0;
    mem_write = 0;
    mem_read = 0;
    mem_access_type = WORD_MEM_ACCESS;

    // reset mem
    rst_n = 0; // pull reset low
    repeat (2) @(posedge clk); // @ second posedge clk
    rst_n = 1; // release reset
    @(posedge clk);

    // read reset mem
    read_word(32'h00000010, 32'h0, WORD_MEM_ACCESS);
    read_word(32'h00000000, 32'h0, WORD_MEM_ACCESS);
    read_word(32'h00000008, 32'h0, WORD_MEM_ACCESS);

    repeat (1) @(posedge clk); // rest for two clock cycles (20ns)
    mem_access_type = WORD_MEM_ACCESS; // set access type to WORD_MEM_ACCESS
    repeat (5) begin
      reg [DATA_WIDTH-1:0] rs;
      reg [DATA_WIDTH-1:0] rd;

      rs = {$random};
      rd = {$random};

      write_word(rs, rd, mem_access_type); // write to memory
      read_word(rs, rd, mem_access_type); // read from memory
    end

    mem_access_type = HALF_MEM_ACCESS; // set access type to HALF_MEM_ACCESS
    repeat (5) begin
      reg [DATA_WIDTH-1:0] rs;
      reg [DATA_WIDTH-1:0] rd;
      reg [15:0] half_data;

      rs = {$random};
      half_data = {$random};
      rd = { {(DATA_WIDTH-1-15){1'b0}}, half_data }; // zero-extend to 32 bits

      write_word(rs, rd, mem_access_type); // write to memory
      read_word(rs, rd, mem_access_type); // read from memory
    end

    mem_access_type = BYTE_MEM_ACCESS; // set access type to BYTE_MEM_ACCESS
    repeat (5) begin
      reg [DATA_WIDTH-1:0] rs;
      reg [DATA_WIDTH-1:0] rd;
      reg [7:0] byte_data;

      rs = {$random};
      byte_data = {$random};
      rd = { {(DATA_WIDTH-1-7){1'b0}}, byte_data }; // zero-extend to 32 bits

      write_word(rs, rd, mem_access_type); // write to memory
      read_word(rs, rd, mem_access_type); // read from memory
    end

    repeat (2) @(posedge clk); // wait for clock edges to capture the last event.
    finish;
  end

endmodule
