#!/usr/bin/env python3
"""
rv32i_asm.py  —  RV32I Assembler for Early-Branch Pipeline
=============================================================
支持直接处理 GCC 生成的 RV32I 汇编（.s 文件），适配你的微架构。

【内存映射约定】
  Icache : byte addr 0 起，word index = byte[10:2]，存放指令
  Dcache : byte addr 0 起，word index = byte[10:2]，存放数据
  .text  → Icache（自动 NOP padding，3 slot/指令）
  .rodata → Dcache 预加载，起始字节地址 = RODATA_BASE（默认 0x400）
  stack  → Dcache，sp 初始值 = STACK_TOP（默认 0x300，向低地址增长）

【命令行】
  python rv32i_asm.py  source.asm
  python rv32i_asm.py  source.asm  --rodata 0x400  --stack 0x300

【输出文件】
  <stem>.listing    — 人类可读的地址/hex/汇编对照表
  <stem>.vh         — Verilog task：load_icache + load_dcache（直接粘贴到 TB）

【主要特性】
  • 忽略所有 GNU 元信息指令（.option .attribute .type .size .ident .globl 等）
  • 处理 .rodata 段的 .word 数据
  • 解析 %hi(label) / %lo(label) 用于 lui/addi 对
  • 自动在程序开头注入 li sp, STACK_TOP（适配裸机无 runtime）
  • ret 替换为 beq x0,x0,0 (HALT) 防止跳回 0 重启
  • 每条真实指令后自动插入 2 个 NOP
  • 分支/跳转立即数按字节偏移自动计算
"""

import re, sys, os, argparse

# ─────────────────────────────────────────────────────────────────────────────
#  ★ 用户可调参数（也可通过命令行覆盖）
# ─────────────────────────────────────────────────────────────────────────────
DEFAULT_RODATA_BASE = 0x400   # .rodata 在 Dcache 的起始字节地址
DEFAULT_STACK_TOP   = 0x300   # sp 初始值（程序前自动注入 li sp, STACK_TOP）
SLOTS_PER_INST      = 3       # 每条真实指令占的 word slot（1条指令 + 2个NOP）
BYTES_PER_SLOT      = 4
BYTES_PER_INST      = SLOTS_PER_INST * BYTES_PER_SLOT   # = 12
NOP_WORD            = 0x00000013   # addi x0,x0,0
HALT_WORD           = 0x00000063   # beq x0,x0,0（自跳转）

# ─────────────────────────────────────────────────────────────────────────────
#  寄存器映射
# ─────────────────────────────────────────────────────────────────────────────
REGS = {f"x{i}": i for i in range(32)}
REGS.update({
    "zero":0, "ra":1,  "sp":2,  "gp":3,  "tp":4,
    "t0":5,   "t1":6,  "t2":7,
    "s0":8,   "fp":8,  "s1":9,
    "a0":10,  "a1":11, "a2":12, "a3":13, "a4":14, "a5":15, "a6":16, "a7":17,
    "s2":18,  "s3":19, "s4":20, "s5":21, "s6":22, "s7":23,
    "s8":24,  "s9":25, "s10":26,"s11":27,
    "t3":28,  "t4":29, "t5":30, "t6":31,
})

