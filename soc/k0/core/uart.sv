// transmit only uart with the register layout of a 16550 (byte registers, offsets 0..7), which is
// what the linux ns16550a driver and earlycon expect for console output. 8N1 at
// clk / CLKS_PER_BIT baud.
//
//   0 THR (write)  start sending a byte, dropped if a byte is still being sent. RBR (read) is 0, there is no receiver
//   1 IER          read/write, no interrupts yet
//   2 IIR (read)   0x01, no interrupt pending
//   3 LCR, 4 MCR   read/write, stored only
//   5 LSR (read)   bit 5 THRE and bit 6 TEMT: set when idle
//   6 MSR (read)   0
//   7 SCR          scratch, read/write
module uart #(
  parameter int CLKS_PER_BIT = 8,
  parameter bit ECHO = 0 // print every accepted byte in simulation
)(
  input wire clk,
  input wire rst_n,

  // register access, one cycle: `sel` with `write` or not
  input wire sel,
  input wire write,
  input wire [2:0] reg_addr,
  input wire [7:0] wdata,
  output reg [7:0] rdata,

  output wire tx
);

  reg [7:0] ier;
  reg [7:0] lcr;
  reg [7:0] mcr;
  reg [7:0] scr;

  reg busy;
  reg [9:0] shift; // stop, 8 data bits, start; shifted out from bit 0
  reg [3:0] bits_left;
  reg [$clog2(CLKS_PER_BIT+1)-1:0] clk_count;

  assign tx = busy ? shift[0] : 1'b1;

  wire thr_write = sel && write && reg_addr == 3'd0 && !busy;

  always @* begin
    case (reg_addr)
      3'd1: rdata = ier;
      3'd2: rdata = 8'h01;
      3'd3: rdata = lcr;
      3'd4: rdata = mcr;
      3'd5: rdata = {1'b0, !busy, !busy, 5'b0};
      3'd7: rdata = scr;
      default: rdata = 8'h00;
    endcase
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ier <= 0;
      lcr <= 0;
      mcr <= 0;
      scr <= 0;
      busy <= 0;
      shift <= '1;
      bits_left <= 0;
      clk_count <= 0;
    end
    else begin
      if (sel && write) begin
        case (reg_addr)
          3'd1: ier <= wdata;
          3'd3: lcr <= wdata;
          3'd4: mcr <= wdata;
          3'd7: scr <= wdata;
          default: begin
          end
        endcase
      end

      if (thr_write) begin
        busy <= 1;
        shift <= {1'b1, wdata, 1'b0};
        bits_left <= 10;
        clk_count <= 1;
        if (ECHO) $write("%c", wdata);
      end
      else if (busy) begin
        if (clk_count == CLKS_PER_BIT) begin
          clk_count <= 1;
          shift <= {1'b1, shift[9:1]};
          bits_left <= bits_left - 1;
          if (bits_left == 1) busy <= 0;
        end
        else begin
          clk_count <= clk_count + 1;
        end
      end
    end
  end

endmodule
