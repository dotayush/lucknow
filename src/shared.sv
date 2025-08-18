package isa_shared;

  typedef enum logic [2:0] {
    ALU_ADD = 3'b000, // Load Word
    ALU_NOP = 3'b111 // No Operation
  } alu_ops_e;

  typedef enum logic [2:0] {
    IMM_3120 = 3'b000, // Load Word
    IMM_NOP = 3'b111 // No Operation
  } imm_ops_e;

endpackage
