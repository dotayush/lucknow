`ifndef ISA_SHARED_IMPORT
  `define ISA_SHARED_IMPORT
  import isa_shared::*;
`endif


module csrfile #(parameter DATA_WIDTH = 32, COUNT = 4096) (
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
    output wire mtvec_vectored, // mtvec mode 1: interrupts go to trap_vector + 4 * code

    // interrupts, from the outside world
    input wire irq_software, // clint msip
    input wire irq_timer, // clint mtip
    input wire irq_external, // plic meip
    output wire irq_pending, // an enabled interrupt is pending and mstatus.MIE is set: take it now
    output wire [3:0] irq_code,

    // counters
    input wire [63:0] time_value, // read through time/timeh
    input wire retire // an instruction completes this cycle (minstret)
);

  localparam [11:0] IRQ_SOFTWARE = 12'h008; // mip/mie bit 3
  localparam [11:0] IRQ_TIMER = 12'h080; // mip/mie bit 7
  localparam [11:0] IRQ_EXTERNAL = 12'h800; // mip/mie bit 11
  localparam [DATA_WIDTH-1:0] MIE_MASK = 32'h0000_0888;
  localparam [DATA_WIDTH-1:0] MSTATUS_MASK = 32'h0000_0088; // writable: MIE (bit 3), MPIE (bit 7)
  localparam [DATA_WIDTH-1:0] MSTATUS_MPP_M = 32'h0000_1800;

  reg [DATA_WIDTH-1:0] csr_array [0:COUNT-1];
  reg [63:0] cycle;
  reg [63:0] instret;

  function automatic logic is_writeable(input [11:0] addr);
    case (addr)
      CSR_MVENDORID, CSR_MARCHID, CSR_MIMPID, CSR_MHARTID, CSR_ISA: is_writeable = 1'b0; // read-only
      CSR_CYCLE, CSR_TIME, CSR_INSTRET, CSR_CYCLEH, CSR_TIMEH, CSR_INSTRETH: is_writeable = 1'b0; // read-only
      default: is_writeable = 1'b1; // read-write
    endcase
  endfunction

  assign trap_vector = csr_array[CSR_MTVEC] & 32'hFFFFFFFC; // exceptions always go to the base address
  assign mtvec_vectored = csr_array[CSR_MTVEC][0];

  // mip has no storage: it is what the outside world says
  wire [DATA_WIDTH-1:0] mip = (irq_software ? IRQ_SOFTWARE : 0) | (irq_timer ? IRQ_TIMER : 0) | (irq_external ? IRQ_EXTERNAL : 0);
  wire [DATA_WIDTH-1:0] enabled = mip & csr_array[CSR_MIE];
  assign irq_pending = csr_array[CSR_MSTATUS][3] && (enabled != 0);
  // priority among machine level interrupts: external, software, timer
  assign irq_code = (enabled & IRQ_EXTERNAL) ? 4'd11 : (enabled & IRQ_SOFTWARE) ? 4'd3 : 4'd7;

  always @* begin
    case (csr_addr)
      CSR_MIP: csr_rdata = mip;
      CSR_MCYCLE, CSR_CYCLE: csr_rdata = cycle[31:0];
      CSR_MCYCLEH, CSR_CYCLEH: csr_rdata = cycle[63:32];
      CSR_MINSTRET, CSR_INSTRET: csr_rdata = instret[31:0];
      CSR_MINSTRETH, CSR_INSTRETH: csr_rdata = instret[63:32];
      CSR_TIME: csr_rdata = time_value[31:0];
      CSR_TIMEH: csr_rdata = time_value[63:32];
      default: csr_rdata = csr_array[csr_addr];
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
      for (int i = 0; i < COUNT; i = i + 1) begin
        case (i)
          CSR_MVENDORID: csr_array[i] <= 32'h00000000;
          CSR_MARCHID: csr_array[i] <= 32'h00000000;
          CSR_MIMPID: csr_array[i] <= 32'h00000000;
          CSR_MHARTID: csr_array[i] <= 32'h00000000;
          CSR_ISA: csr_array[i] <= 32'h40001101; // 32-bit (31:30), RV32I (bit 8), M (bit 12), A (bit 0)
          CSR_MTVEC: csr_array[i] <= 32'h00000000; // default trap vector
          CSR_MSTATUS: csr_array[i] <= 32'h00001800; // MPP = 11 (M-mode), MPIE = 0, MIE = 0
          default: csr_array[i] <= 'b0;
        endcase
      end
    end
    else begin
      if (!cycle_written) cycle <= cycle + 1;
      if (retire && !instret_written) instret <= instret + 1;

      if (trap) begin
        csr_array[CSR_MEPC] <= trap_pc;
        csr_array[CSR_MCAUSE] <= {trap_interrupt, 27'b0, trap_cause};
        csr_array[CSR_MTVAL] <= trap_value;

        // update mstatus to reflect trap
        csr_array[CSR_MSTATUS][7] <= csr_array[CSR_MSTATUS][3]; // MPIE = MIE
        csr_array[CSR_MSTATUS][3] <= 0; // MIE = 0
        csr_array[CSR_MSTATUS][12:11] <= 2'b11; // MPP = M-mode (11)
      end
      else if (mret) begin
        csr_array[CSR_MSTATUS][3] <= csr_array[CSR_MSTATUS][7]; // MIE = MPIE
        csr_array[CSR_MSTATUS][7] <= 1; // MPIE = 1
        csr_array[CSR_MSTATUS][12:11] <= 2'b11; // MPP = M-mode (11), the only supported mode
      end
      else if (do_write) begin
        case (csr_addr)
          CSR_MCYCLE: cycle[31:0] <= wr_val; // a write wins over the count
          CSR_MCYCLEH: cycle[63:32] <= wr_val;
          CSR_MINSTRET: instret[31:0] <= wr_val;
          CSR_MINSTRETH: instret[63:32] <= wr_val;
          CSR_MIP: begin
          end // every implemented bit is a hardware input
          CSR_MIE: csr_array[CSR_MIE] <= wr_val & MIE_MASK;
          CSR_MTVEC: csr_array[CSR_MTVEC] <= wr_val & ~32'h2; // mode is 0 (direct) or 1 (vectored)
          CSR_MSTATUS: csr_array[CSR_MSTATUS] <= (wr_val & MSTATUS_MASK) | MSTATUS_MPP_M; // only M-mode exists: MPP reads 11
          default: csr_array[csr_addr] <= wr_val;
        endcase
      end
    end
  end

endmodule
