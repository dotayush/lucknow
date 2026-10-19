`ifndef ISA_SHARED_IMPORT
  `define ISA_SHARED_IMPORT
  import isa_shared::*;
`endif


// only the CSRs that something uses are built, as named registers. Any other address reads 0 and
// ignores writes (WARL), instead of a 4096 word array that no chip would want to pay for.
// implemented: mstatus mie mip mtvec mscratch mepc mcause mtval mcycle mcounteren pmpaddr0,
// constants: misa mvendorid marchid mimpid mhartid.
module csrfile #(parameter DATA_WIDTH = 32) (
    input wire clk,
    input wire rst_n,

    // access interface
    input wire [11:0] csr_addr,
    input wire [DATA_WIDTH-1:0] csr_wdata,
    output reg [DATA_WIDTH-1:0] csr_rdata,
    input wire [1:0] csr_op,

    // trap inputs
    input wire trap,
    input wire trap_pre, // trap known from the instruction alone (see control.sv)
    input wire mem_fault, // load or store refused by the memory: trap is trap_pre, mem_fault or a taken branch to a misaligned target
    input wire [3:0] trap_cause,
    input wire [DATA_WIDTH-1:0] trap_value,
    input wire [DATA_WIDTH-1:0] trap_pc,
    input wire mret, // return from trap: restores the interrupt enable stack in mstatus
    output wire [DATA_WIDTH-1:0] trap_vector // address of the trap handler, 31 ~ 2 + 00 (word aligned)
);

  localparam [11:0] CSR_MSCRATCH = 12'h340;
  localparam [11:0] CSR_MCOUNTEREN = 12'h306;
  localparam [11:0] CSR_PMPADDR0 = 12'h3B0; // storage only, no protection; riscv-tests pmpaddr probes it

  reg [DATA_WIDTH-1:0] mstatus, mie, mip, mtvec, mscratch, mepc, mcause, mtval, mcycle, mcounteren, pmpaddr0;

  assign trap_vector = mtvec & 32'hFFFFFFFC; // exceptions always go to the base address

  // value after the csr instruction's operation, applied to whichever register csr_addr selects
  function automatic [DATA_WIDTH-1:0] apply(input [DATA_WIDTH-1:0] old);
    case (csr_op)
      CSR_WRITE: apply = csr_wdata;
      CSR_SET: apply = old | csr_wdata;
      CSR_CLEAR: apply = old & ~csr_wdata;
      default: apply = old;
    endcase
  endfunction

  always @* begin
    case (csr_addr)
      CSR_MSTATUS: csr_rdata = mstatus;
      CSR_ISA: csr_rdata = 32'h40000100; // 32-bit (31:30), RV32I (bit 8)
      CSR_MIE: csr_rdata = mie;
      CSR_MIP: csr_rdata = mip;
      CSR_MTVEC: csr_rdata = mtvec;
      CSR_MSCRATCH: csr_rdata = mscratch;
      CSR_MEPC: csr_rdata = mepc;
      CSR_MCAUSE: csr_rdata = mcause;
      CSR_MTVAL: csr_rdata = mtval;
      CSR_MCYCLE: csr_rdata = mcycle;
      CSR_MCOUNTEREN: csr_rdata = mcounteren;
      CSR_PMPADDR0: csr_rdata = pmpaddr0;
      default: csr_rdata = '0; // mvendorid marchid mimpid mhartid are 0, so is anything not built
    endcase
  end

  // what a trap changes: the trap record and mstatus. these see the full `trap`, which for a taken branch to a
  // misaligned target is known late (it follows the branch compare).
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mstatus <= 32'h00001800; // MPP = 11 (M-mode), MPIE = 0, MIE = 0
      mepc <= '0;
      mcause <= '0;
      mtval <= '0;
      mcycle <= '0;
    end
    else begin
      if (trap) begin
        mepc <= trap_pc;
        mcause <= {28'b0, trap_cause}; // assuming 4-bit cause
        mtval <= trap_value;
        mstatus[7] <= mstatus[3]; // MPIE = MIE
        mstatus[3] <= 0; // MIE = 0
        mstatus[12:11] <= 2'b11; // MPP = M-mode (11)
      end
      else if (mret) begin
        mstatus[3] <= mstatus[7]; // MIE = MPIE
        mstatus[7] <= 1; // MPIE = 1
        mstatus[12:11] <= 2'b11; // MPP = M-mode (11), the only supported mode
      end
      else begin
        case (csr_addr)
          CSR_MSTATUS: mstatus <= apply(mstatus);
          CSR_MEPC: mepc <= apply(mepc);
          CSR_MCAUSE: mcause <= apply(mcause);
          CSR_MTVAL: mtval <= apply(mtval);
          default: begin end
        endcase
      end
      mcycle <= mcycle + 1; // every clock; a csr write to it is overridden, as before
    end
  end

  // the registers a trap does not touch. they are written only by csr instructions, and a late trap (a taken
  // branch) never comes with one, so their write enable uses trap_pre and mem_fault (last) and stays off the late path.
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mie <= '0;
      mip <= '0;
      mtvec <= '0;
      mscratch <= '0;
      mcounteren <= '0;
      pmpaddr0 <= '0;
    end
    else if (!trap_pre && !mret && !mem_fault) begin
      case (csr_addr)
        CSR_MIE: mie <= apply(mie);
        CSR_MIP: mip <= apply(mip);
        CSR_MTVEC: mtvec <= apply(mtvec);
        CSR_MSCRATCH: mscratch <= apply(mscratch);
        CSR_MCOUNTEREN: mcounteren <= apply(mcounteren);
        CSR_PMPADDR0: pmpaddr0 <= apply(pmpaddr0);
        default: begin end // read only or not built
      endcase
    end
  end

endmodule
