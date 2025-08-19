package isa_shared;

  typedef enum logic [2:0] {
    ALU_ADD = 3'b000, // ADD
    ALU_NOP = 3'b111 // No Operation
  } alu_ops_e;

  typedef enum logic [2:0] {
    SX_1100 = 3'b000,
    SX_3100 = 3'b001,
    SX_NOP = 3'b111 // No Operation
  } sx_ops_e;

  typedef enum logic [2:0] {
    I_LW = 3'b010
  } function3_e;

endpackage
