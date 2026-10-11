`timescale 1ns/1ps

module test_memory;

  localparam int WORDS = 64;
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
  wire [1:0] mem_error;

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
    .data_out(data_out),
    .mem_error(mem_error)
  );

  // a memory that is bigger than its image: the image is loaded, the rest reads as zero
  memory #(
    .WORDS(128),
    .DATA_WIDTH(DATA_WIDTH),
    .MEM_INIT("./memory/test_rom.hex") // 64 words
  ) image_dut (
    .clk(clk),
    .rst_n(rst_n),
    .addr(32'h0),
    .data_in(32'h0),
    .mem_write(1'b0),
    .mem_read(1'b0),
    .mem_access_type(2'b10),
    .data_out(),
    .mem_error()
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

  // access that must be rejected with `exp_err`, leaving memory untouched
  task expect_error(input [DATA_WIDTH-1:0] ead, input [1:0] access_type, input write, input [1:0] exp_err);
    begin
      @(negedge clk);
      addr = ead;
      data_in = 32'hFFFFFFFF;
      mem_access_type = access_type;
      mem_write = write;
      mem_read = !write;
      #1;
      if (mem_error !== exp_err) begin
        test_failed = 1;
        $display("[%0t] error: addr=0x%08x type=%b write=%b expected mem_error=%b, got=%b", $time, ead, access_type, write, exp_err, mem_error);
      end
      if (!write && data_out !== '0) begin
        test_failed = 1;
        $display("[%0t] error: faulting read at 0x%08x returned data 0x%08x", $time, ead, data_out);
      end
      @(negedge clk); // a rejected write must not land
      mem_write = 0;
      mem_read = 0;
      data_in = '0;
    end
  endtask

  initial begin
    test_failed = 0;
    $dumpfile("./tests/results/test_memory.vcd");
    $dumpvars(0, test_memory);

    // initial state
    addr = '0;
    data_in = '0;
    mem_write = 0;
    mem_read = 0;
    mem_access_type = WORD_MEM_ACCESS;

    // reset mem
    rst_n = 0;
    repeat (2) @(posedge clk);
    rst_n = 1;
    @(posedge clk);

    // memory is zero after reset
    read_word(32'h00000000, 32'h0, WORD_MEM_ACCESS);
    read_word(32'h00000010, 32'h0, WORD_MEM_ACCESS);
    read_word((WORDS-1)*4, 32'h0, WORD_MEM_ACCESS);

    // word write/read, including first and last word
    write_word(32'h00000000, 32'hAABBCCDD, WORD_MEM_ACCESS);
    read_word(32'h00000000, 32'hAABBCCDD, WORD_MEM_ACCESS);
    write_word((WORDS-1)*4, 32'h11223344, WORD_MEM_ACCESS);
    read_word((WORDS-1)*4, 32'h11223344, WORD_MEM_ACCESS);

    // byte lanes are returned zero-extended and addressed individually
    read_word(32'h00000000, 32'h000000DD, BYTE_MEM_ACCESS);
    read_word(32'h00000001, 32'h000000CC, BYTE_MEM_ACCESS);
    read_word(32'h00000002, 32'h000000BB, BYTE_MEM_ACCESS);
    read_word(32'h00000003, 32'h000000AA, BYTE_MEM_ACCESS);

    // halfword lanes
    read_word(32'h00000000, 32'h0000CCDD, HALF_MEM_ACCESS);
    read_word(32'h00000002, 32'h0000AABB, HALF_MEM_ACCESS);

    // a byte store only touches its own lane
    write_word(32'h00000001, 32'h000000EE, BYTE_MEM_ACCESS);
    read_word(32'h00000000, 32'hAABBEEDD, WORD_MEM_ACCESS);
    write_word(32'h00000003, 32'h00000011, BYTE_MEM_ACCESS);
    read_word(32'h00000000, 32'h11BBEEDD, WORD_MEM_ACCESS);

    // a halfword store only touches its own half
    write_word(32'h00000002, 32'h00005566, HALF_MEM_ACCESS);
    read_word(32'h00000000, 32'h5566EEDD, WORD_MEM_ACCESS);
    write_word(32'h00000000, 32'h00007788, HALF_MEM_ACCESS);
    read_word(32'h00000000, 32'h55667788, WORD_MEM_ACCESS);

    // misaligned accesses are rejected and do not modify memory
    expect_error(32'h00000001, WORD_MEM_ACCESS, 0, ADDRESS_MISALIGNED);
    expect_error(32'h00000002, WORD_MEM_ACCESS, 0, ADDRESS_MISALIGNED);
    expect_error(32'h00000001, HALF_MEM_ACCESS, 0, ADDRESS_MISALIGNED);
    expect_error(32'h00000003, WORD_MEM_ACCESS, 1, ADDRESS_MISALIGNED);
    expect_error(32'h00000001, HALF_MEM_ACCESS, 1, ADDRESS_MISALIGNED);
    read_word(32'h00000000, 32'h55667788, WORD_MEM_ACCESS);

    // out of bounds accesses are rejected and do not wrap into valid memory
    expect_error(WORDS*4, WORD_MEM_ACCESS, 0, OUT_OF_BOUNDS);
    expect_error(WORDS*4, BYTE_MEM_ACCESS, 1, OUT_OF_BOUNDS);
    expect_error(32'hFFFFFFFC, WORD_MEM_ACCESS, 1, OUT_OF_BOUNDS);
    expect_error(32'h80000000, BYTE_MEM_ACCESS, 0, OUT_OF_BOUNDS);
    read_word(32'h00000000, 32'h55667788, WORD_MEM_ACCESS);
    read_word((WORDS-1)*4, 32'h11223344, WORD_MEM_ACCESS);

    // image: the first word is there, everything after the image is zero (not x)
    if (image_dut.mem[0] !== 32'h00052283) begin
      test_failed = 1;
      $display("[%0t] error: image not loaded, mem[0]=0x%08x", $time, image_dut.mem[0]);
    end
    for (int w = 64; w < 128; w = w + 1) begin
      if (image_dut.mem[w] !== 32'h0) begin
        test_failed = 1;
        $display("[%0t] error: image memory word %0d beyond the image expected 0, got 0x%08x", $time, w, image_dut.mem[w]);
      end
    end

    // no error is flagged when idle
    @(negedge clk);
    if (mem_error !== NO_MEM_ERROR) begin
      test_failed = 1;
      $display("[%0t] error: mem_error=%b while idle", $time, mem_error);
    end

    // reset clears memory again
    rst_n = 0;
    repeat (2) @(posedge clk);
    rst_n = 1;
    @(posedge clk);
    read_word(32'h00000000, 32'h0, WORD_MEM_ACCESS);
    read_word((WORDS-1)*4, 32'h0, WORD_MEM_ACCESS);

    repeat (2) @(posedge clk);
    finish;
  end

endmodule
