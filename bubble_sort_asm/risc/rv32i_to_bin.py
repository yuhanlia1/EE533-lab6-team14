import struct,re,sys,math

# =========================
# Register map (with alias)
# =========================

reg = {f"x{i}":i for i in range(32)}
aliases = {
"zero":0,"ra":1,"sp":2,"gp":3,"tp":4,
"t0":5,"t1":6,"t2":7,
"s0":8,"fp":8,"s1":9,
"a0":10,"a1":11,"a2":12,"a3":13,"a4":14,"a5":15,"a6":16,"a7":17,
"s2":18,"s3":19,"s4":20,"s5":21,"s6":22,"s7":23,"s8":24,"s9":25,"s10":26,"s11":27,
"t3":28,"t4":29,"t5":30,"t6":31
}
reg.update(aliases)

# =========================
# Instruction Table RV32I
# =========================

INST = {

# R
"add":("R",0x33,0,0x00),
"sub":("R",0x33,0,0x20),
"sll":("R",0x33,1,0x00),
"slt":("R",0x33,2,0x00),
"sltu":("R",0x33,3,0x00),
"xor":("R",0x33,4,0x00),
"srl":("R",0x33,5,0x00),
"sra":("R",0x33,5,0x20),
"or": ("R",0x33,6,0x00),
"and":("R",0x33,7,0x00),

# I arithmetic
"addi":("I",0x13,0),
"slti":("I",0x13,2),
"sltiu":("I",0x13,3),
"xori":("I",0x13,4),
"ori": ("I",0x13,6),
"andi":("I",0x13,7),
"slli":("ISHIFT",0x13,1,0x00),
"srli":("ISHIFT",0x13,5,0x00),
"srai":("ISHIFT",0x13,5,0x20),

# Load
"lb": ("I",0x03,0),
"lh": ("I",0x03,1),
"lw": ("I",0x03,2),
"lbu":("I",0x03,4),
"lhu":("I",0x03,5),

# Store
"sb":("S",0x23,0),
"sh":("S",0x23,1),
"sw":("S",0x23,2),

# Branch
"beq": ("B",0x63,0),
"bne": ("B",0x63,1),
"blt": ("B",0x63,4),
"bge": ("B",0x63,5),
"bltu":("B",0x63,6),
"bgeu":("B",0x63,7),

# U
"lui":  ("U",0x37),
"auipc":("U",0x17),

# J
"jal": ("J",0x6F),
"jalr":("I",0x67,0),

# Fence
"fence":("F",0x0F),
"fence.i":("F",0x0F),

# Sys
"ecall": ("SYS",0x73,0),
"ebreak":("SYS",0x73,1),
}

# =========================
# Assembler core
# =========================

text_base = 0x0
rodata_base = 0x1000

labels = {}
sections = {"text":[], "rodata":[]}
pc_text = 0
pc_rodata = 0
current_section = "text"

def clean(line):
    return line.split("#")[0].strip()

def align(pc,n):
    return (pc + (n-1)) & ~(n-1)

# -------- First Pass --------

with open(sys.argv[1]) as f:
    for raw in f:
        line = clean(raw)
        if not line: continue

        # 忽略 GNU 元信息指令
        if line.startswith((
            ".file",
            ".option",
            ".attribute",
            ".globl",
            ".type",
            ".size",
            ".ident"
        )):
            continue

        if line.startswith(".section"):
            if ".rodata" in line: current_section="rodata"
            else: current_section="text"
            continue

        if line.startswith(".text"):
            current_section="text"
            continue

        if line.startswith(".rodata"):
            current_section="rodata"
            continue

        if line.startswith(".align"):
            n=int(line.split()[1])
            if current_section=="text":
                pc_text=align(pc_text,2**n)
            else:
                pc_rodata=align(pc_rodata,2**n)
            continue

        if ":" in line:
            label=line.replace(":","").strip()
            if current_section=="text":
                labels[label]=text_base+pc_text
            else:
                labels[label]=rodata_base+pc_rodata
            continue

        if line.startswith(".word"):
            sections[current_section].append(line)
            pc_rodata+=4
            continue

        sections[current_section].append(line)
        if current_section=="text":
            pc_text+=4

# -------- Helpers --------

def imm12(x): return x & 0xfff
def imm20(x): return x & 0xfffff

