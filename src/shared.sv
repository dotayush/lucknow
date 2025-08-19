package isa_shared;

  typedef enum logic [2:0] {
    ALU_ADD = 3'b000, // ADD
    ALU_NOP = 3'b111 // No Operation
  } alu_ops_e;

  typedef enum logic [2:0] {
    SX_1100 = 3'b000,  // 12 bits sign extension
    SX_3100 = 3'b001, // no sign extension
    SX_1500 = 3'b010, // 16 bits sign extension
    SX_0700 = 3'b011, // 8 bits sign extension
    SX_NOP = 3'b111 // No Operation
  } sx_ops_e;

  typedef enum logic [2:0] {
    I_LW = 3'b010,  // I-Load_Word
    I_LH = 3'b001,   // I-Load_Halfword
    I_LB = 3'b000 // I-Load_Byte
  } function3_e;

endpackage
