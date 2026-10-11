`timescale 1ns/1ps
import isa_shared::*;

// memory map, access faults, unified instruction/data view of the ram and wait states.
// run from soc/k0 (the boot rom image is ./memory/bootrom.hex).
module test_bus;

  localparam [31:0] ROM_BASE = 32'h0000_1000;
  localparam int ROM_WORDS = 16;
  localparam [31:0] RAM_BASE = 32'h8000_0000;
  localparam int RAM_WORDS = 32;

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
  initial begin
    clk = 0;
    forever #5 clk = !clk;
  end

  // ---- dut without wait states
  reg [31:0] imem_addr;
  wire [31:0] imem_data;
  wire imem_ready;
  wire [1:0] imem_error;
  reg mem_read;
  reg mem_write;
  reg [1:0] mem_access_type;
  reg [31:0] mem_addr;
  reg [31:0] mem_wdata;
  wire [31:0] mem_rdata;
  wire mem_ready;
  wire [1:0] mem_error;
  wire uart_tx;
  wire [63:0] mtime;
  wire msip;
  wire mtip;

  bus #(
    .ROM_BASE(ROM_BASE), .ROM_WORDS(ROM_WORDS),
    .RAM_BASE(RAM_BASE), .RAM_WORDS(RAM_WORDS)
  ) dut (
    .clk(clk), .rst_n(rst_n),
    .imem_addr(imem_addr), .imem_data(imem_data), .imem_ready(imem_ready), .imem_error(imem_error),
    .mem_read(mem_read), .mem_write(mem_write), .mem_access_type(mem_access_type),
    .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ready(mem_ready), .mem_error(mem_error),
    .uart_tx(uart_tx),
    .mtime(mtime),
    .msip(msip),
    .mtip(mtip)
  );

  // ---- dut with wait states
  reg [31:0] s_imem_addr;
  wire [31:0] s_imem_data;
  wire s_imem_ready;
  wire [1:0] s_imem_error;
  reg s_mem_read;
  reg s_mem_write;
  reg [1:0] s_mem_access_type;
  reg [31:0] s_mem_addr;
  reg [31:0] s_mem_wdata;
  wire [31:0] s_mem_rdata;
  wire s_mem_ready;
  wire [1:0] s_mem_error;
  wire s_uart_tx;

  bus #(
    .ROM_BASE(ROM_BASE), .ROM_WORDS(ROM_WORDS),
    .RAM_BASE(RAM_BASE), .RAM_WORDS(RAM_WORDS),
    .FETCH_WAIT(2), .DATA_WAIT(3)
  ) slow (
    .clk(clk), .rst_n(rst_n),
    .imem_addr(s_imem_addr), .imem_data(s_imem_data), .imem_ready(s_imem_ready), .imem_error(s_imem_error),
    .mem_read(s_mem_read), .mem_write(s_mem_write), .mem_access_type(s_mem_access_type),
    .mem_addr(s_mem_addr), .mem_wdata(s_mem_wdata), .mem_rdata(s_mem_rdata), .mem_ready(s_mem_ready), .mem_error(s_mem_error),
    .uart_tx(s_uart_tx),
    .mtime(),
    .msip(),
    .mtip()
  );

  // ---- helpers
  task idle;
    begin
      mem_read = 0;
      mem_write = 0;
      mem_wdata = '0;
    end
  endtask

  task load(input [31:0] a, input [1:0] t, input [31:0] exp_data, input [1:0] exp_err, input string name);
    begin
      mem_addr = a;
      mem_access_type = t;
      mem_read = 1;
      #1;
      if (mem_rdata !== exp_data || mem_error !== exp_err || mem_ready !== 1'b1) begin
        test_failed = 1;
        $display("[%0t] error: %s load 0x%08x expected data=0x%08x err=%b, got data=0x%08x err=%b ready=%b", $time, name, a, exp_data, exp_err, mem_rdata, mem_error, mem_ready);
      end
      mem_read = 0;
    end
  endtask

  task store(input [31:0] a, input [1:0] t, input [31:0] d, input [1:0] exp_err, input string name);
    begin
      mem_addr = a;
      mem_access_type = t;
      mem_wdata = d;
      mem_write = 1;
      #1;
      if (mem_error !== exp_err) begin
        test_failed = 1;
        $display("[%0t] error: %s store 0x%08x expected err=%b, got err=%b", $time, name, a, exp_err, mem_error);
      end
      @(posedge clk);
      #1;
      idle();
    end
  endtask

  task fetch(input [31:0] a, input [31:0] exp_data, input [1:0] exp_err, input string name);
    begin
      imem_addr = a;
      #1;
      if (imem_data !== exp_data || imem_error !== exp_err || imem_ready !== 1'b1) begin
        test_failed = 1;
        $display("[%0t] error: %s fetch 0x%08x expected data=0x%08x err=%b, got data=0x%08x err=%b ready=%b", $time, name, a, exp_data, exp_err, imem_data, imem_error, imem_ready);
      end
    end
  endtask

  task expect_bit(input got, input exp, input string what);
    begin
      if (got !== exp) begin
        test_failed = 1;
        $display("[%0t] error: %s expected %b, got %b", $time, what, exp, got);
      end
    end
  endtask

  integer i;
  initial begin
    $dumpfile("./tests/results/test_bus.vcd");
    $dumpvars(0, test_bus);
    test_failed = 0;
    imem_addr = ROM_BASE;
    idle();
    mem_addr = '0;
    mem_access_type = WORD_MEM_ACCESS;
    s_imem_addr = RAM_BASE;
    s_mem_read = 0;
    s_mem_write = 0;
    s_mem_access_type = WORD_MEM_ACCESS;
    s_mem_addr = RAM_BASE;
    s_mem_wdata = '0;

    rst_n = 0;
    repeat (2) @(posedge clk);
    #1 rst_n = 1;
    @(negedge clk);

    // boot rom: the image, then zeros up to its size
    load(ROM_BASE, WORD_MEM_ACCESS, 32'h800002b7, NO_MEM_ERROR, "rom word 0");
    load(ROM_BASE + 4, WORD_MEM_ACCESS, 32'h00028067, NO_MEM_ERROR, "rom word 1");
    load(ROM_BASE + 8, WORD_MEM_ACCESS, 32'h0, NO_MEM_ERROR, "rom word 2");
    load(ROM_BASE + 4*(ROM_WORDS-1), WORD_MEM_ACCESS, 32'h0, NO_MEM_ERROR, "rom last word");
    load(ROM_BASE + 1, BYTE_MEM_ACCESS, 32'h00000002, NO_MEM_ERROR, "rom byte lane"); // 0x800002b7 -> byte 1 = 0x02
    fetch(ROM_BASE, 32'h800002b7, NO_MEM_ERROR, "rom");
    fetch(ROM_BASE + 4, 32'h00028067, NO_MEM_ERROR, "rom");

    // the rom can't be written: access fault, contents unchanged
    store(ROM_BASE, WORD_MEM_ACCESS, 32'hDEADBEEF, OUT_OF_BOUNDS, "rom");
    store(ROM_BASE + 8, BYTE_MEM_ACCESS, 32'h000000AA, OUT_OF_BOUNDS, "rom");
    load(ROM_BASE, WORD_MEM_ACCESS, 32'h800002b7, NO_MEM_ERROR, "rom after store attempt");
    load(ROM_BASE + 8, WORD_MEM_ACCESS, 32'h0, NO_MEM_ERROR, "rom after store attempt");

    // ram: stores and loads, all widths
    load(RAM_BASE, WORD_MEM_ACCESS, 32'h0, NO_MEM_ERROR, "ram initial");
    store(RAM_BASE, WORD_MEM_ACCESS, 32'hAABBCCDD, NO_MEM_ERROR, "ram");
    load(RAM_BASE, WORD_MEM_ACCESS, 32'hAABBCCDD, NO_MEM_ERROR, "ram word");
    load(RAM_BASE + 2, HALF_MEM_ACCESS, 32'h0000AABB, NO_MEM_ERROR, "ram half");
    load(RAM_BASE + 1, BYTE_MEM_ACCESS, 32'h000000CC, NO_MEM_ERROR, "ram byte");
    store(RAM_BASE + 3, BYTE_MEM_ACCESS, 32'h00000011, NO_MEM_ERROR, "ram byte");
    load(RAM_BASE, WORD_MEM_ACCESS, 32'h11BBCCDD, NO_MEM_ERROR, "ram after byte store");
    store(RAM_BASE + 4*(RAM_WORDS-1), WORD_MEM_ACCESS, 32'h01234567, NO_MEM_ERROR, "ram last word");
    load(RAM_BASE + 4*(RAM_WORDS-1), WORD_MEM_ACCESS, 32'h01234567, NO_MEM_ERROR, "ram last word");

    // instruction port sees the data port's stores, same address space
    fetch(RAM_BASE, 32'h11BBCCDD, NO_MEM_ERROR, "ram after store");
    store(RAM_BASE + 8, WORD_MEM_ACCESS, 32'h00000013, NO_MEM_ERROR, "ram");
    fetch(RAM_BASE + 8, 32'h00000013, NO_MEM_ERROR, "ram right after a store");

    // addresses outside the map fault for loads, stores and fetches and have no side effect
    load(32'h0000_0000, WORD_MEM_ACCESS, 32'h0, OUT_OF_BOUNDS, "below rom");
    load(ROM_BASE - 4, WORD_MEM_ACCESS, 32'h0, OUT_OF_BOUNDS, "just below rom");
    load(ROM_BASE + 4*ROM_WORDS, WORD_MEM_ACCESS, 32'h0, OUT_OF_BOUNDS, "just above rom");
    load(RAM_BASE - 4, WORD_MEM_ACCESS, 32'h0, OUT_OF_BOUNDS, "just below ram");
    load(RAM_BASE + 4*RAM_WORDS, WORD_MEM_ACCESS, 32'h0, OUT_OF_BOUNDS, "just above ram");
    load(32'hFFFF_FFFC, WORD_MEM_ACCESS, 32'h0, OUT_OF_BOUNDS, "top of address space");
    store(32'h2000_0000, WORD_MEM_ACCESS, 32'hFFFFFFFF, OUT_OF_BOUNDS, "unmapped");
    store(RAM_BASE + 4*RAM_WORDS, WORD_MEM_ACCESS, 32'hFFFFFFFF, OUT_OF_BOUNDS, "past ram");
    store(RAM_BASE - 4, WORD_MEM_ACCESS, 32'hFFFFFFFF, OUT_OF_BOUNDS, "before ram");
    load(RAM_BASE, WORD_MEM_ACCESS, 32'h11BBCCDD, NO_MEM_ERROR, "ram untouched by faulting stores");
    load(RAM_BASE + 4*(RAM_WORDS-1), WORD_MEM_ACCESS, 32'h01234567, NO_MEM_ERROR, "ram end untouched");
    fetch(32'h0000_0000, 32'h0, OUT_OF_BOUNDS, "unmapped");
    fetch(RAM_BASE + 4*RAM_WORDS, 32'h0, OUT_OF_BOUNDS, "past ram");
    fetch(32'h1000_0000, 32'h0, OUT_OF_BOUNDS, "uart (data port only)");
    fetch(32'h2000_0000, 32'h0, OUT_OF_BOUNDS, "unmapped");

    // uart: byte registers only, the registers repeat inside the window
    load(32'h1000_0005, BYTE_MEM_ACCESS, 32'h00000060, NO_MEM_ERROR, "uart LSR idle");
    load(32'h1000_0002, BYTE_MEM_ACCESS, 32'h00000001, NO_MEM_ERROR, "uart IIR");
    store(32'h1000_0007, BYTE_MEM_ACCESS, 32'h0000005A, NO_MEM_ERROR, "uart SCR");
    load(32'h1000_0007, BYTE_MEM_ACCESS, 32'h0000005A, NO_MEM_ERROR, "uart SCR readback");
    load(32'h1000_00FF, BYTE_MEM_ACCESS, 32'h0000005A, NO_MEM_ERROR, "uart SCR mirror at the end of the window");
    load(32'h1000_0100, BYTE_MEM_ACCESS, 32'h0, OUT_OF_BOUNDS, "just above the uart window");
    load(32'h0FFF_FFFF, BYTE_MEM_ACCESS, 32'h0, OUT_OF_BOUNDS, "just below the uart window");
    load(32'h1000_0004, WORD_MEM_ACCESS, 32'h0, OUT_OF_BOUNDS, "uart word load");
    load(32'h1000_0004, HALF_MEM_ACCESS, 32'h0, OUT_OF_BOUNDS, "uart half load");
    store(32'h1000_0000, WORD_MEM_ACCESS, 32'h00000041, OUT_OF_BOUNDS, "uart word store");
    store(32'h1000_0000, HALF_MEM_ACCESS, 32'h00000041, OUT_OF_BOUNDS, "uart half store");
    load(32'h1000_0005, BYTE_MEM_ACCESS, 32'h00000060, NO_MEM_ERROR, "uart idle after the faulting stores");
    expect_bit(uart_tx, 1'b1, "uart line idle after the faulting stores");
    store(32'h1000_0000, BYTE_MEM_ACCESS, 32'h00000041, NO_MEM_ERROR, "uart THR");
    load(32'h1000_0005, BYTE_MEM_ACCESS, 32'h00000000, NO_MEM_ERROR, "uart LSR busy after a THR store");
    expect_bit(uart_tx, 1'b0, "uart start bit");

    // clint @ 0x0200_0000: 32 bit registers, word accesses only, data port only
    fetch(32'h0200_0000, 32'h0, OUT_OF_BOUNDS, "clint (data port only)");
    load(32'h0200_4000, WORD_MEM_ACCESS, 32'hFFFF_FFFF, NO_MEM_ERROR, "clint mtimecmp low at reset");
    load(32'h0200_0000, WORD_MEM_ACCESS, 32'h0, NO_MEM_ERROR, "clint msip");
    store(32'h0200_0000, WORD_MEM_ACCESS, 32'h1, NO_MEM_ERROR, "clint msip");
    expect_bit(msip, 1'b1, "msip output follows the register");
    load(32'h0200_0000, WORD_MEM_ACCESS, 32'h1, NO_MEM_ERROR, "clint msip readback");
    store(32'h0200_4000, WORD_MEM_ACCESS, 32'h0, NO_MEM_ERROR, "clint mtimecmp low");
    store(32'h0200_4004, WORD_MEM_ACCESS, 32'h0, NO_MEM_ERROR, "clint mtimecmp high");
    expect_bit(mtip, 1'b1, "mtip output once mtime >= mtimecmp");
    store(32'h0200_0000, WORD_MEM_ACCESS, 32'h0, NO_MEM_ERROR, "clint msip clear");
    load(32'h0200_0000, BYTE_MEM_ACCESS, 32'h0, OUT_OF_BOUNDS, "clint byte load");
    load(32'h0200_0000, HALF_MEM_ACCESS, 32'h0, OUT_OF_BOUNDS, "clint half load");
    store(32'h0200_0000, BYTE_MEM_ACCESS, 32'h1, OUT_OF_BOUNDS, "clint byte store");
    expect_bit(msip, 1'b0, "a faulting store does not reach the clint");
    load(32'h0200_0002, WORD_MEM_ACCESS, 32'h0, ADDRESS_MISALIGNED, "clint misaligned load");
    store(32'h0200_0002, WORD_MEM_ACCESS, 32'h1, ADDRESS_MISALIGNED, "clint misaligned store");
    expect_bit(msip, 1'b0, "a misaligned store does not reach the clint");
    load(32'h0201_0000, WORD_MEM_ACCESS, 32'h0, OUT_OF_BOUNDS, "just above the clint window");
    load(32'h01FF_FFFC, WORD_MEM_ACCESS, 32'h0, OUT_OF_BOUNDS, "just below the clint window");

    // misaligned accesses fault inside the regions
    load(RAM_BASE + 2, WORD_MEM_ACCESS, 32'h0, ADDRESS_MISALIGNED, "ram");
    load(RAM_BASE + 1, HALF_MEM_ACCESS, 32'h0, ADDRESS_MISALIGNED, "ram");
    store(RAM_BASE + 1, WORD_MEM_ACCESS, 32'hFFFFFFFF, ADDRESS_MISALIGNED, "ram");
    load(RAM_BASE, WORD_MEM_ACCESS, 32'h11BBCCDD, NO_MEM_ERROR, "ram untouched by misaligned store");
    load(ROM_BASE + 2, WORD_MEM_ACCESS, 32'h0, ADDRESS_MISALIGNED, "rom");
    fetch(RAM_BASE + 2, 32'h0, ADDRESS_MISALIGNED, "ram");

    // nothing requested, nothing flagged
    idle();
    mem_addr = 32'hFFFF_0000;
    #1;
    expect_bit(mem_error === NO_MEM_ERROR, 1'b1, "idle data port has no error");

    // ---- wait states: fetch 2 cycles, data 3 cycles. requests are launched just after a clock
    // edge, like the core does, and sampled just after the following edges.
    @(posedge clk); #1;
    s_imem_addr = ROM_BASE; // an earlier fetch
    @(posedge clk); #1;
    s_imem_addr = RAM_BASE; // new fetch
    #1;
    expect_bit(s_imem_ready, 1'b0, "fetch ready in cycle 0");
    @(posedge clk); #1;
    expect_bit(s_imem_ready, 1'b0, "fetch ready in cycle 1");
    @(posedge clk); #1;
    expect_bit(s_imem_ready, 1'b1, "fetch ready in cycle 2");
    @(posedge clk); #1;
    expect_bit(s_imem_ready, 1'b1, "fetch stays ready while the same address is held");
    s_imem_addr = RAM_BASE + 4; // new fetch, the wait starts over
    #1;
    expect_bit(s_imem_ready, 1'b0, "fetch ready right after the address changed");
    s_imem_addr = ROM_BASE; // the wait applies to the rom too
    @(posedge clk); #1;
    @(posedge clk); #1;
    expect_bit(s_imem_ready, 1'b1, "rom fetch ready after 2 cycles");
    expect_bit(s_imem_data === 32'h800002b7, 1'b1, "rom fetch data after the wait");

    // data: a store lands once, on the edge that completes the transfer
    @(posedge clk); #1;
    s_mem_addr = RAM_BASE + 16;
    s_mem_wdata = 32'hA5A5A5A5;
    s_mem_write = 1;
    #1;
    expect_bit(s_mem_ready, 1'b0, "store ready in cycle 0");
    for (i = 1; i < 3; i = i + 1) begin
      @(posedge clk); #1;
      expect_bit(s_mem_ready, 1'b0, "store ready while waiting");
    end
    expect_bit(slow.ram_inst.mem[4] === 32'h0, 1'b1, "store must not land while waiting");
    @(posedge clk); #1;
    expect_bit(s_mem_ready, 1'b1, "store ready in cycle 3");
    expect_bit(slow.ram_inst.mem[4] === 32'h0, 1'b1, "store not landed before the completing edge");
    @(posedge clk); #1;
    expect_bit(slow.ram_inst.mem[4] === 32'hA5A5A5A5, 1'b1, "store landed on the completing edge");
    s_mem_write = 0;

    // data: a load returns its data when ready, an idle port is always ready
    @(posedge clk); #1;
    s_mem_addr = RAM_BASE + 16;
    s_mem_read = 1;
    #1;
    expect_bit(s_mem_ready, 1'b0, "load ready in cycle 0");
    repeat (3) begin
      @(posedge clk); #1;
    end
    expect_bit(s_mem_ready, 1'b1, "load ready after 3 wait cycles");
    expect_bit(s_mem_rdata === 32'hA5A5A5A5, 1'b1, "load data");
    s_mem_read = 0;
    #1;
    expect_bit(s_mem_ready, 1'b1, "idle data port is ready");

    // a uart register write lands once, on the completing edge, after the wait
    @(posedge clk); #1;
    s_mem_addr = 32'h1000_0000;
    s_mem_wdata = 32'h00000042;
    s_mem_write = 1;
    s_mem_access_type = BYTE_MEM_ACCESS;
    #1;
    expect_bit(s_mem_ready, 1'b0, "uart store ready in cycle 0");
    repeat (3) begin
      @(posedge clk); #1;
    end
    expect_bit(s_mem_ready, 1'b1, "uart store ready in cycle 3");
    expect_bit(slow.uart_inst.busy, 1'b0, "uart not started before the completing edge");
    @(posedge clk); #1;
    expect_bit(slow.uart_inst.busy, 1'b1, "uart started on the completing edge");
    s_mem_write = 0;
    s_mem_access_type = WORD_MEM_ACCESS;

    // a faulting access completes (with its error) after the same wait
    @(posedge clk); #1;
    s_mem_addr = 32'h0000_0000;
    s_mem_read = 1;
    repeat (3) begin
      @(posedge clk); #1;
    end
    expect_bit(s_mem_ready, 1'b1, "unmapped load ready after the wait");
    expect_bit(s_mem_error === OUT_OF_BOUNDS, 1'b1, "unmapped load error");
    s_mem_read = 0;

    finish;
  end

endmodule