# ─────────────────────────────────────────────────────────────────────────────
#  指令表  (fmt, opcode, funct3 [, funct7])
# ─────────────────────────────────────────────────────────────────────────────
INST = {
    # R-type
    "add":  ("R",0x33,0,0x00), "sub":  ("R",0x33,0,0x20),
    "sll":  ("R",0x33,1,0x00), "slt":  ("R",0x33,2,0x00),
    "sltu": ("R",0x33,3,0x00), "xor":  ("R",0x33,4,0x00),
    "srl":  ("R",0x33,5,0x00), "sra":  ("R",0x33,5,0x20),
    "or":   ("R",0x33,6,0x00), "and":  ("R",0x33,7,0x00),
    # I-type arithmetic
    "addi": ("I",0x13,0), "slti": ("I",0x13,2), "sltiu":("I",0x13,3),
    "xori": ("I",0x13,4), "ori":  ("I",0x13,6), "andi": ("I",0x13,7),
    # I-shift
    "slli": ("IS",0x13,1,0x00), "srli": ("IS",0x13,5,0x00), "srai": ("IS",0x13,5,0x20),
    # Load
    "lb":("I",0x03,0),"lh":("I",0x03,1),"lw":("I",0x03,2),
    "lbu":("I",0x03,4),"lhu":("I",0x03,5),
    # Store
    "sb":("S",0x23,0),"sh":("S",0x23,1),"sw":("S",0x23,2),
    # Branch
    "beq":("B",0x63,0),"bne":("B",0x63,1),
    "blt":("B",0x63,4),"bge":("B",0x63,5),
    "bltu":("B",0x63,6),"bgeu":("B",0x63,7),
    # U-type
    "lui":("U",0x37),"auipc":("U",0x17),
    # J-type
    "jal":("J",0x6F),
    # JALR
    "jalr":("I",0x67,0),
    # System
    "ecall":("SYS",0x73,0),"ebreak":("SYS",0x73,1),
}

# ─────────────────────────────────────────────────────────────────────────────
#  工具函数
# ─────────────────────────────────────────────────────────────────────────────
def R(name):
    name = name.strip()
    if name not in REGS:
        raise ValueError(f"未知寄存器: {name!r}")
    return REGS[name]

def parse_int(s):
    s = s.strip()
    neg = s.startswith('-')
    if neg: s = s[1:]
    base = 16 if s.lower().startswith('0x') else 10
    v = int(s, base)
    return -v if neg else v

def hi20(addr):
    """%hi(addr) = (addr + 0x800) >> 12  (lui immediate，处理 lo 负号)"""
    return ((addr + 0x800) >> 12) & 0xFFFFF

def lo12(addr):
    """%lo(addr) = addr & 0xFFF (sign-extended 12-bit)"""
    v = addr & 0xFFF
    return v - 0x1000 if v >= 0x800 else v

def split_args(s):
    """把 'rd, rs1, imm' 或 'rd, imm(rs1)' 标准化拆开"""
    s = re.sub(r'(-?[\w.]+)\((\w+)\)', r'\1,\2', s)  # imm(rs) → imm,rs
    parts = re.split(r'[\s,]+', s.strip())
    return [p for p in parts if p]

# ─────────────────────────────────────────────────────────────────────────────
#  %hi/%lo 解析（处理 lui a3,%hi(.LC0) 等形式）
# ─────────────────────────────────────────────────────────────────────────────
def resolve_hi_lo(arg, labels):
    """
    如果 arg 包含 %hi(label) 或 %lo(label)，返回对应整数值。
    否则直接 parse_int。
    """
    arg = arg.strip()
    m_hi = re.match(r'%hi\(([^)]+)\)', arg)
    m_lo = re.match(r'%lo\(([^)]+)\)', arg)
    if m_hi:
        lbl = m_hi.group(1).strip()
        if lbl not in labels:
            raise ValueError(f"未定义标签: {lbl!r} (用于 %hi)")
        return hi20(labels[lbl])
    if m_lo:
        lbl = m_lo.group(1).strip()
        if lbl not in labels:
            raise ValueError(f"未定义标签: {lbl!r} (用于 %lo)")
        return lo12(labels[lbl])
    return parse_int(arg)

