// uart with the register layout of a 16550 (byte registers, offsets 0..7), which is what the
// linux 8250 driver and earlycon expect. 8N1 at clk / CLKS_PER_BIT baud (CLKS_PER_BIT >= 4),
// a 16550A: 16 byte transmit and receive fifos, enabled by FCR bit 0. with the fifos off it
// is a 16450 (one transmit byte, which is the shift register itself, and one receive byte).
// use compatible "ns16550a" in a device tree.
//
//   0 THR (write)  start sending a byte, dropped if a byte is still being sent
//     RBR (read)   the received byte, clears DR
//     DLL          divisor latch low while LCR bit 7 (DLAB) is set, stored only (the baud rate is fixed)
//   1 IER          bit 0 received data, bit 1 THR empty, bit 2 receiver line status (bit 3 modem, stored only)
//     DLM          divisor latch high while DLAB, stored only
//   2 IIR (read)   0x01 nothing pending, else 0x06 line status, 0x04 received data (fifo at the
//                  trigger level), 0x0C character timeout (fifo not empty and 4 character times with
//                  no traffic), 0x02 THR empty (highest first); reading it while 0x02 is reported
//                  clears that interrupt. bits 7:6 are 11 while the fifos are enabled
//     FCR (write)  bit 0 enable the fifos (changing it clears both), bit 1 clear the receive fifo,
//                  bit 2 clear the transmit fifo (the byte being shifted out still goes), bits 7:6
//                  receive trigger level 1, 4, 8 or 14 bytes
//   3 LCR, 4 MCR   read/write, stored only
//   5 LSR (read)   bit 0 DR (receive fifo not empty), bit 1 OE (overrun), bit 3 FE (framing),
//                  bit 5 THRE (transmit fifo empty, with the fifos off: not shifting), bit 6 TEMT
//                  (fifo empty and nothing shifting); OE and FE clear when read. errors are not
//                  kept per byte, they are flagged as they happen
//   6 MSR (read)   0
//   7 SCR          scratch, read/write
//
// an overrun (a byte arrives with the receive fifo full) drops the new byte and keeps the old ones. `irq` is the level
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
  reg fifo_en;
  reg [1:0] rx_trig;
  reg [7:0] txf_mem [0:15];
  reg [3:0] txf_wp;
  reg [3:0] txf_rp;
  reg [4:0] txf_n;
  reg [9:0] shift; // stop, 8 data bits, start; shifted out from bit 0
  reg [3:0] bits_left;
  reg [$clog2(CLKS_PER_BIT+1)-1:0] clk_count;

  assign tx = busy ? shift[0] : 1'b1;

  wire dlab = lcr[7];
  wire access = sel && !dlab;
  wire thr_wr = access && write && reg_addr == 3'd0;
  wire thr_direct = thr_wr && !busy && txf_n == 0; // straight into the shift register
  wire thr_push = thr_wr && fifo_en && !thr_direct && txf_n != 5'd16;
  wire txf_pop = !busy && txf_n != 0 && !thr_direct;
  wire thre = fifo_en ? (txf_n == 0) : !busy;
  wire fcr_write = sel && write && reg_addr == 3'd2;
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
  reg [7:0] rxf_mem [0:15];
  reg [3:0] rxf_wp;
  reg [3:0] rxf_rp;
  reg [4:0] rxf_n;
  reg [7:0] rbr_last; // what a read of an empty fifo returns
  localparam int TO_LIMIT = 40 * CLKS_PER_BIT; // 4 character times of 10 bits
  reg [$clog2(TO_LIMIT+1)-1:0] to_count;
  reg to_flag;
  wire dr = rxf_n != 0;
  wire [7:0] rbr = dr ? rxf_mem[rxf_rp] : rbr_last;
  wire rbr_read = access && !write && reg_addr == 3'd0;
  wire rbr_pop = rbr_read && dr;
  wire [4:0] rx_trig_n = !fifo_en ? 5'd1 : rx_trig == 2'd0 ? 5'd1 : rx_trig == 2'd1 ? 5'd4 : rx_trig == 2'd2 ? 5'd8 : 5'd14;
  wire [4:0] rxf_limit = fifo_en ? 5'd16 : 5'd1;
  reg oe;
  reg fe;

  // ---- interrupts
  reg thre_int; // transmitter became empty (or THRE interrupts were just enabled), until IIR read or THR write
  wire line_irq = ier[2] && (oe || fe);
  wire data_irq = ier[0] && rxf_n >= rx_trig_n;
  wire to_irq = ier[0] && fifo_en && to_flag;
  wire thr_irq = ier[1] && thre_int;
  wire [3:0] iir_id = line_irq ? 4'h6 : data_irq ? 4'h4 : to_irq ? 4'hC : thr_irq ? 4'h2 : 4'h1;
  wire [7:0] iir = {fifo_en, fifo_en, 2'b00, iir_id};
  assign irq = line_irq || data_irq || to_irq || thr_irq;

  always @* begin
    case (reg_addr)
      3'd0: rdata = dlab ? dll : rbr;
      3'd1: rdata = dlab ? dlm : ier;
      3'd2: rdata = iir;
      3'd3: rdata = lcr;
      3'd4: rdata = mcr;
      3'd5: rdata = {1'b0, txf_n == 0 && !busy, thre, 1'b0, fe, 1'b0, oe, dr};
      3'd7: rdata = scr;
      default: rdata = 8'h00;
    endcase
  end

  wire rx_frame_done = (rx_state == RX_STOP) && (rx_count == CLKS_PER_BIT);
  wire rxf_full = rxf_n >= rxf_limit;
  wire rxf_push = rx_frame_done && (!rxf_full || rbr_pop);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ier <= 0;
      lcr <= 0;
      mcr <= 0;
      scr <= 0;
      dll <= 0;
      dlm <= 0;
      busy <= 0;
      fifo_en <= 0;
      rx_trig <= 0;
      txf_wp <= 0;
      txf_rp <= 0;
      txf_n <= 0;
      rxf_wp <= 0;
      rxf_rp <= 0;
      rxf_n <= 0;
      rbr_last <= 0;
      to_count <= 0;
      to_flag <= 0;
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
        if (wdata[1] && !ier[1] && thre) thre_int <= 1;
      end

      // ---- transmit
      if (thr_direct || thr_push) thre_int <= 0;
      if (thr_direct || txf_pop) begin
        busy <= 1;
        shift <= {1'b1, thr_direct ? wdata : txf_mem[txf_rp], 1'b0};
        bits_left <= 10;
        clk_count <= 1;
        if (ECHO) $write("%c", thr_direct ? wdata : txf_mem[txf_rp]);
      end
      else if (busy) begin
        if (clk_count == CLKS_PER_BIT) begin
          clk_count <= 1;
          shift <= {1'b1, shift[9:1]};
          bits_left <= bits_left - 1;
          if (bits_left == 1) begin
            busy <= 0;
            if (txf_n == 0) thre_int <= 1;
          end
        end
        else begin
          clk_count <= clk_count + 1;
        end
      end
      if (txf_pop) begin
        txf_rp <= txf_rp + 1;
        if (txf_n == 1) thre_int <= 1;
      end
      if (thr_push) begin
        txf_mem[txf_wp] <= wdata;
        txf_wp <= txf_wp + 1;
      end
      txf_n <= txf_n + (thr_push ? 5'd1 : 5'd0) - (txf_pop ? 5'd1 : 5'd0);
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
            if (rxf_full && !rbr_pop) oe <= 1; // the unread bytes stay
          end
          else begin
            rx_count <= rx_count + 1;
          end
        end
      endcase

      // ---- receive fifo
      if (rxf_push) begin
        rxf_mem[rxf_wp] <= rx_shift;
        rxf_wp <= rxf_wp + 1;
      end
      if (rbr_pop) begin
        rxf_rp <= rxf_rp + 1;
        rbr_last <= rxf_mem[rxf_rp];
      end
      rxf_n <= rxf_n + (rxf_push ? 5'd1 : 5'd0) - (rbr_pop ? 5'd1 : 5'd0);

      // ---- character timeout: the fifo holds data and nothing arrived or was read for 4 characters
      if (rxf_push || rbr_pop || rxf_n == 0) begin
        to_count <= 0;
        to_flag <= 0;
      end
      else if (to_count == TO_LIMIT) begin
        to_flag <= 1;
      end
      else begin
        to_count <= to_count + 1;
      end

      if (lsr_read) begin
        // an error raised on this very edge is not lost
        if (!(rx_frame_done && !rx_sync)) fe <= 0;
        if (!(rx_frame_done && rxf_full && !rbr_pop)) oe <= 0;
      end

      // ---- fifo control (last, so a clear wins over the updates above)
      if (fcr_write) begin
        fifo_en <= wdata[0];
        if (wdata[0]) rx_trig <= wdata[7:6];
        if (wdata[0] != fifo_en || wdata[1]) begin
          rxf_wp <= 0;
          rxf_rp <= 0;
          rxf_n <= 0;
        end
        if (wdata[0] != fifo_en || wdata[2]) begin
          txf_wp <= 0;
          txf_rp <= 0;
          txf_n <= 0;
        end
      end
    end
  end

endmodule
