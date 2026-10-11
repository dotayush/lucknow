module memory_bus #(
  parameter DATA_WIDTH = 32,
  parameter ADDR_WIDTH = 32
  parameter AGENTS = 2 // number of bus agents
)(
  // global signals
  input wire clk,
  input wire rst_n,

  // agent interfaces
  input wire agent_req [0:AGENTS-1], // request signal from agent to use the bus
  output reg agent_grant [0:AGENTS-1], // grant signal from bus to agent
  input wire agent_rt  [0:AGENTS-1], // request type: 0 = read, 1 = write
  input wire [1:0] agent_at [0:AGENTS-1], // 00 = byte, 01 = halfword, 10 = word
  input wire [ADDR_WIDTH-1:0] agent_addr [0:AGENTS-1], // address from agent
  input wire [DATA_WIDTH-1:0] agent_wdata [0:AGENTS-1], // write data from agent
  output reg [DATA_WIDTH-1:0] agent_rdata [0:AGENTS-1], // read data to agent
  output reg [1:0] agent_error [0:AGENTS-1], // error signal from bus to agent
  output reg agent_ready [0:AGENTS-1], // ready signal from bus to agent

  // memory interface
  output reg mem_req, // request signal to memory
  output reg mem_rw, // request type: 0 = read, 1 = write
  output reg [1:0] mem_access_type, // 00 = byte, 01 = halfword, 10 = word
  output reg [ADDR_WIDTH-1:0] mem_addr, // address to memory
  output reg [DATA_WIDTH-1:0] mem_wdata, // write data to memory
  input wire [DATA_WIDTH-1:0] mem_rdata, // read data from memory
  input wire mem_ready, // ready signal from memory
  input wire [1:0] mem_error // error signal from memory
);

  // simple round-robin arbiter
  integer i;
  reg [31:0] current_agent; // index of the current agent being served


  // initial state
  initial begin
    current_agent = 0;
    for (i = 0; i < AGENTS; i = i + 1) begin
      agent_grant[i] = 0;
      agent_ready[i] = 0;
      agent_error[i] = 0;
      agent_rdata[i] = 0;
    end
    mem_req = 0;
    mem_rw = 0;
    mem_access_type = 0;
    mem_addr = 0;
    mem_wdata = 0;
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      current_agent <= 0;
      for (i = 0; i < AGENTS; i = i + 1) begin
        agent_grant[i] <= 0;
        agent_ready[i] <= 0;
        agent_error[i] <= 0;
        agent_rdata[i] <= 0;
      end
      mem_req <= 0;
      mem_rw <= 0;
      mem_access_type <= 0;
      mem_addr <= 0;
      mem_wdata <= 0;
    end
    else begin
      // check if memory is ready to accept a new request or return data
      if (mem_ready) begin
        // if memory was ready, clear the request signal
        mem_req <= 0;

        // if there was an active request, return data and error to the corresponding agent
        if (agent_grant[current_agent]) begin
          agent_ready[current_agent] <= 1; // signal that the request is complete
          agent_error[current_agent] <= mem_error; // pass through any memory error
          if (!mem_rw) begin // if it was a read request, provide the read data
            agent_rdata[current_agent] <= mem_rdata;
          end
          agent_grant[current_agent] <= 0; // clear the grant signal
        end

        // move to the next agent in round-robin fashion
        current_agent <= (current_agent + 1) % AGENTS;

        // check for new requests from agents
        for (i = 0; i < AGENTS; i = i + 1) begin
          if (agent_req[(current_agent + i) % AGENTS]) begin
            // grant the bus to this agent
            current_agent <= (current_agent + i) % AGENTS;
            agent_grant[current_agent] <= 1;
            agent_ready[current_agent] <= 0; // clear ready signal for new request
            agent_error[current_agent] <= 0; // clear error signal for new request

            // set up memory request signals
            mem_req <= 1;
            mem_rw <= agent_rt[current_agent];
            mem_access_type <= agent_at[current_agent];
            mem_addr <= agent_addr[current_agent];
            mem_wdata <= agent_wdata[current_agent];
            break; // exit the loop after granting one agent
          end
        end
    end
  end


endmodule
