// physical memory protection check: N regions, 4 byte granularity (so NA4 exists and pmpaddr uses all
// 32 bits). `cfg` and `addr` are the pmpcfg bytes and pmpaddr registers of the csr file, entry 0 in the
// low bits. an access is checked by its (word aligned) address: accesses are at most 4 bytes and aligned,
// so they never straddle two regions.
//
//   cfg bit 0 R, 1 W, 2 X, 4:3 A (0 off, 1 TOR, 2 NA4, 3 NAPOT), 7 L (locked: also binds machine mode)
//
// the lowest numbered entry that matches decides. user mode succeeds only when the matching entry
// grants every permission asked for, and fails when nothing matches. machine mode succeeds when nothing
// matches or the matching entry is not locked, a locked entry binds it too.
module pmp #(
  parameter int N = 8
)(
  input wire [N*8-1:0] cfg,
  input wire [N*32-1:0] addr,
  input wire user,
  input wire [31:0] a, // byte address
  input wire r,
  input wire w,
  input wire x,
  output reg ok
);

  reg found;
  reg [7:0] c;
  reg [31:0] lo;
  reg [31:0] hi;
  reg [31:0] mask;
  reg hit;
  wire [31:0] aw = {2'b00, a[31:2]}; // pmpaddr holds address bits 33:2

  always @* begin
    found = 0;
    c = 8'h00;
    ok = !user;
    for (int i = 0; i < N; i = i + 1) begin
      hi = addr[i*32 +: 32];
      lo = (i == 0) ? 32'h0 : addr[(i-1)*32 +: 32];
      mask = hi ^ (hi + 32'd1); // NAPOT: the trailing ones of pmpaddr and the zero above them
      case (cfg[i*8 + 3 +: 2])
        2'd1: hit = (aw >= lo) && (aw < hi);
        2'd2: hit = (aw == hi);
        2'd3: hit = ((aw ^ hi) & ~mask) == 32'h0;
        default: hit = 0;
      endcase
      if (hit && !found) begin
        found = 1;
        c = cfg[i*8 +: 8];
      end
    end
    if (found && (user || c[7])) ok = (!r || c[0]) && (!w || c[1]) && (!x || c[2]);
    else if (found) ok = 1;
  end

endmodule
