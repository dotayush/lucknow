// mixed signal demo: a counter powers up the analog oscillator after 128 clocks,
// the oscillator output is synchronised and counted back in the digital domain.
module LELO_GR02 (input PWRUP_1V8, output OSC_TEMP_1V8);   // blackbox; power pins come from the pdn, not the netlist
endmodule

module ms_demo (
  input  wire clk,
  input  wire rst_n,
  output reg  [7:0] ticks,
  output wire osc_seen
);
  reg [7:0] up;
  wire osc;
  always @(posedge clk or negedge rst_n)
    if (!rst_n) up <= 8'd0; else if (!up[7]) up <= up + 8'd1;

  LELO_GR02 osc_i (.PWRUP_1V8(up[7]), .OSC_TEMP_1V8(osc));

  reg s1, s2, s3;
  always @(posedge clk or negedge rst_n)
    if (!rst_n) begin s1 <= 0; s2 <= 0; s3 <= 0; ticks <= 0; end
    else begin s1 <= osc; s2 <= s1; s3 <= s2; if (s2 & ~s3) ticks <= ticks + 8'd1; end
  assign osc_seen = s2;
endmodule
