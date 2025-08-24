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
    SXU_0400 = 5'b01001, // 5 bits unsigned extension
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
  typedef enum logic [2:0] {
    SYS_ECALL_EBREAK = 3'b000, // Environment Call and Breakpoint
    SYS_CSRRW = 3'b001, // Atomic Read/Write CSR
    SYS_CSRRS = 3'b010, // Atomic Read and Set Bits in CSR
    SYS_CSRRC = 3'b011, // Atomic Read and Clear Bits in CSR
    SYS_CSRRWI = 3'b101, // Atomic Read/Write CSR Immediate
    SYS_CSRRSI = 3'b110, // Atomic Read and Set Bits in CSR Immediate
    SYS_CSRRCI = 3'b111 // Atomic Read and Clear Bits in CSR Immediate
  } system_function3_e;

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
    SYSTEM = 7'b1110011 // Environment Call and Breakpoint, CSR etc.
  } opcode_e;

  typedef enum logic [1:0] {
    BYTE_MEM_ACCESS = 2'b00, // Byte access
    HALF_MEM_ACCESS = 2'b01, // Halfword access
    WORD_MEM_ACCESS = 2'b10 // Word access
  } mem_access_type_e;

  typedef enum logic [1:0] {
    CSR_NOP = 2'b00, // No operation
    CSR_WRITE = 2'b01, // Write CSR
    CSR_SET = 2'b10, // Set bits in CSR
    CSR_CLEAR = 2'b11 // Clear bits in CSR
  } csr_ops_e;

  typedef enum logic [3:0] {
    TRAP_NONE = 4'b0000, // No trap
    TRAP_ECALL_M = 4'b0011, // Environment call from M-mode
    TRAP_EBREAK = 4'b0100, // Breakpoint
    TRAP_ILLEGAL_INSTRUCTION = 4'b0101, // Illegal instruction
    TRAP_MEMORY_ADDRESS_MISALIGNED = 4'b0110 // Address misaligned
  } trap_cause_e;

  typedef enum logic [11:0] {
    // machine trap and interrupt related CSRs
    CSR_MTVEC = 12'h305, // Machine trap-handler base address
    CSR_MCAUSE = 12'h342, // Machine trap cause
    CSR_MTVAL = 12'h343, // Machine bad address or instruction
    CSR_MEPC = 12'h341, // Machine trap program counter

    // machine information and control CSRs
    CSR_MIP = 12'h344, // Machine interrupt pending
    CSR_MIE = 12'h304, // Machine interrupt enable
    CSR_MSTATUS = 12'h300, // Machine status register
    CSR_ISA = 12'h301, // ISA and extensions
    CSR_MCYCLE = 12'hB00, // Machine cycle counter

    // metadata CSRs
    CSR_MVENDORID = 12'hF11, // Vendor ID
    CSR_MARCHID = 12'hF12, // Architecture ID
    CSR_MIMPID = 12'hF13, // Implementation ID
    CSR_MHARTID = 12'hF14 // Hardware thread ID
  } csr_addr_e;

endpackage
