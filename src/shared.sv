package isa_shared;

  typedef enum logic [2:0] {
    ALU_ADD = 3'b000, // ADD
    ALU_NOP = 3'b111 // No Operation
  } alu_ops_e;

  typedef enum logic [2:0] {
    SX_1100 = 3'b000,  // 12 bits sign extension
    SX_3100 = 3'b001, // 32 unsigned/signed extension
    SX_1500 = 3'b010, // 16 bits sign extension
    SX_0700 = 3'b011, // 8 bits sign extension
    SXU_0700 = 3'b100, // 8 bits unsigned extension
    SXU_1500 = 3'b101, // 16 bits unsigned extension
    SX_2000  = 3'b110, // 20 bits sign extension
    SX_NOP = 3'b111 // No Operation
  } sx_ops_e;

  typedef enum logic [2:0] {
    I_LW = 3'b010,  // I-Load_Word
    I_LH = 3'b001,   // I-Load_Halfword
    I_LB = 3'b000, // I-Load_Byte
    I_LBU = 3'b100, // I-Load_Byte_Unsigned
    I_LHU = 3'b101 // I-Load_Halfword_Unsigned
  } i_function3_e;

  typedef enum logic [2:0] {
    S_SW = 3'b010, // S-Store_Word
    S_SH = 3'b001, // S-Store_Halfword
    S_SB = 3'b000 // S-Store_Byte
  } s_function3_e;

  typedef enum logic [6:0] {
    LOAD = 7'b0000011, // Load instructions
    STORE = 7'b0100011, // Store instructions
    JAL = 7'b1101111, // Jump and Link
    JALR = 7'b1100111 // Jump and Link Register
  } opcode_e;

  typedef enum logic [1:0] {
    BYTE_MEM_ACCESS = 2'b00, // Byte access
    HALF_MEM_ACCESS = 2'b01, // Halfword access
    WORD_MEM_ACCESS = 2'b10 // Word access
  } mem_access_type_e;

endpackage
