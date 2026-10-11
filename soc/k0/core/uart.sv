// uart with the register layout of a 16550 (byte registers, offsets 0..7), which is what the
// linux 8250 driver and earlycon expect. 8N1 at clk / CLKS_PER_BIT baud (CLKS_PER_BIT >= 4),
// no fifos: one transmit holding byte (the shift register itself) and one receive byte, so it
// is a 16450 as far as software can tell (use compatible "ns16450" in a device tree: a 16550a
// driver would write 16 bytes at a time).
//
//   0 THR (write)  start sending a byte, dropped if a byte is still being sent
//     RBR (read)   the received byte, clears DR
//     DLL          divisor latch low while LCR bit 7 (DLAB) is set, stored only (the baud rate is fixed)
//   1 IER          bit 0 received data, bit 1 THR empty, bit 2 receiver line status (bit 3 modem, stored only)
//     DLM          divisor latch high while DLAB, stored only
//   2 IIR (read)   0x01 nothing pending, else 0x06 line status, 0x04 received data, 0x02 THR empty
//                  (highest first); reading it while 0x02 is reported clears that interrupt
//     FCR (write)  ignored
//   3 LCR, 4 MCR   read/write, stored only
//   5 LSR (read)   bit 0 DR, bit 1 OE (overrun), bit 3 FE (framing), bit 5 THRE, bit 6 TEMT;
//                  OE and FE clear when read
//   6 MSR (read)   0
//   7 SCR          scratch, read/write
//
// an overrun drops the new byte and keeps the unread one (as a 16450 does). `irq` is the level
// of the interrupt output (a PLIC source). register reads and writes are one cycle: `sel` is high
// for exactly the cycle the access completes, because reading RBR, LSR and IIR has side effects.
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

  input wire rx,
  output wire tx,
  output wire irq
);

  reg [7:0] ier;
  reg [7:0] lcr;
  reg [7:0] mcr;
  reg [7:0] scr;
  reg [7:0] dll;
  reg [7:0] dlm;

  // ---- transmitter
  reg busy;
  reg [9:0] shift; // stop, 8 data bits, start; shifted out from bit 0
  reg [3:0] bits_left;
  reg [$clog2(CLKS_PER_BIT+1)-1:0] clk_count;

  assign tx = busy ? shift[0] : 1'b1;

  wire dlab = lcr[7];
  wire access = sel && !dlab;
  wire thr_write = access && write && reg_addr == 3'd0 && !busy;
  wire rbr_read = access && !write && reg_addr == 3'd0;
  wire lsr_read = sel && !write && reg_addr == 3'd5;
  wire iir_read = sel && !write && reg_addr == 3'd2;
  wire ier_write = access && write && reg_addr == 3'd1;

  // ---- receiver. rx goes through two flops, then a start bit is looked for and every bit sampled
  // in its middle: the first check is half a bit after the detection, the others one bit apart
  localparam int START_CHECK = CLKS_PER_BIT / 2 - 1;
  localparam [1:0] RX_IDLE = 2'd0, RX_START = 2'd1, RX_DATA = 2'd2, RX_STOP = 2'd3;
  reg rx_meta;
  reg rx_sync;
  reg [1:0] rx_state;
  reg rx_wait_high; // a frame ended on a low line (break): wait for it to go high before the next start
  reg [$clog2(CLKS_PER_BIT+1)-1:0] rx_count;
  reg [2:0] rx_bit;
  reg [7:0] rx_shift;
  reg [7:0] rbr;
  reg dr;
  reg oe;
  reg fe;

  // ---- interrupts
  reg thre_int; // transmitter became empty (or THRE interrupts were just enabled), until IIR read or THR write
  wire line_irq = ier[2] && (oe || fe);
  wire data_irq = ier[0] && dr;
  wire thr_irq = ier[1] && thre_int;
  wire [7:0] iir = line_irq ? 8'h06 : data_irq ? 8'h04 : thr_irq ? 8'h02 : 8'h01;
  assign irq = line_irq || data_irq || thr_irq;

  always @* begin
    case (reg_addr)
      3'd0: rdata = dlab ? dll : rbr;
      3'd1: rdata = dlab ? dlm : ier;
      3'd2: rdata = iir;
      3'd3: rdata = lcr;
      3'd4: rdata = mcr;
      3'd5: rdata = {1'b0, !busy, !busy, 1'b0, fe, 1'b0, oe, dr};
      3'd7: rdata = scr;
      default: rdata = 8'h00;
    endcase
  end

  wire rx_frame_done = (rx_state == RX_STOP) && (rx_count == CLKS_PER_BIT);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ier <= 0;
      lcr <= 0;
      mcr <= 0;
      scr <= 0;
      dll <= 0;
      dlm <= 0;
      busy <= 0;
      shift <= '1;
      bits_left <= 0;
      clk_count <= 0;
      thre_int <= 0;
      rx_meta <= 1;
      rx_sync <= 1;
      rx_state <= RX_IDLE;
      rx_wait_high <= 0;
      rx_count <= 0;
      rx_bit <= 0;
      rx_shift <= 0;
      rbr <= 0;
      dr <= 0;
      oe <= 0;
      fe <= 0;
    end
    else begin
      if (sel && write) begin
        case (reg_addr)
          3'd0: if (dlab) dll <= wdata;
          3'd1: if (dlab) dlm <= wdata;
          3'd3: lcr <= wdata;
          3'd4: mcr <= wdata;
          3'd7: scr <= wdata;
          default: begin
          end
        endcase
      end
      if (ier_write) begin
        ier <= {4'b0, wdata[3:0]};
        // turning THRE interrupts on while the transmitter is empty raises one
        if (wdata[1] && !ier[1] && !busy) thre_int <= 1;
      end

      // ---- transmit
      if (thr_write) begin
        busy <= 1;
        shift <= {1'b1, wdata, 1'b0};
        bits_left <= 10;
        clk_count <= 1;
        thre_int <= 0;
        if (ECHO) $write("%c", wdata);
      end
      else if (busy) begin
        if (clk_count == CLKS_PER_BIT) begin
          clk_count <= 1;
          shift <= {1'b1, shift[9:1]};
          bits_left <= bits_left - 1;
          if (bits_left == 1) begin
            busy <= 0;
            thre_int <= 1;
          end
        end
        else begin
          clk_count <= clk_count + 1;
        end
      end
      if (iir_read && !line_irq && !data_irq && thr_irq) thre_int <= 0;

      // ---- receive
      rx_meta <= rx;
      rx_sync <= rx_meta;
      case (rx_state)
        RX_IDLE: begin
          if (rx_wait_high) begin
            if (rx_sync) rx_wait_high <= 0;
          end
          else if (!rx_sync) begin
            rx_state <= RX_START;
            rx_count <= 1;
          end
        end
        RX_START: begin
          if (rx_count == START_CHECK) begin
            if (rx_sync) begin
              rx_state <= RX_IDLE; // a glitch, not a start bit
            end
            else begin
              rx_state <= RX_DATA;
              rx_count <= 1;
              rx_bit <= 0;
            end
          end
          else begin
            rx_count <= rx_count + 1;
          end
        end
        RX_DATA: begin
          if (rx_count == CLKS_PER_BIT) begin
            rx_shift <= {rx_sync, rx_shift[7:1]}; // lsb first
            rx_count <= 1;
            rx_bit <= rx_bit + 1;
            if (rx_bit == 3'd7) rx_state <= RX_STOP;
          end
          else begin
            rx_count <= rx_count + 1;
          end
        end
        RX_STOP: begin
          if (rx_count == CLKS_PER_BIT) begin
            rx_state <= RX_IDLE;
            rx_wait_high <= !rx_sync;
            if (!rx_sync) fe <= 1;
            if (dr && !rbr_read) begin
              oe <= 1; // the unread byte stays
            end
            else begin
              rbr <= rx_shift;
              dr <= 1;
            end
          end
          else begin
            rx_count <= rx_count + 1;
          end
        end
      endcase

      if (rbr_read && !rx_frame_done) dr <= 0;
      if (lsr_read) begin
        // an error raised on this very edge is not lost
        if (!(rx_frame_done && !rx_sync)) fe <= 0;
        if (!(rx_frame_done && dr && !rbr_read)) oe <= 0;
      end
    end
  end

endmodule
