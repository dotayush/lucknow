`timescale 1ns/1ps

// the pmp checker alone: matching modes, priority, user versus machine mode, locking
module test_pmp;

  reg test_failed;
  localparam int N = 4;
  reg [N*8-1:0] cfg;
  reg [N*32-1:0] addr;
  reg user;
  reg [31:0] a;
  reg r, w, x;
  wire ok;

  pmp #(.N(N)) dut (.cfg(cfg), .addr(addr), .user(user), .a(a), .r(r), .w(w), .x(x), .ok(ok));

  localparam [7:0] R = 8'h01, W = 8'h02, X = 8'h04, TOR = 8'h08, NA4 = 8'h10, NAPOT = 8'h18, L = 8'h80;

  task check(input [31:0] address, input rr, input ww, input xx, input u, input exp, input string name);
    begin
      a = address; r = rr; w = ww; x = xx; user = u;
      #1;
      if (ok !== exp) begin
        test_failed = 1;
        $display("error: %s: expected %0d got %0d", name, exp, ok);
      end
    end
  endtask

  initial begin
    test_failed = 0;
    cfg = 0;
    addr = 0;

    // nothing configured: machine mode passes, user mode fails
    check(32'h8000_0000, 1, 0, 0, 0, 1, "M, no entries");
    check(32'h8000_0000, 1, 0, 0, 1, 0, "U, no entries");

    // entry 0: NAPOT 4 KiB at 0x8000_0000 rw, entry 1: TOR from there to 0x8000_3000 r
    cfg = {8'h00, 8'h00, TOR | R, NAPOT | R | W};
    addr[0*32 +: 32] = 32'h2000_0000 | 32'h1ff;
    addr[1*32 +: 32] = 32'h8000_3000 >> 2;
    check(32'h8000_0ffc, 1, 0, 0, 1, 1, "U read inside the napot region");
    check(32'h8000_0ffc, 0, 1, 0, 1, 1, "U write inside the napot region");
    check(32'h8000_0ffc, 0, 0, 1, 1, 0, "U fetch without x");
    check(32'h8000_1000, 1, 0, 0, 1, 1, "U read in the TOR region");
    check(32'h8000_1000, 0, 1, 0, 1, 0, "U write in a read only TOR region");
    check(32'h8000_2ffc, 1, 0, 0, 1, 1, "U read at the last word of TOR");
    check(32'h8000_3000, 1, 0, 0, 1, 0, "U read at the TOR top (exclusive)");
    check(32'h8000_1000, 0, 1, 0, 0, 1, "M write to an unlocked read only region");
    check(32'h9000_0000, 0, 1, 0, 0, 1, "M outside every region");
    check(32'h8000_1000, 1, 1, 0, 1, 0, "U amo (r and w) on a read only region");

    // lowest entry wins: entry 0 is read only and shadows the writable entry 1 over the same range
    cfg = {16'h0000, NAPOT | R | W, NAPOT | R};
    addr[0*32 +: 32] = 32'h2000_0000 | 32'h1ff;
    addr[1*32 +: 32] = 32'h2000_0000 | 32'h3ff;
    check(32'h8000_0100, 0, 1, 0, 1, 0, "priority: entry 0 decides");
    check(32'h8000_1100, 0, 1, 0, 1, 1, "entry 1 where entry 0 does not reach");

    // NA4: exactly one word
    cfg = {24'h0, NA4 | R | W};
    addr[0*32 +: 32] = 32'h8000_2000 >> 2;
    check(32'h8000_2000, 1, 0, 0, 1, 1, "NA4 hit");
    check(32'h8000_2004, 1, 0, 0, 1, 0, "NA4 next word");
    check(32'h8000_1ffc, 1, 0, 0, 1, 0, "NA4 previous word");

    // a locked entry binds machine mode
    cfg = {24'h0, L | NAPOT | R};
    addr[0*32 +: 32] = 32'h2000_0000 | 32'h1ff;
    check(32'h8000_0000, 1, 0, 0, 0, 1, "M read of a locked r region");
    check(32'h8000_0000, 0, 1, 0, 0, 0, "M write of a locked r region");

    // NAPOT of everything (what linux sets up)
    cfg = {24'h0, NAPOT | R | W | X};
    addr[0*32 +: 32] = 32'hFFFF_FFFF;
    check(32'h0000_0000, 0, 0, 1, 1, 1, "U fetch, all of memory, low");
    check(32'hFFFF_FFFC, 0, 1, 0, 1, 1, "U write, all of memory, high");

    if (test_failed) $display("Test failed!");
    else $display("Test passed!");
    $finish;
  end

endmodule
