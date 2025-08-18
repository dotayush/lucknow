module regfile #(parameter DATA_WIDTH = 32) (
    input wire clk,
    input wire rst_n,

    // reads
    input wire [$clog2(DATA_WIDTH)-1:0] rs1,
    input wire [$clog2(DATA_WIDTH)-1:0] rs2,
    output reg [DATA_WIDTH-1:0] rs1_data,
    output reg [DATA_WIDTH-1:0] rs2_data,

    // writes
    input wire write_enable,
    input wire [$clog2(DATA_WIDTH)-1:0] rd,
    input wire [DATA_WIDTH-1:0] rd_data
);
  localparam int REG_COUNT = 32; // 32 registers
  reg [DATA_WIDTH-1:0] regs [0:REG_COUNT-1]; // register array

  // read logic
  always_comb begin
      rs1_data = regs[rs1];
      rs2_data = regs[rs2];
  end

  // write logic
  always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin // pull low for reset
          for (int i = 0; i < REG_COUNT; i = i + 1) begin
              regs[i] <= 0; // reset to zero
          end
      end
      else if (write_enable && rd != 0) begin // avoid writing to x0 as per RISC-V spec
          regs[rd] <= rd_data;
      end
  end
endmodule

