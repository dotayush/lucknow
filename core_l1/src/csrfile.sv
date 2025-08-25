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
    input wire [3:0] trap_cause,
    input wire [DATA_WIDTH-1:0] trap_value,
    input wire [DATA_WIDTH-1:0] trap_pc,
    output reg trap_handled,
    output reg [DATA_WIDTH-1:0] trap_target_pc // 31 ~ 2 + 00 (word aligned)
);

  reg [DATA_WIDTH-1:0] csr_array [0:COUNT-1];

  function automatic logic is_writeable(input [11:0] addr);
    case (addr)
      CSR_MVENDORID, CSR_MARCHID, CSR_MIMPID, CSR_MHARTID, CSR_ISA: is_writeable = 1'b0; // read-only
      default: is_writeable = 1'b1; // read-write
    endcase
  endfunction

  always @(posedge clk or negedge rst_n) begin
    trap_target_pc <= 'b0;
    trap_handled <= 0;
    if (!rst_n) begin
      for (int i = 0; i < COUNT; i = i + 1) begin
        case (i)
          CSR_MVENDORID: csr_array[i] = 32'h00000000;
          CSR_MARCHID: csr_array[i] = 32'h00000000;
          CSR_MIMPID: csr_array[i] = 32'h00000000;
          CSR_MHARTID: csr_array[i] = 32'h00000000;
          CSR_ISA: csr_array[i] = 32'h40001100; // 32-bit (31:30), RV32I (bit 8), M (bit 12)
          CSR_MTVEC: csr_array[i] = 32'h00000000; // default trap vector
          CSR_MSTATUS: csr_array[i] = 32'h00001800; // MPP = 11 (M-mode), MPIE = 0, MIE = 0
          default: csr_array[i] = 'b0;
        endcase
      end
      csr_rdata <= 'b0;
      trap_handled <= 0;
      trap_target_pc <= 'b0;
    end
    else begin
      if (trap) begin
        csr_array[CSR_MEPC] <= trap_pc;
        csr_array[CSR_MCAUSE] <= {28'b0, trap_cause}; // assuming 4-bit cause
        csr_array[CSR_MTVAL] <= trap_value;
        trap_target_pc <= csr_array[CSR_MTVEC] & 32'hFFFFFFFC; // align to word boundary
        trap_handled <= 1;

        // update mstatus to reflect trap
        csr_array[CSR_MSTATUS][7] <= csr_array[CSR_MSTATUS][3]; // MPIE = MIE
        csr_array[CSR_MSTATUS][3] <= 0; // MIE = 0/
        csr_array[CSR_MSTATUS][12:11] <= 2'b11; // MPP = M-mode (11)
      end
      else begin
        trap_handled <= 0; // reset trap handled flag
        if (is_writeable(csr_addr)) begin
          case (csr_op)
            CSR_WRITE: begin
              csr_array[csr_addr] <= csr_wdata;
            end
            CSR_SET: begin
              csr_array[csr_addr] <= csr_array[csr_addr] | csr_wdata;
            end
            CSR_CLEAR: begin
              csr_array[csr_addr] <= csr_array[csr_addr] & ~csr_wdata;
            end
            default: begin
            end
          endcase
        end
      end
      csr_array[CSR_MCYCLE] <= csr_array[CSR_MCYCLE] + 1; // increment cycle counter
    end
  end

  always @* begin
    csr_rdata = csr_array[csr_addr];
  end

endmodule
