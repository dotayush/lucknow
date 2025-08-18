module memory #(parameter WORDS = 64, DATA_WIDTH = 32, MEM_INIT = "") (
    input wire clk,
    input wire rst_n,

    input wire [DATA_WIDTH-1:0] addr,
    output reg [DATA_WIDTH-1:0] data_out,

    input wire [DATA_WIDTH-1:0] data_in,
    input wire mem_write
);
    reg [DATA_WIDTH-1:0] mem [0:WORDS-1]; // array

    initial begin
        if (MEM_INIT != "") begin
            $readmemh(MEM_INIT, mem); // load memory from file if specified
        end
        else begin
            for (int i = 0; i < WORDS; i = i + 1) begin
                mem[i] = '0; // initialize memory to zero
            end
        end
    end

    always @(posedge clk) begin
      if (!rst_n) begin // pull low for reset
          for (int i = 0; i < WORDS; i = i + 1) begin
              mem[i] <= '0; // reset to zero
          end
      end
      else if (mem_write && addr[1:0] == 2'b00) begin // the address must be aligned; last 3 bits must be 0
          // system has 32-bit words, each word is 4 bytes
          // and the memory is byte aligned. even though the
          // address space is 2^32 bits, we only use 64 words/bytes.
          // this means the address space usable has
          // address only from 0x00_00_00_00 (0) to 0x00_00_00_3F (63) instead
          // of the full 32-bit address space of
          // 0x00_00_00_00 (0) to 0xFF_FF_FF_FF (4,294,967,295).
          mem[addr[DATA_WIDTH-1:2]] <= data_in;
      end
    end

    assign data_out = mem[addr[DATA_WIDTH-1:2]]; // read data from memory

endmodule
