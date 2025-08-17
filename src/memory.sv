module memory #(parameter WORDS = 64, DATA_WIDTH = 32) (
    input wire clk,
    input wire rst_n,
    input wire [DATA_WIDTH-1:0] addr,
    input wire [DATA_WIDTH-1:0] data_in,
    input wire write_enable,
    output reg [DATA_WIDTH-1:0] data_out
);
    reg [DATA_WIDTH-1:0] mem [0:WORDS-1]; // array

    always @(posedge clk) begin
      if (!rst_n) begin // pull low for reset
          for (int i = 0; i < WORDS; i = i + 1) begin
              mem[i] <= '0; // reset to zero
          end
      end
      else if (write_enable && addr[2:0] == 3'b000) begin // the address must be byte aligned; last 3 bits must be 0
          // system has 32-bit words, each word is 4 bytes
          // and the memory is byte aligned. even though the
          // address space is 2^32 bits, we only use 64 words * bytes/word
          // = 256 bytes of memory. this means the address space usable has
          // address only from 0x00_00_00_00 (0) to 0x00_00_00_FF (255) instead of
          // 0x00_00_00_00 (0) to 0xFF_FF_FF_FF (4,294,967,295).
          mem[addr[DATA_WIDTH-1:0]] <= data_in;
      end
    end

    assign data_out = mem[addr[DATA_WIDTH-1:0]]; // read data from memory

endmodule
