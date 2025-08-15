module memory #(parameter ADDR_WIDTH = 8, DATA_WIDTH = 32) (
    input wire clk,
    input wire rst_n,
    input wire [ADDR_WIDTH-1:0] addr,
    input wire [DATA_WIDTH-1:0] data_in,
    input wire write_enable,
    output reg [DATA_WIDTH-1:0] data_out
);
    localparam int WORDS = 1 << (ADDR_WIDTH - 2); // address should be a multiple of 4 (f e d c b a 0 0)
    reg [DATA_WIDTH-1:0] mem [0:WORDS-1]; // array

    always @(posedge clk) begin
      if (!rst_n) begin // pull low for reset
          for (int i = 0; i < WORDS; i = i + 1) begin
              mem[i] <= '0; // reset to zero
          end
      end
      else if (write_enable && addr[1:0] == 2'b00) begin
          mem[addr[ADDR_WIDTH-1:2]] <= data_in;
      end
    end

    assign data_out = mem[addr[ADDR_WIDTH-1:2]]; // read data from memory

endmodule
