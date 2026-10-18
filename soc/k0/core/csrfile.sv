`ifndef ISA_SHARED_IMPORT
  `define ISA_SHARED_IMPORT
  import isa_shared::*;
`endif


// only the CSRs that exist are built, as named registers; any other address reads 0 and ignores writes.
module csrfile #(parameter DATA_WIDTH = 32, PMP_ENTRIES = 8, HPM_COUNTERS = 8) (
    input wire clk,
    input wire rst_n,

    // access interface
    input wire [11:0] csr_addr,
    input wire [DATA_WIDTH-1:0] csr_wdata,
    output reg [DATA_WIDTH-1:0] csr_rdata,
    input wire [1:0] csr_op,

    // trap inputs
    input wire trap,
    input wire trap_interrupt, // the trap is an interrupt, trap_cause is its code
    input wire [3:0] trap_cause,
    input wire [DATA_WIDTH-1:0] trap_value,
    input wire [DATA_WIDTH-1:0] trap_pc,
    input wire mret, // return from trap: restores the interrupt enable stack in mstatus
    output wire [DATA_WIDTH-1:0] trap_vector, // address of the trap handler, 31 ~ 2 + 00 (word aligned)
    output wire priv_user, // the hart is in user mode (otherwise machine mode)
    output wire [DATA_WIDTH-1:0] mcounteren, // which counters user mode may read
    output wire [PMP_ENTRIES*8-1:0] pmp_cfg, // pmpcfg bytes, entry 0 lowest
    output wire [PMP_ENTRIES*32-1:0] pmp_addr,
    output wire mtvec_vectored, // mtvec mode 1: interrupts go to trap_vector + 4 * code

    // interrupts, from the outside world
    input wire irq_software, // clint msip
    input wire irq_timer, // clint mtip
    input wire irq_external, // plic meip
    output wire irq_pending, // an enabled interrupt is pending and mstatus.MIE is set: take it now
    output wire [3:0] irq_code,

    // counters. hpm_events[1..15] are one clock pulses of things worth counting, hpm_events[0] is unused
    input wire [15:0] hpm_events,
    input wire [63:0] time_value, // read through time/timeh
    input wire retire // an instruction completes this cycle (minstret)
);

  localparam [11:0] IRQ_SOFTWARE = 12'h008; // mip/mie bit 3
  localparam [11:0] IRQ_TIMER = 12'h080; // mip/mie bit 7
  localparam [11:0] IRQ_EXTERNAL = 12'h800; // mip/mie bit 11
  localparam [DATA_WIDTH-1:0] MIE_MASK = 32'h0000_0888;
  localparam [DATA_WIDTH-1:0] MSTATUS_MASK = 32'h0000_0088; // writable: MIE (bit 3), MPIE (bit 7)
  localparam [DATA_WIDTH-1:0] MSTATUS_MPP_M = 32'h0000_1800;
  localparam [11:0] CSR_MSCRATCH = 12'h340;

  reg [DATA_WIDTH-1:0] mstatus, mie, mtvec, mscratch, mepc, mcause, mtval, mcounteren_q;
  reg [63:0] cycle;
  reg user; // 1: user mode, 0: machine mode
  reg [63:0] instret;

  // zihpm: HPM_COUNTERS event counters (mhpmcounter3.., 64 bit), each counts the pulses of the event its
  // mhpmevent register selects (0 counts nothing). mcountinhibit stops a counter, bit 0 cycle, bit 2 instret.
  // a counter that is not implemented reads as zero and ignores writes.
  localparam [31:0] INHIBIT_MASK = 32'h0000_0005 | (((32'd1 << HPM_COUNTERS) - 32'd1) << 3);
  localparam [31:0] COUNTEREN_MASK = 32'h0000_0007 | (((32'd1 << HPM_COUNTERS) - 32'd1) << 3);
  reg [63:0] hpm [0:HPM_COUNTERS-1];
  reg [3:0] hpm_event [0:HPM_COUNTERS-1]; // event number 1..15
  reg [31:0] mcountinhibit;
  wire [4:0] hpm_n = csr_addr[4:0]; // which counter, for the csr ranges below (3..31 are the event counters)
  wire hpm_hit = (hpm_n >= 5'd3) && ({27'b0, hpm_n} - 32'd3 < HPM_COUNTERS);
  wire [4:0] hpm_i = hpm_n - 5'd3;
  wire hpm_lo = hpm_hit && (csr_addr[11:5] == 7'h58 || csr_addr[11:5] == 7'h60); // mhpmcounter, hpmcounter
  wire hpm_hi = hpm_hit && (csr_addr[11:5] == 7'h5C || csr_addr[11:5] == 7'h64); // the high halves
  wire hpm_evsel = hpm_hit && (csr_addr[11:5] == 7'h19); // mhpmevent3..
  wire hpm_range = (hpm_n >= 5'd3) && (csr_addr[11:5] == 7'h58 || csr_addr[11:5] == 7'h5C || csr_addr[11:5] == 7'h60 ||
                                       csr_addr[11:5] == 7'h64 || csr_addr[11:5] == 7'h19); // all 29 of each kind

  // pmp: entries 0 to PMP_ENTRIES-1 (at most 16). the others read as zero and ignore writes. a locked entry
  // ignores writes to its pmpcfg byte and its pmpaddr, and so does the pmpaddr below a locked TOR entry
  reg [7:0] pmpcfg [0:15];
  reg [31:0] pmpaddr [0:15];
  genvar gi;
  generate
    for (gi = 0; gi < PMP_ENTRIES; gi = gi + 1) begin : g_pmp
      assign pmp_cfg[gi*8 +: 8] = pmpcfg[gi];
      assign pmp_addr[gi*32 +: 32] = pmpaddr[gi];
    end
  endgenerate
  wire [3:0] pmp_idx = csr_addr[3:0];
  wire pmp_addr_locked = pmpcfg[pmp_idx][7] || (pmp_idx != 4'd15 && pmpcfg[pmp_idx + 4'd1][7] && pmpcfg[pmp_idx + 4'd1][4:3] == 2'b01);

  function automatic logic is_writeable(input [11:0] addr);
    case (addr)
      CSR_MVENDORID, CSR_MARCHID, CSR_MIMPID, CSR_MHARTID, CSR_ISA: is_writeable = 1'b0; // read-only
      CSR_CYCLE, CSR_TIME, CSR_INSTRET, CSR_CYCLEH, CSR_TIMEH, CSR_INSTRETH: is_writeable = 1'b0; // read-only
      default: is_writeable = (addr[11:5] != 7'h60) && (addr[11:5] != 7'h64); // hpmcounter3..31 and their high halves are read-only
    endcase
  endfunction

  assign trap_vector = mtvec & 32'hFFFFFFFC; // exceptions always go to the base address
  assign mtvec_vectored = mtvec[0];
  assign mcounteren = mcounteren_q;
  assign priv_user = user;

  // mip has no storage: it is what the outside world says
  wire [DATA_WIDTH-1:0] mip = (irq_software ? IRQ_SOFTWARE : 0) | (irq_timer ? IRQ_TIMER : 0) | (irq_external ? IRQ_EXTERNAL : 0);
  wire [DATA_WIDTH-1:0] enabled = mip & mie;
  // an interrupt for a higher privilege level is enabled whatever mstatus.MIE says: in user mode machine interrupts always are
  assign irq_pending = (mstatus[3] || priv_user) && (enabled != 0);
  // priority among machine level interrupts: external, software, timer
  assign irq_code = (enabled & IRQ_EXTERNAL) ? 4'd11 : (enabled & IRQ_SOFTWARE) ? 4'd3 : 4'd7;

  always @* begin
    case (csr_addr)
      CSR_MIP: csr_rdata = mip;
      CSR_MSTATUS: csr_rdata = mstatus;
      CSR_ISA: csr_rdata = 32'h40101101; // 32-bit (31:30), RV32I (bit 8), M (bit 12), A (bit 0), U (bit 20)
      CSR_MIE: csr_rdata = mie;
      CSR_MTVEC: csr_rdata = mtvec;
      CSR_MSCRATCH: csr_rdata = mscratch;
      CSR_MEPC: csr_rdata = mepc;
      CSR_MCAUSE: csr_rdata = mcause;
      CSR_MTVAL: csr_rdata = mtval;
      CSR_MCOUNTEREN: csr_rdata = mcounteren_q;
      CSR_MCYCLE, CSR_CYCLE: csr_rdata = cycle[31:0];
      CSR_MCYCLEH, CSR_CYCLEH: csr_rdata = cycle[63:32];
      CSR_MINSTRET, CSR_INSTRET: csr_rdata = instret[31:0];
      CSR_MINSTRETH, CSR_INSTRETH: csr_rdata = instret[63:32];
      CSR_TIME: csr_rdata = time_value[31:0];
      CSR_TIMEH: csr_rdata = time_value[63:32];
      CSR_MCOUNTINHIBIT: csr_rdata = mcountinhibit;
      12'h3A0, 12'h3A1, 12'h3A2, 12'h3A3: csr_rdata = {pmpcfg[{csr_addr[1:0], 2'd3}], pmpcfg[{csr_addr[1:0], 2'd2}],
                                                       pmpcfg[{csr_addr[1:0], 2'd1}], pmpcfg[{csr_addr[1:0], 2'd0}]};
      default: begin
        if (csr_addr[11:4] == 8'h3B) csr_rdata = pmpaddr[pmp_idx];
        else if (hpm_lo) csr_rdata = hpm[hpm_i][31:0];
        else if (hpm_hi) csr_rdata = hpm[hpm_i][63:32];
        else if (hpm_evsel) csr_rdata = {28'b0, hpm_event[hpm_i]};
        else if (hpm_range) csr_rdata = 32'h0; // not implemented
        else csr_rdata = 32'h0; // mvendorid marchid mimpid mhartid are 0, so is anything not built
      end
    endcase
  end

  // the value a csr instruction writes (csr_op already applied to what is read)
  logic [DATA_WIDTH-1:0] wr_val;
  always @* begin
    case (csr_op)
      CSR_SET: wr_val = csr_rdata | csr_wdata;
      CSR_CLEAR: wr_val = csr_rdata & ~csr_wdata;
      default: wr_val = csr_wdata;
    endcase
  end

  wire do_write = (csr_op != CSR_NOP) && is_writeable(csr_addr);
  // a write to either half of a counter replaces the whole counter, the increment of that cycle is dropped
  wire cycle_written = do_write && (csr_addr == CSR_MCYCLE || csr_addr == CSR_MCYCLEH);
  wire instret_written = do_write && (csr_addr == CSR_MINSTRET || csr_addr == CSR_MINSTRETH);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cycle <= 64'd0;
      instret <= 64'd0;
      user <= 0;
      mcountinhibit <= 0;
      for (int h = 0; h < HPM_COUNTERS; h = h + 1) begin
        hpm[h] <= 64'd0;
        hpm_event[h] <= (h < 15) ? h + 1 : 4'd0; // counter 3 + h counts event 1 + h until reprogrammed
      end
      for (int j = 0; j < 16; j = j + 1) begin
        pmpcfg[j] <= 8'h00;
        pmpaddr[j] <= 32'h0;
      end
      mstatus <= 32'h00001800; // MPP = 11 (M-mode), MPIE = 0, MIE = 0
      mie <= 32'h0;
      mtvec <= 32'h0; // default trap vector
      mscratch <= 32'h0;
      mepc <= 32'h0;
      mcause <= 32'h0;
      mtval <= 32'h0;
      mcounteren_q <= COUNTEREN_MASK; // user mode may read every counter (linux's m-mode build never writes it)
    end
    else begin
      if (!cycle_written && !mcountinhibit[0]) cycle <= cycle + 1;
      if (retire && !instret_written && !mcountinhibit[2]) instret <= instret + 1;
      for (int h = 0; h < HPM_COUNTERS; h = h + 1) begin
        if (!mcountinhibit[h + 3] && hpm_event[h] != 4'd0 && hpm_events[hpm_event[h]]) hpm[h] <= hpm[h] + 64'd1;
      end

      if (trap) begin
        mepc <= trap_pc;
        mcause <= {trap_interrupt, 27'b0, trap_cause};
        mtval <= trap_value;

        // update mstatus to reflect trap
        mstatus[7] <= mstatus[3]; // MPIE = MIE
        mstatus[3] <= 0; // MIE = 0
        mstatus[12:11] <= user ? 2'b00 : 2'b11; // MPP = the mode the trap came from
        user <= 0;
      end
      else if (mret) begin
        mstatus[3] <= mstatus[7]; // MIE = MPIE
        mstatus[7] <= 1; // MPIE = 1
        mstatus[12:11] <= 2'b00; // MPP = the least privileged mode, user
        user <= (mstatus[12:11] != 2'b11);
      end
      else if (do_write) begin
        case (csr_addr)
          CSR_MCYCLE: cycle[31:0] <= wr_val; // a write wins over the count
          CSR_MCYCLEH: cycle[63:32] <= wr_val;
          CSR_MINSTRET: instret[31:0] <= wr_val;
          CSR_MINSTRETH: instret[63:32] <= wr_val;
          CSR_MIP: begin
          end // every implemented bit is a hardware input
          CSR_MIE: mie <= wr_val & MIE_MASK;
          CSR_MSCRATCH: mscratch <= wr_val;
          CSR_MEPC: mepc <= wr_val;
          CSR_MCAUSE: mcause <= wr_val;
          CSR_MTVAL: mtval <= wr_val;
          CSR_MCOUNTEREN: mcounteren_q <= wr_val & COUNTEREN_MASK;
          CSR_MCOUNTINHIBIT: mcountinhibit <= wr_val & INHIBIT_MASK;
          CSR_MTVEC: mtvec <= wr_val & ~32'h2; // mode is 0 (direct) or 1 (vectored)
          CSR_MSTATUS: mstatus <= (wr_val & MSTATUS_MASK) | ((wr_val[12:11] == 2'b11) ? MSTATUS_MPP_M : 0); // MPP is user (00) or machine (11)
          12'h3A0, 12'h3A1, 12'h3A2, 12'h3A3: begin
            for (int k = 0; k < 4; k = k + 1) begin
              if ({csr_addr[1:0], 2'd0} + k < PMP_ENTRIES && !pmpcfg[{csr_addr[1:0], 2'd0} + k][7]) begin
                // W without R is reserved: drop W; bits 6:5 are zero
                pmpcfg[{csr_addr[1:0], 2'd0} + k] <= {wr_val[8*k+7], 2'b00, wr_val[8*k+3 +: 2], wr_val[8*k+2],
                                                       wr_val[8*k+1] && wr_val[8*k], wr_val[8*k]};
              end
            end
          end
          default: begin
            if (csr_addr[11:4] == 8'h3B) begin
              if (pmp_idx < PMP_ENTRIES && !pmp_addr_locked) pmpaddr[pmp_idx] <= wr_val;
            end
            else if (hpm_lo) hpm[hpm_i][31:0] <= wr_val; // a write wins over the count
            else if (hpm_hi) hpm[hpm_i][63:32] <= wr_val;
            else if (hpm_evsel) hpm_event[hpm_i] <= (wr_val[4] ? 4'd0 : wr_val[3:0]); // events above 15 are not there
          end
        endcase
      end
    end
  end

endmodule