def hi20(addr): return (addr + 0x800) >> 12
def lo12(addr): return addr & 0xfff

# -------- Pseudo expand --------

def expand(line):
    t=re.split(r"[,\s()]+",line)
    op=t[0]

    if op=="li":
        rd=t[1]; imm=int(t[2])
        if -2048<=imm<2048:
            return [f"addi {rd},x0,{imm}"]
        else:
            return [f"lui {rd},{hi20(imm)}",
                    f"addi {rd},{rd},{lo12(imm)}"]

    if op=="mv":
        return [f"addi {t[1]},{t[2]},0"]

    if op=="j":
        return [f"jal x0,{t[1]}"]

    if op=="jr":
        return [f"jalr x0,0({t[1]})"]

    if op=="nop":
        return ["addi x0,x0,0"]

    if op=="ble":
        return [f"bge {t[2]},{t[1]},{t[3]}"]

    if op=="bgt":
        return [f"blt {t[2]},{t[1]},{t[3]}"]
    
    if op == "call":
        return [f"jal ra,{t[1]}"]
    
    if op == "ret":
        return ["jalr x0,0(ra)"]
    
    return [line]

# -------- Encoding --------

def encode(inst,pc):
    t=re.split(r"[,\s()]+",inst)
    op=t[0]

    fmt=INST[op][0]

    if fmt=="R":
        _,opc,f3,f7=INST[op]
        rd,rs1,rs2=reg[t[1]],reg[t[2]],reg[t[3]]
        return (f7<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|opc

    if fmt=="I":
        _,opc,f3 = INST[op]

        # 处理 %lo(label)
        if "%lo" in inst:
            label = re.findall(r'%lo\((.*?)\)',inst)[0]
            imm = lo12(labels[label])
            rd  = reg[t[1]]
            rs1 = reg[t[2]]

        # jalr / load 格式
        elif op=="jalr" or op in ["lb","lh","lw","lbu","lhu"]:
            rd  = reg[t[1]]
            imm = int(t[2])
            rs1 = reg[t[3]]

        else:
            rd  = reg[t[1]]
            rs1 = reg[t[2]]
            imm = int(t[3])

        return ((imm & 0xfff)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|opc

    if fmt=="ISHIFT":
        _,opc,f3,f7=INST[op]
        rd,rs1,sh=reg[t[1]],reg[t[2]],int(t[3])
        return (f7<<25)|(sh<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|opc

    if fmt=="S":
        _,opc,f3=INST[op]
        rs2,imm,rs1=reg[t[1]],int(t[2]),reg[t[3]]
        return ((imm>>5)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|((imm&0x1f)<<7)|opc

    if fmt=="B":
        _,opc,f3=INST[op]
        rs1,rs2,label=reg[t[1]],reg[t[2]],t[3]
        imm=labels[label]-pc
        return ((imm>>12)<<31)|(((imm>>5)&0x3f)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(((imm>>1)&0xf)<<8)|(((imm>>11)&1)<<7)|opc

    if fmt=="U":
        _,opc=INST[op]
        if "%hi" in inst:
            label=re.findall(r'%hi\((.*?)\)',inst)[0]
            imm=hi20(labels[label])
        else:
            imm=int(t[2])
        rd=reg[t[1]]
        return (imm20(imm)<<12)|(rd<<7)|opc

    if fmt=="J":
        _,opc=INST[op]
        rd,label=reg[t[1]],t[2]
        imm=labels[label]-pc
        return ((imm>>20)<<31)|(((imm>>1)&0x3ff)<<21)|(((imm>>11)&1)<<20)|(((imm>>12)&0xff)<<12)|(rd<<7)|opc

    if fmt=="F":
        return 0x0000000F

    if fmt=="SYS":
        _,opc,code=INST[op]
        return (code<<20)|opc

    raise Exception("Unknown instruction "+op)

# -------- Second Pass --------

with open("findmin_rv32i_gen.bin","wb") as out:
    pc=text_base
    for line in sections["text"]:
        for ex in expand(line):
            code=encode(ex,pc)
            # out.write(struct.pack("<I",code))
            out.write(struct.pack("<I", code & 0xffffffff))
            pc+=4

    # write rodata
    for line in sections["rodata"]:
        val=int(line.split()[1])
        out.write(struct.pack("<i",val))

print("Build success → out.bin")