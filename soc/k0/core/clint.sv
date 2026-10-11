// core local interruptor, the register layout of qemu's virt machine / sifive clint (one hart):
//
//   0x0000 msip          bit 0 is the software interrupt, the other bits read as 0
//   0x4000 mtimecmp low  \ 64 bit, the timer interrupt is high while mtime >= mtimecmp
//   0x4004 mtimecmp high / (resets to all ones, no interrupt until software sets it)
//   0xBFF8 mtime low     \ 64 bit, counts clocks
//   0xBFFC mtime high    /
//
// word registers. any other offset inside the window reads as 0 and ignores writes.
module clint #(
  parameter int DATA_WIDTH = 32
)(
  input wire clk,
  input wire rst_n,

  // register access, one cycle: `sel` with `write` or not
  input wire sel,
  input wire write,
  input wire [15:2] reg_addr, // word offset inside the window
  input wire [DATA_WIDTH-1:0] wdata,
  output reg [DATA_WIDTH-1:0] rdata,

  output wire [63:0] mtime,
  output wire msip,
  output wire mtip
);

  localparam [15:2] MSIP = 14'h0000 >> 2;
  localparam [15:2] MTIMECMP_LO = 16'h4000 >> 2;
  localparam [15:2] MTIMECMP_HI = 16'h4004 >> 2;
  localparam [15:2] MTIME_LO = 16'hBFF8 >> 2;
  localparam [15:2] MTIME_HI = 16'hBFFC >> 2;

  reg [63:0] time_reg;
  reg [63:0] timecmp;
  reg sw_irq;

  assign mtime = time_reg;
  assign msip = sw_irq;
  assign mtip = (time_reg >= timecmp);

  always @* begin
    case (reg_addr)
      MSIP: rdata = {31'b0, sw_irq};
      MTIMECMP_LO: rdata = timecmp[31:0];
      MTIMECMP_HI: rdata = timecmp[63:32];
      MTIME_LO: rdata = time_reg[31:0];
      MTIME_HI: rdata = time_reg[63:32];
      default: rdata = '0;
    endcase
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      time_reg <= 64'd0;
      timecmp <= '1;
      sw_irq <= 0;
    end
    else begin
      time_reg <= time_reg + 1;
      if (sel && write) begin
        case (reg_addr)
          MSIP: sw_irq <= wdata[0];
          MTIMECMP_LO: timecmp[31:0] <= wdata;
          MTIMECMP_HI: timecmp[63:32] <= wdata;
          MTIME_LO: time_reg[31:0] <= wdata; // a write wins over the count
          MTIME_HI: time_reg[63:32] <= wdata;
          default: begin
          end
        endcase
      end
    end
  end

endmodule
