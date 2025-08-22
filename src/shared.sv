package isa_shared;

  typedef enum logic [4:0] {
    ALU_ADD = 5'b00000, // ADD
    ALU_EQUALS = 5'b00001, // EQ
    ALU_NOT_EQUALS = 5'b00010, // NEQ
    ALU_SUB = 5'b00011, // SUB

    ALU_LT = 5'b00100, // LT
    ALU_GE = 5'b00101, // GE
    ALU_LTU = 5'b00110, // LTU
    ALU_GEU = 5'b00111, // GEU

    ALU_XOR = 5'b01000, // XOR
    ALU_OR = 5'b01001, // OR
    ALU_AND = 5'b01010, // AND

    ALU_NOP = 5'b11111 // No Operation
  } alu_ops_e;

  typedef enum logic [4:0] {
    SX_1100 = 5'b00000,  // 12 bits sign extension
    SX_3100 = 5'b00001, // 32 unsigned/signed extension
    SX_1500 = 5'b00010, // 16 bits sign extension
    SX_0700 = 5'b00011, // 8 bits sign extension
    SXU_0700 = 5'b00100, // 8 bits unsigned extension
    SXU_1500 = 5'b00101, // 16 bits unsigned extension
    SX_2000  = 5'b00110, // 21 bits sign extension
    SX_1200 = 5'b00111, // 13 bits sign extension
    SX_NOP = 5'b11111 // No Operation
  } sx_ops_e;

  typedef enum logic [2:0] {
    I_LW = 3'b010,  // I-Load_Word
    I_LH = 3'b001,   // I-Load_Halfword
    I_LB = 3'b000, // I-Load_Byte
    I_LBU = 3'b100, // I-Load_Byte_Unsigned
    I_LHU = 3'b101 // I-Load_Halfword_Unsigned
  } i_function3_e;

  typedef enum logic [2:0] {
    RI_ADDI = 3'b000, // RI-Add_Immediate
    RI_SLTI = 3'b010, // RI-Set_Less_Than_Immediate
    RI_SLTIU = 3'b011, // RI-Set_Less_Than_Immediate_Unsigned
    RI_XORI = 3'b100, // RI-Xor_Immediate
    RI_ORI = 3'b110, // RI-Or_Immediate
    RI_ANDI = 3'b111 // RI-And_Immediate
  } ri_function3_e;

  typedef enum logic [2:0] {
    S_SW = 3'b010, // S-Store_Word
    S_SH = 3'b001, // S-Store_Halfword
    S_SB = 3'b000 // S-Store_Byte
  } s_function3_e;

  typedef enum logic [2:0] {
    B_BEQ = 3'b000, // B-Branch_Equal
    B_BNE = 3'b001, // B-Branch_Not_Equal
    B_BLT = 3'b100, // B-Branch_Less_Than
    B_BGE = 3'b101, // B-Branch_Greater_Than_or_Equal
    B_BLTU = 3'b110, // B-Branch_Less_Than_Unsigned
    B_BGEU = 3'b111 // B-Branch_Greater_Than_or_Equal_Unsigned
  } b_function3_e;

  typedef enum logic [6:0] {
    LOAD = 7'b0000011, // Load instructions
    STORE = 7'b0100011, // Store instructions
    JAL = 7'b1101111, // Jump and Link
    JALR = 7'b1100111, // Jump and Link Register
    BRANCH = 7'b1100011, // Branch instructions
    REGISTER_IMM = 7'b0010011 // Register-Immediate instructions
  } opcode_e;

  typedef enum logic [1:0] {
    BYTE_MEM_ACCESS = 2'b00, // Byte access
    HALF_MEM_ACCESS = 2'b01, // Halfword access
    WORD_MEM_ACCESS = 2'b10 // Word access
  } mem_access_type_e;

endpackage
