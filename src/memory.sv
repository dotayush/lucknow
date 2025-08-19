module memory #(parameter WORDS = 64, DATA_WIDTH = 32, MEM_INIT = "") (
    input wire clk,
    input wire rst_n,

    // read
    input wire [DATA_WIDTH-1:0] addr,
    output reg [DATA_WIDTH-1:0] data_out,

    // write
    input wire [DATA_WIDTH-1:0] data_in,
    input wire mem_write

    // exception

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
      else if (mem_write) begin
          // system has 32-bit words, each word is 4 bytes
          // and the memory is byte aligned. even though the
          // address space is 2^32 bits, we only use 64 words/bytes.
          // this means the address space usable has
          // address only from 0x00_00_00_00 (0) to 0x00_00_00_3F (63) instead
          // of the full 32-bit address space of
          // 0x00_00_00_00 (0) to 0xFF_FF_FF_FF (4,294,967,295).

          if (addr[1:0] != 2'b00) begin // check if address is aligned to 4 bytes
            $display("[%0t] error: address %h is not aligned to 4 bytes", $time, addr);
            // TODO: implement trap
          end
          else if (addr[DATA_WIDTH-1:2] >= WORDS) begin // check if address is within bounds
            $display("[%0t] error: address %h is out of bounds", $time, addr);
            // TODO: implement trap
          end
          else mem[addr[DATA_WIDTH-1:2]] <= data_in; // write data to memory
      end
    end

    always @* begin
       if (addr[1:0] != 2'b00) begin
          $display("[%0t] error: address %h is not aligned to 4 bytes", $time, addr);
          data_out = '0; // return zero if address is not aligned
       end
       else if (addr[DATA_WIDTH-1:2] >= WORDS) begin
          $display("[%0t] error: address %h is out of bounds", $time, addr);
          data_out = '0; // return zero if address is out of bounds
       end
       else data_out = mem[addr[DATA_WIDTH-1:2]]; // read data from memory
    end

endmodule
