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

    ALU_SLL = 5'b01011, // Shift Left Logical
    ALU_SRL = 5'b01100, // Shift Right Logical
    ALU_SRA = 5'b01101, // Shift Right Arithmetic

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
    SX_1900 = 5'b01000, // 19 bits sign extension
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
    SH_SLLI = 3'b001, // RI-Shift_Left_Logical
    RI_SLTI = 3'b010, // RI-Set_Less_Than_Immediate
    RI_SLTIU = 3'b011, // RI-Set_Less_Than_Immediate_Unsigned
    RI_XORI = 3'b100, // RI-Xor_Immediate
    SH_SRLI = 3'b101, // RI-Shift_Right_Logical_Immediate, RI-Shift_Right_Arithmetic
    RI_ORI = 3'b110, // RI-Or_Immediate
    RI_ANDI = 3'b111 // RI-And_Immediate
  } ri_function3_e;

  typedef enum logic [6:0] {
    SH_SRLI_F7 = 7'b0000000, // RI-Shift_Right_Logical
    SH_SRAI_F7 = 7'b0100000 // RI-Shift_Right_Arithmetic
  } sh_function7_e;

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

  typedef enum logic [2:0] {
    R_ADDSUB = 3'b000, // R-Add_Subtract
    R_SLL = 3'b001, // R-Shift_Left_Logical
    R_SLT = 3'b010, // R-Set_Less_Than
    R_SLTU = 3'b011, // R-Set_Less_Than_Unsigned
    R_XOR = 3'b100, // R-Xor
    R_SRL_SRA = 3'b101, // R-Shift_Right_Logical, R-Shift_Right_Arithmetic
    R_OR = 3'b110, // R-Or
    R_AND = 3'b111 // R-And
  } r_function3_e;

  typedef enum logic [6:0] {
    R_ADD_F7 = 7'b0000000, // R-Add
    R_SUB_F7 = 7'b0100000 // R-Subtract
  } r_addsub_function7_e;
  typedef enum logic [6:0] {
    R_SRL_F7 = 7'b0000000, // R-Shift_Right_Logical
    R_SRA_F7 = 7'b0100000 // R-Shift_Right_Arithmetic
  } r_srlsra_function7_e;

  typedef enum logic [6:0] {
    LOAD = 7'b0000011, // Load instructions
    STORE = 7'b0100011, // Store instructions
    JAL = 7'b1101111, // Jump and Link
    JALR = 7'b1100111, // Jump and Link Register
    BRANCH = 7'b1100011, // Branch instructions
    REGISTER_IMM = 7'b0010011, // Register-Immediate instructions
    REGISTER = 7'b0110011, // Register-Register instructions
    LUI = 7'b0110111, // Load Upper Immediate Instruction
    AUIPC = 7'b0010111, // Add Upper Immediate to PC Instruction
    FENCE = 7'b0001111, // Fence instruction
    ECALL_BREAK = 7'b1110011 // Environment Call and Breakpoint
  } opcode_e;

  typedef enum logic [1:0] {
    BYTE_MEM_ACCESS = 2'b00, // Byte access
    HALF_MEM_ACCESS = 2'b01, // Halfword access
    WORD_MEM_ACCESS = 2'b10 // Word access
  } mem_access_type_e;

endpackage
