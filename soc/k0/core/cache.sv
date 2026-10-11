`ifndef ISA_SHARED_IMPORT
  `define ISA_SHARED_IMPORT
  import isa_shared::*;
`endif

module cache #(
  parameter int CACHE_SIZE = 128,
  parameter int DATA_WIDTH = 32,
  parameter MEM_INIT = ""
)(
  input  wire                     clk,
  input  wire                     rst_n,
  input  wire                     mem_write,
  input  wire                     mem_read,
  input  wire [1:0]               mem_access_type,
  input  wire [DATA_WIDTH-1:0]    addr,
  input  wire [DATA_WIDTH-1:0]    data_in,
  output reg  [DATA_WIDTH-1:0]    data_out,
  output reg  [1:0]               mem_error
);

  localparam int INDEX_WIDTH = $clog2(CACHE_SIZE);

  reg [DATA_WIDTH-1:0] mem [0:CACHE_SIZE-1];
  reg mem_aligned;

  wire [INDEX_WIDTH-1:0] word_index = addr[INDEX_WIDTH+1:2];
  wire out_of_bounds = (addr[DATA_WIDTH-1:2] >= CACHE_SIZE);
  wire [4:0] lane_shift = {addr[1:0], 3'b000}; // bit offset of the addressed byte inside its word

  // power-on and reset state: the preloaded image if there is one, zeros otherwise.
  task automatic restore;
    integer i;
    begin
      if (MEM_INIT != "") begin
        $readmemh(MEM_INIT, mem);
      end
      else begin
        for (i = 0; i < CACHE_SIZE; i = i + 1) mem[i] = '0;
      end
    end
  endtask

  initial restore();

  always @* begin
    case (mem_access_type)
      WORD_MEM_ACCESS: mem_aligned = (addr[1:0] == 2'b00);
      HALF_MEM_ACCESS: mem_aligned = (addr[0] == 1'b0);
      default: mem_aligned = 1'b1; // byte & default
    endcase
  end

  // a faulting access neither reads nor writes
  always @* begin
    mem_error = NO_MEM_ERROR;
    if (mem_read || mem_write) begin
      if (out_of_bounds) mem_error = OUT_OF_BOUNDS;
      else if (!mem_aligned) mem_error = ADDRESS_MISALIGNED;
    end
  end

  // sub-word reads return the addressed lane, zero-extended; the consumer sign-extends.
  always @* begin
    data_out = '0;
    if (mem_read && mem_error == NO_MEM_ERROR) begin
      case (mem_access_type)
        BYTE_MEM_ACCESS: data_out = {{(DATA_WIDTH-8){1'b0}}, mem[word_index][lane_shift +: 8]};
        HALF_MEM_ACCESS: data_out = {{(DATA_WIDTH-16){1'b0}}, mem[word_index][lane_shift +: 16]};
        default: data_out = mem[word_index];
      endcase
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      restore();
    end
    else if (mem_write && mem_error == NO_MEM_ERROR) begin
      case (mem_access_type)
        BYTE_MEM_ACCESS: mem[word_index][lane_shift +: 8] <= data_in[7:0];
        HALF_MEM_ACCESS: mem[word_index][lane_shift +: 16] <= data_in[15:0];
        default: mem[word_index] <= data_in;
      endcase
    end
    else if (mem_error != NO_MEM_ERROR) begin
      $display("[%0t] warning: %s access addr=%h type=%b", $time,
               (mem_error == OUT_OF_BOUNDS) ? "out of bounds" : "misaligned", addr, mem_access_type);
    end
  end

endmodule
