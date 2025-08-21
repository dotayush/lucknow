`ifndef ISA_SHARED_IMPORT
  `define ISA_SHARED_IMPORT
  import isa_shared::*;
`endif

module memory #(
  parameter int WORDS = 64,
  parameter int DATA_WIDTH = 32,
  parameter string MEM_INIT = ""
)(
  input  wire                     clk,
  input  wire                     rst_n,
  input  wire                     mem_write,
  input  wire                     mem_read,
  input  wire [1:0]               mem_access_type,
  input  wire [DATA_WIDTH-1:0]    addr,
  input  wire [DATA_WIDTH-1:0]    data_in,
  output reg  [DATA_WIDTH-1:0]    data_out
);

  localparam int ADDR_WIDTH = $clog2(WORDS);

  reg [DATA_WIDTH-1:0] mem [0:WORDS-1];
  reg mem_aligned;

  integer i;
  initial begin
    if (MEM_INIT != "") begin
      $readmemh(MEM_INIT, mem);
    end
    else begin
      for (i = 0; i < WORDS; i = i + 1) mem[i] = '0;
    end
    mem_aligned = 1'b1;
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      for (i = 0; i < WORDS; i = i + 1) mem[i] <= '0;
    end
    else if (mem_write) begin
      // compute truncated physical address and OOB
      reg [DATA_WIDTH-1:0] paddr_w;
      reg                 oob_w;
      paddr_w = {{(DATA_WIDTH-ADDR_WIDTH){1'b0}}, addr[ADDR_WIDTH-1:0]};
      oob_w   = (addr[DATA_WIDTH-1:2] >= WORDS);

      if (oob_w) begin
        $strobe("[%0t] error (write): addr=%h out of bounds, wrapping=%h, mem_access_type=%b", $time, addr, paddr_w, mem_access_type);
        mem[paddr_w[DATA_WIDTH-1:2]] <= data_in;
      end
      else begin
        if (!mem_aligned) begin
          $strobe("[%0t] error (write): addr=%h not aligned, mem_access_type=%b", $time, addr, mem_access_type);
        end
        else begin
          mem[addr[DATA_WIDTH-1:2]] <= data_in;
        end
      end
    end
  end

  always @* begin
    case (mem_access_type)
      2'b10: mem_aligned = (addr[1:0] == 2'b00); // word
      2'b01: mem_aligned = (addr[0]   == 1'b0 ); // half
      default: mem_aligned = 1'b1;               // byte & default
    endcase

    data_out = '0;
    if (!mem_read) begin
    end
    else begin
      reg [DATA_WIDTH-1:0] paddr_r;
      reg                 oob_r;
      paddr_r = {{(DATA_WIDTH-ADDR_WIDTH){1'b0}}, addr[ADDR_WIDTH-1:0]};
      oob_r   = (addr[DATA_WIDTH-1:2] >= WORDS);

      if (oob_r) begin
        $strobe("[%0t] error (read): addr=%h out of bounds, wrapping=%h, mem_access_type=%b", $time, addr, paddr_r, mem_access_type);
        data_out = mem[paddr_r[DATA_WIDTH-1:2]];
      end
      else begin
        if (!mem_aligned) begin
          $strobe("[%0t] error (read): addr=%h not aligned, mem_access_type=%b", $time, addr, mem_access_type);
          data_out = '0;
        end
        else begin
          data_out = mem[addr[DATA_WIDTH-1:2]];
        end
      end
    end
  end

endmodule
