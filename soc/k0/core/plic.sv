// platform level interrupt controller, one context (machine mode of hart 0), the register layout
// of the sifive plic that qemu virt uses (offsets from the base):
//
//   0x000000 + 4 * n   priority of source n, 1..NUM_SOURCES (PRIORITY_BITS wide, 0 = never interrupts)
//   0x001000           pending, bit n = source n (read only)
//   0x002000           enable, bit n = source n
//   0x200000           threshold: only sources with a priority above it interrupt
//   0x200004           claim (read) / complete (write)
//
// sources are level interrupts. a source becomes pending when its line is high and it is not
// being handled; a claim returns the id of the highest priority pending enabled source (the
// lowest id on a tie, 0 if there is none), clears its pending bit and holds the source until
// software completes it by writing the id back. a completion of an id that isn't enabled is ignored.
// anything else in the window reads 0 and ignores writes.
module plic #(
  parameter int NUM_SOURCES = 31, // 1..31, the sources are src[NUM_SOURCES:1], 0 is reserved
  parameter int PRIORITY_BITS = 3
)(
  input wire clk,
  input wire rst_n,

  input wire [NUM_SOURCES:1] src,

  // register access, one cycle, `sel` is high for exactly the cycle the access completes
  // (a claim has a side effect). reg_addr is the word offset, byte offset bits [25:2]
  input wire sel,
  input wire write,
  input wire [25:2] reg_addr,
  input wire [31:0] wdata,
  output reg [31:0] rdata,

  output wire meip // an enabled source above the threshold is pending
);

  localparam [25:2] PRIORITY_LAST = NUM_SOURCES;
  localparam [25:2] PENDING = 24'h1000 >> 2;
  localparam [25:2] ENABLE = 24'h2000 >> 2;
  localparam [25:2] THRESHOLD = 26'h20_0000 >> 2;
  localparam [25:2] CLAIM = 26'h20_0004 >> 2;

  reg [PRIORITY_BITS-1:0] priority_of [1:NUM_SOURCES];
  reg [NUM_SOURCES:1] pending;
  reg [NUM_SOURCES:1] enable;
  reg [NUM_SOURCES:1] in_flight; // claimed, not yet completed
  reg [PRIORITY_BITS-1:0] threshold;

  // the best candidate: highest priority above the threshold, lowest id on a tie
  reg [5:0] best_id;
  reg [PRIORITY_BITS-1:0] best_priority;
  always @* begin
    best_id = 0;
    best_priority = threshold;
    for (int i = 1; i <= NUM_SOURCES; i = i + 1) begin
      if (pending[i] && enable[i] && priority_of[i] > best_priority) begin
        best_id = i;
        best_priority = priority_of[i];
      end
    end
  end
  assign meip = (best_id != 0);

  wire is_priority = (reg_addr >= 1) && (reg_addr <= PRIORITY_LAST);
  wire [5:0] id_written = wdata[5:0];
  wire claim = sel && !write && reg_addr == CLAIM && meip;
  wire complete = sel && write && reg_addr == CLAIM && wdata[31:6] == 0 && id_written >= 1 && id_written <= NUM_SOURCES;

  always @* begin
    rdata = 0;
    if (is_priority) rdata = 32'(priority_of[reg_addr[7:2]]);
    else if (reg_addr == PENDING) rdata = 32'({pending, 1'b0});
    else if (reg_addr == ENABLE) rdata = 32'({enable, 1'b0});
    else if (reg_addr == THRESHOLD) rdata = 32'(threshold);
    else if (reg_addr == CLAIM) rdata = 32'(best_id);
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 1; i <= NUM_SOURCES; i = i + 1) priority_of[i] <= 0;
      pending <= 0;
      enable <= 0;
      in_flight <= 0;
      threshold <= 0;
    end
    else begin
      // gateway
      for (int i = 1; i <= NUM_SOURCES; i = i + 1) begin
        if (claim && best_id == i) begin
          pending[i] <= 0;
          in_flight[i] <= 1;
        end
        else if (complete && id_written == i && enable[i]) begin
          in_flight[i] <= 0;
        end
        else if (src[i] && !in_flight[i]) begin
          pending[i] <= 1;
        end
      end

      if (sel && write) begin
        if (is_priority) priority_of[reg_addr[7:2]] <= wdata[PRIORITY_BITS-1:0];
        else if (reg_addr == ENABLE) enable <= wdata[NUM_SOURCES:1];
        else if (reg_addr == THRESHOLD) threshold <= wdata[PRIORITY_BITS-1:0];
      end
    end
  end

endmodule