# ─────────────────────────────────────────────────────────────────────────────
#  伪指令展开  → list of (mnemonic, args_str)
# ─────────────────────────────────────────────────────────────────────────────
def expand_pseudo(mn, args, labels=None):
    tok = split_args(args) if args else []

    if mn == "nop":   return [("addi","x0,x0,0")]
    if mn == "ret":   return [("_HALT","")]           # 特殊标记：转 HALT

    if mn == "li":
        rd  = tok[0]
        imm = parse_int(tok[1])
        if -2048 <= imm < 2048:
            return [("addi", f"{rd},x0,{imm}")]
        else:
            h = hi20(imm); l = lo12(imm)
            return [("lui",  f"{rd},{h}"),
                    ("addi", f"{rd},{rd},{l}")]

    if mn == "mv":    return [("addi", f"{tok[0]},{tok[1]},0")]
    if mn == "j":     return [("jal",  f"x0,{tok[0]}")]
    if mn == "jr":    return [("jalr", f"x0,0({tok[0]})")]
    if mn == "call":  return [("jal",  f"ra,{tok[0]}")]
    if mn == "tail":  return [("jal",  f"x0,{tok[0]}")]

    if mn == "ble":   return [("bge",  f"{tok[1]},{tok[0]},{tok[2]}")]
    if mn == "bgt":   return [("blt",  f"{tok[1]},{tok[0]},{tok[2]}")]
    if mn == "blez":  return [("bge",  f"x0,{tok[0]},{tok[1]}")]
    if mn == "bgtz":  return [("blt",  f"x0,{tok[0]},{tok[1]}")]
    if mn == "beqz":  return [("beq",  f"{tok[0]},x0,{tok[1]}")]
    if mn == "bnez":  return [("bne",  f"{tok[0]},x0,{tok[1]}")]
    if mn == "seqz":  return [("sltiu",f"{tok[0]},{tok[1]},1")]
    if mn == "snez":  return [("sltu", f"{tok[0]},x0,{tok[1]}")]
    if mn == "sltz":  return [("slt",  f"{tok[0]},{tok[1]},x0")]
    if mn == "sgtz":  return [("slt",  f"{tok[0]},x0,{tok[1]}")]
    if mn == "neg":   return [("sub",  f"{tok[0]},x0,{tok[1]}")]
    if mn == "not":   return [("xori", f"{tok[0]},{tok[1]},-1")]
    if mn == "halt":  return [("_HALT","")]

    return [(mn, args)]

# ─────────────────────────────────────────────────────────────────────────────
#  编码单条真实指令
# ─────────────────────────────────────────────────────────────────────────────
def encode_one(mn, args_str, byte_pc, labels):
    """返回 32-bit 编码。_HALT 返回 HALT_WORD。"""
    if mn == "_HALT":
        return HALT_WORD

    tok = split_args(args_str) if args_str else []

    def lbl_offset(name):
        if name not in labels:
            raise ValueError(f"未定义标签: {name!r}  (at byte_pc={byte_pc})")
        return labels[name] - byte_pc

    if mn not in INST:
        raise ValueError(f"未知指令: {mn!r}  (byte_pc={byte_pc})")

    info = INST[mn]
    fmt  = info[0]

    # ── R-type ──────────────────────────────────────────────────────────────
    if fmt == "R":
        _, opc, f3, f7 = info
        rd, rs1, rs2 = R(tok[0]), R(tok[1]), R(tok[2])
        return (f7<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|opc

    # ── I-type（含 load / jalr）────────────────────────────────────────────
    if fmt == "I":
        _, opc, f3 = info
        if mn in ("lw","lh","lb","lbu","lhu","jalr"):
            rd  = R(tok[0])
            imm = parse_int(tok[1])
            rs1 = R(tok[2])
        else:
            rd  = R(tok[0])
            rs1 = R(tok[1])
            # 第三个参数可能是 %lo(label)
            imm = resolve_hi_lo(tok[2], labels)
        return ((imm & 0xFFF)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|opc

    # ── I-shift ─────────────────────────────────────────────────────────────
    if fmt == "IS":
        _, opc, f3, f7 = info
        rd    = R(tok[0])
        rs1   = R(tok[1])
        shamt = parse_int(tok[2]) & 0x1F
        return (f7<<25)|(shamt<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|opc

    # ── S-type ──────────────────────────────────────────────────────────────
    if fmt == "S":
        _, opc, f3 = info
        rs2 = R(tok[0])
        imm = parse_int(tok[1]) & 0xFFF
        rs1 = R(tok[2])
        return ((imm>>5)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|((imm&0x1F)<<7)|opc

    # ── B-type ──────────────────────────────────────────────────────────────
    if fmt == "B":
        _, opc, f3 = info
        rs1 = R(tok[0])
        rs2 = R(tok[1])
        imm = lbl_offset(tok[2])
        return (((imm>>12)&1)<<31)|(((imm>>5)&0x3F)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(((imm>>1)&0xF)<<8)|(((imm>>11)&1)<<7)|opc

    # ── U-type ──────────────────────────────────────────────────────────────
    if fmt == "U":
        _, opc = info
        rd  = R(tok[0])
        # 支持 %hi(label)
        imm = resolve_hi_lo(tok[1], labels) & 0xFFFFF
        return (imm<<12)|(rd<<7)|opc

    # ── J-type ──────────────────────────────────────────────────────────────
    if fmt == "J":
        _, opc = info
        rd  = R(tok[0])
        imm = lbl_offset(tok[1])
        return (((imm>>20)&1)<<31)|(((imm>>1)&0x3FF)<<21)|(((imm>>11)&1)<<20)|(((imm>>12)&0xFF)<<12)|(rd<<7)|opc

    # ── System ──────────────────────────────────────────────────────────────
    if fmt == "SYS":
        _, opc, code = info
        return (code<<20)|opc

    raise ValueError(f"未知格式: {fmt}")

# ─────────────────────────────────────────────────────────────────────────────
#  GNU 指令过滤
# ─────────────────────────────────────────────────────────────────────────────
GNU_SKIP = re.compile(
    r'^\.(file|option|attribute|globl|type|size|ident|text$|data$|bss$'
    r'|cfi_|loc |loc$|uleb|sleb|string|ascii|byte|half|'
    r'|p2align|balign|comm|lcomm|set|equ|equiv|weak|protected|hidden|internal'
    r'|section(?!\s+\.rodata))'  # .section .rodata 要保留
)

def should_skip(line):
    if not line or line.startswith('//'):
        return True
    if re.match(r'^\.(file|option|attribute|globl|type|size|ident)', line):
        return True
    return False

# ─────────────────────────────────────────────────────────────────────────────
#  主汇编流程
# ─────────────────────────────────────────────────────────────────────────────
def assemble(src_path, rodata_base=DEFAULT_RODATA_BASE, stack_top=DEFAULT_STACK_TOP):
    stem = os.path.splitext(src_path)[0]

    # ── 读取源文件 ────────────────────────────────────────────────────────────
    with open(src_path, encoding="utf-8", errors="replace") as f:
        raw = f.readlines()

    # ── 预处理：去注释、strip ────────────────────────────────────────────────
    lines = []
    for line in raw:
        line = re.split(r'(?<!\S)#|//|@', line)[0].strip()
        if line:
            lines.append(line)

    # ── 第一遍：分段收集 ─────────────────────────────────────────────────────
    # section_text: list of (original_line, is_label, label_name | mnemonic, args)
    # section_rodata: list of int (word values)
    section = "text"
    text_raw    = []   # (line_str,)
    rodata_data = []   # int words
    rodata_labels = {} # label_name → byte_offset_within_rodata

    rodata_pc = 0

    for line in lines:
        lo = line.lower()

        # 切换 section
        if lo.startswith('.section') and '.rodata' in lo:
            section = "rodata"; continue
        if lo == '.text' or lo.startswith('.text '):
            section = "text"; continue
        if lo == '.data':
            section = "data"; continue
        if lo == '.rodata':
            section = "rodata"; continue

        # 忽略 GNU 元信息
        if should_skip(line): continue
        if re.match(r'\.(align|p2align|balign)\s', lo): continue

        # 标签
        if line.endswith(':') or (re.match(r'^[\w.]+\s*:', line) and not line.startswith('.')):
            lbl = re.match(r'^([\w.]+)\s*:', line).group(1)
            if section == "rodata":
                rodata_labels[lbl] = rodata_pc
            else:
                text_raw.append(('LABEL', lbl))
            # 标签后可能还有指令
            rest = line[line.index(':')+1:].strip()
            if rest:
                if section == "rodata":
                    text_raw.append(('CODE', rest))
                else:
                    text_raw.append(('CODE', rest))
            continue

        # .word in rodata
        if lo.startswith('.word'):
            if section == "rodata":
                val = parse_int(line.split(None,1)[1].strip())
                rodata_data.append(val & 0xFFFFFFFF)
                rodata_pc += 4
            continue

        # 普通指令行
        if section == "text":
            text_raw.append(('CODE', line))

    # ── 构建标签字节地址表（rodata 部分）────────────────────────────────────
    labels = {}
    for lbl, offset in rodata_labels.items():
        labels[lbl] = rodata_base + offset

    # ── 注入启动存根：li sp, STACK_TOP ──────────────────────────────────────
    startup_code = []
    if stack_top != 0:
        if -2048 <= stack_top < 2048:
            startup_code = [('CODE', f"addi sp,x0,{stack_top}")]
        else:
            h = hi20(stack_top); l = lo12(stack_top)
            startup_code = [('CODE', f"lui sp,{h}"),
                            ('CODE', f"addi sp,sp,{l}")]

    text_raw = startup_code + text_raw

    # ── 第一遍文本：展开伪指令，给每条真实指令分配字节PC，收集标签 ──────────
    instructions = []  # (byte_pc, orig_mn, orig_args, [real_insts])
    inst_idx = 0

    for item_type, item_val in text_raw:
        if item_type == 'LABEL':
            labels[item_val] = inst_idx * BYTES_PER_INST
            continue
        # CODE
        line = item_val
        m = re.match(r'([\w.]+)(.*)', line)
        if not m: continue
        mn   = m.group(1).strip().lower()
        args = m.group(2).strip().lstrip(',').strip()

        expanded = expand_pseudo(mn, args)
        for (emn, eargs) in expanded:
            byte_pc = inst_idx * BYTES_PER_INST
            instructions.append((byte_pc, emn, eargs, mn, args))
            inst_idx += 1

    total_insts = len(instructions)
    total_slots = total_insts * SLOTS_PER_INST
    halt_byte_pc = (total_insts - 1) * BYTES_PER_INST

    # ── 第二遍：编码 ─────────────────────────────────────────────────────────
    encoded = []
    for (byte_pc, emn, eargs, orig_mn, orig_args) in instructions:
        slot_idx = byte_pc // BYTES_PER_SLOT
        try:
            word = encode_one(emn, eargs, byte_pc, labels)
        except Exception as e:
            raise RuntimeError(
                f"\n[编码错误] byte_pc={byte_pc}  {orig_mn} {orig_args}\n"
                f"  展开为: {emn} {eargs}\n  {e}"
            )
        encoded.append((byte_pc, slot_idx, word, orig_mn, orig_args, emn, eargs))

    # ── 打印汇总 ─────────────────────────────────────────────────────────────
    print(f"\n{'='*60}")
    print(f" 汇编成功")
    print(f"  真实指令数 : {total_insts}")
    print(f"  Icache slots: {total_slots}  (需要 Icache ≥ {total_slots} words)")
    print(f"  HALT byte PC: {halt_byte_pc}  (slot {halt_byte_pc//4})")
    print(f"  STACK_TOP   : 0x{stack_top:04X} = {stack_top}")
    print(f"  RODATA_BASE : 0x{rodata_base:04X} = {rodata_base}  → Dcache word {rodata_base//4}")
    if rodata_data:
        print(f"  .rodata 数据: {len(rodata_data)} words → Dcache[{rodata_base//4}..{rodata_base//4+len(rodata_data)-1}]")
    print(f"\n  标签地址:")
    for k, v in sorted(labels.items(), key=lambda x: x[1]):
        if v < rodata_base:  # text 标签
            s = v // BYTES_PER_SLOT
            print(f"    {k:25s} byte={v:5d}  slot={s:4d}")
        else:                # rodata 标签
            print(f"    {k:25s} byte=0x{v:04X}  Dcache word {v//4}")
    print(f"{'='*60}\n")

    # ── 生成 Listing ─────────────────────────────────────────────────────────
    # slot → 标签名映射
    slot2lbl = {}
    for lbl, bpc in labels.items():
        if bpc < rodata_base:
            slot2lbl.setdefault(bpc // BYTES_PER_SLOT, []).append(lbl)

    with open(stem + ".listing", "w", encoding="utf-8") as lf:
        lf.write(f"RV32I Listing — {os.path.basename(src_path)}\n")
        lf.write(f"  RODATA_BASE=0x{rodata_base:04X}  STACK_TOP=0x{stack_top:04X}\n")
        lf.write(f"  {total_insts} insts  {total_slots} slots  HALT byte PC={halt_byte_pc}\n")
        lf.write("─"*72 + "\n")
        lf.write(f"{'BytePC':>7} {'Slot':>5}  {'Hex':>10}  {'Assembly'}\n")
        lf.write("─"*72 + "\n")
        for (byte_pc, slot_idx, word, orig_mn, orig_args, emn, eargs) in encoded:
            # 标签
            for lbl in slot2lbl.get(slot_idx, []):
                lf.write(f"{'':>7} {'':>5}  {'':>10}  <{lbl}>:\n")
            asm_str = f"{orig_mn} {orig_args}".strip()
            real_str = f"{emn} {eargs}".strip() if (emn != orig_mn or eargs != orig_args) else ""
            expand_note = f"  [{real_str}]" if real_str and real_str != asm_str else ""
            lf.write(f"{byte_pc:7d} {slot_idx:5d}  0x{word:08X}  {asm_str}{expand_note}\n")
            for k in range(1, SLOTS_PER_INST):
                lf.write(f"{'':>7} {slot_idx+k:5d}  0x{NOP_WORD:08X}  (NOP)\n")
        lf.write("─"*72 + "\n")
        lf.write(f"Total slots: {total_slots}\n")

    # ── 生成 Verilog .vh ─────────────────────────────────────────────────────
    with open(stem + ".vh", "w", encoding="utf-8") as vf:
        vf.write(f"// {'='*58}\n")
        vf.write(f"// Auto-generated by rv32i_asm.py\n")
        vf.write(f"// Source : {os.path.basename(src_path)}\n")
        vf.write(f"// Insts  : {total_insts}   Slots: {total_slots}\n")
        vf.write(f"// HALT byte PC = {halt_byte_pc}\n")
        vf.write(f"// STACK_TOP    = 0x{stack_top:04X} = {stack_top}\n")
        vf.write(f"// RODATA_BASE  = 0x{rodata_base:04X} → Dcache word {rodata_base//4}\n")
        if rodata_data:
            vf.write(f"// Sorted result location (if bubble sort):\n")
            # 尝试估算 array 起始（适用于 GCC 冒泡排序）
            # t0 = s0 - 44, s0 = STACK_TOP - 8 + 4 = STACK_TOP - 4
            s0_est = stack_top - 4
            arr_est = s0_est - 44
            vf.write(f"//   s0 ≈ 0x{s0_est:04X}, array_base ≈ 0x{arr_est:04X} "
                     f"→ Dcache word {arr_est//4} .. {arr_est//4 + len(rodata_data) - 1}\n")
        vf.write(f"// {'='*58}\n\n")

        # ── load_icache task ──────────────────────────────────────────────────
        vf.write("// ────────────────────────────────────────────────────\n")
        vf.write("// Task: load_icache\n")
        vf.write("// ────────────────────────────────────────────────────\n")
        vf.write("task load_icache;\n")
        vf.write("integer _ki;\n")
        vf.write("begin\n")
        vf.write("    for (_ki = 0; _ki < 512; _ki = _ki + 1)\n")
        vf.write("        dut.Imm.mem[_ki] = 32'h00000013; // NOP\n\n")

        for (byte_pc, slot_idx, word, orig_mn, orig_args, emn, eargs) in encoded:
            lbls = slot2lbl.get(slot_idx, [])
            if lbls:
                vf.write(f"    // ── {'  '.join('<'+l+'>' for l in lbls)}"
                         f" (byte {byte_pc}) ──\n")
            asm_str = f"{orig_mn} {orig_args}".strip()
            vf.write(f"    dut.Imm.mem[{slot_idx:3d}] = 32'h{word:08X}; // {asm_str}\n")
            for k in range(1, SLOTS_PER_INST):
                vf.write(f"    dut.Imm.mem[{slot_idx+k:3d}] = 32'h{NOP_WORD:08X}; // NOP\n")

        vf.write(f"\n    $display(\"[ICACHE] {total_insts} insts, {total_slots} slots,"
                 f" HALT byte PC={halt_byte_pc}\");\n")
        vf.write("end\nendtask\n\n")

        # ── load_dcache task（rodata 预加载）─────────────────────────────────
        vf.write("// ────────────────────────────────────────────────────\n")
        vf.write("// Task: load_dcache\n")
        if rodata_data:
            vf.write(f"// .rodata -> Dcache word {rodata_base//4}.."
                     f"{rodata_base//4+len(rodata_data)-1}\n")
        vf.write("// ★ 修改测试数据只需改此 task ★\n")
        vf.write("// ────────────────────────────────────────────────────\n")
        vf.write("task load_dcache;\n")
        vf.write("integer _kd;\n")
        vf.write("begin\n")
        vf.write("    for (_kd = 0; _kd < 512; _kd = _kd + 1)\n")
        vf.write("        dut.mm_stage_inst.Dmm.mem[_kd] = 32'h00000000;\n\n")

        if rodata_data:
            vf.write(f"    // .rodata 段数据 (.LC0 等) → Dcache word {rodata_base//4} 起\n")
            vf.write(f"    // ★ 修改测试输入数组请改这里 ★\n")
            base_word = rodata_base // 4
            for idx, val in enumerate(rodata_data):
                vf.write(f"    dut.mm_stage_inst.Dmm.mem[{base_word+idx}]"
                         f" = 32'h{val & 0xFFFFFFFF:08X};"
                         f" // {val if val < 0x80000000 else val - 0x100000000}\n")
        else:
            vf.write("    // 无 .rodata；如需预设数据请在此添加\n")

        vf.write(f"\n    $display(\"[DCACHE] 数据预加载完成\");\n")
        vf.write("end\nendtask\n")

    print(f"[输出] {stem}.listing")
    print(f"[输出] {stem}.vh")

    # 返回关键参数供 TB 生成使用
    return {
        "halt_byte_pc": halt_byte_pc,
        "total_slots":  total_slots,
        "rodata_base":  rodata_base,
        "rodata_words": len(rodata_data),
        "stack_top":    stack_top,
        "labels":       labels,
    }

# ─────────────────────────────────────────────────────────────────────────────
#  命令行入口
# ─────────────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="RV32I Assembler for Early-Branch Pipeline")
    parser.add_argument("src",   help="汇编源文件 (.asm / .s)")
    parser.add_argument("--rodata", default=None, help=f"rodata 字节基址（默认 0x{DEFAULT_RODATA_BASE:X}）")
    parser.add_argument("--stack",  default=None, help=f"sp 初始值（默认 0x{DEFAULT_STACK_TOP:X}）")
    args = parser.parse_args()

    rodata_base = int(args.rodata, 16) if args.rodata else DEFAULT_RODATA_BASE
    stack_top   = int(args.stack,  16) if args.stack  else DEFAULT_STACK_TOP

    assemble(args.src, rodata_base=rodata_base, stack_top=stack_top)