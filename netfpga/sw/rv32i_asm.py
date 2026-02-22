#!/usr/bin/env python3
"""
rv32i_asm.py  —  RV32I Assembler for Early-Branch Pipeline
=============================================================
每条真实指令后固定插入 2 个 NOP（3 slot/指令），适配无前递 5 级流水线。

【内存映射约定】
  Icache : byte addr 0 起，word index = byte[10:2]，存放指令
  Dcache : byte addr 0 起，word index = byte[10:2]，存放数据
  .text   → Icache（自动 NOP padding，3 slot/指令）
  .rodata → Dcache 预加载，起始字节地址 = RODATA_BASE（默认 0x400）
  stack   → Dcache，sp 初始值 = STACK_TOP（默认 0x300，向低地址增长）

【命令行】
  python rv32i_asm.py  source.asm
  python rv32i_asm.py  source.asm  --rodata 0x400  --stack 0x300
  python rv32i_asm.py  source.asm  --imem imem.hex  --dmem dmem.hex

【输出文件】
  <stem>.listing  — 地址/hex/汇编对照表
  <stem>.vh       — Verilog task：load_icache + load_dcache
  imem.hex        — 指令内存 hex（供 pip_reg 脚本加载）
  dmem.hex        — 数据内存 hex（供 pip_reg 脚本加载）

【imem.hex / dmem.hex 格式】
  每行：0x<32bit_word>  # 注释
  顺序列出（无地址字段），pip_reg 从指定 base word 开始自动递增写入。
"""

import re, sys, os, argparse

# ─────────────────────────────────────────────────────────────────────────────
#  用户可调参数
# ─────────────────────────────────────────────────────────────────────────────
DEFAULT_RODATA_BASE = 0x400
DEFAULT_STACK_TOP   = 0x300
SLOTS_PER_INST      = 3          # 每条真实指令占的 word slot（1 指令 + 2 NOP）
BYTES_PER_SLOT      = 4
BYTES_PER_INST      = SLOTS_PER_INST * BYTES_PER_SLOT   # = 12
NOP_WORD            = 0x00000013  # addi x0,x0,0
HALT_WORD           = 0x00000063  # beq x0,x0,0（自跳转 HALT）

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
#  指令表
# ─────────────────────────────────────────────────────────────────────────────
INST = {
    "add":  ("R",0x33,0,0x00), "sub":  ("R",0x33,0,0x20),
    "sll":  ("R",0x33,1,0x00), "slt":  ("R",0x33,2,0x00),
    "sltu": ("R",0x33,3,0x00), "xor":  ("R",0x33,4,0x00),
    "srl":  ("R",0x33,5,0x00), "sra":  ("R",0x33,5,0x20),
    "or":   ("R",0x33,6,0x00), "and":  ("R",0x33,7,0x00),
    "addi": ("I",0x13,0), "slti": ("I",0x13,2), "sltiu":("I",0x13,3),
    "xori": ("I",0x13,4), "ori":  ("I",0x13,6), "andi": ("I",0x13,7),
    "slli": ("IS",0x13,1,0x00), "srli": ("IS",0x13,5,0x00), "srai": ("IS",0x13,5,0x20),
    "lb":("I",0x03,0), "lh":("I",0x03,1), "lw":("I",0x03,2),
    "lbu":("I",0x03,4), "lhu":("I",0x03,5),
    "sb":("S",0x23,0), "sh":("S",0x23,1), "sw":("S",0x23,2),
    "beq":("B",0x63,0), "bne":("B",0x63,1),
    "blt":("B",0x63,4), "bge":("B",0x63,5),
    "bltu":("B",0x63,6), "bgeu":("B",0x63,7),
    "lui":("U",0x37), "auipc":("U",0x17),
    "jal":("J",0x6F),
    "jalr":("I",0x67,0),
    "ecall":("SYS",0x73,0), "ebreak":("SYS",0x73,1),
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
    return (-1 if neg else 1) * int(s, base)

def hi20(addr): return ((addr + 0x800) >> 12) & 0xFFFFF
def lo12(addr):
    v = addr & 0xFFF
    return v - 0x1000 if v >= 0x800 else v

def split_args(s):
    s = re.sub(r'(-?[\w.]+)\((\w+)\)', r'\1,\2', s)
    parts = re.split(r'[\s,]+', s.strip())
    return [p for p in parts if p]

def resolve_hi_lo(arg, labels):
    arg = arg.strip()
    m_hi = re.match(r'%hi\(([^)]+)\)', arg)
    m_lo = re.match(r'%lo\(([^)]+)\)', arg)
    if m_hi:
        lbl = m_hi.group(1).strip()
        if lbl not in labels: raise ValueError(f"未定义标签: {lbl!r} (用于 %hi)")
        return hi20(labels[lbl])
    if m_lo:
        lbl = m_lo.group(1).strip()
        if lbl not in labels: raise ValueError(f"未定义标签: {lbl!r} (用于 %lo)")
        return lo12(labels[lbl])
    return parse_int(arg)

# ─────────────────────────────────────────────────────────────────────────────
#  伪指令展开
# ─────────────────────────────────────────────────────────────────────────────
def expand_pseudo(mn, args):
    tok = split_args(args) if args else []

    if mn == "nop":   return [("addi","x0,x0,0")]
    if mn == "ret":   return [("_HALT","")]

    if mn == "li":
        rd_ = tok[0]; imm = parse_int(tok[1])
        if -2048 <= imm < 2048:
            return [("addi", f"{rd_},x0,{imm}")]
        h = hi20(imm); l = lo12(imm)
        return [("lui", f"{rd_},{h}"), ("addi", f"{rd_},{rd_},{l}")]

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
    if mn == "_HALT": return HALT_WORD
    tok = split_args(args_str) if args_str else []

    def lbl_offset(name):
        if name not in labels:
            raise ValueError(f"未定义标签: {name!r}  (at byte_pc={byte_pc})")
        return labels[name] - byte_pc

    if mn not in INST:
        raise ValueError(f"未知指令: {mn!r}  (byte_pc={byte_pc})")

    info = INST[mn]; fmt = info[0]

    if fmt == "R":
        _, opc, f3, f7 = info
        rd, rs1, rs2 = R(tok[0]), R(tok[1]), R(tok[2])
        return (f7<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|opc

    if fmt == "I":
        _, opc, f3 = info
        if mn in ("lw","lh","lb","lbu","lhu","jalr"):
            rd = R(tok[0]); imm = parse_int(tok[1]); rs1 = R(tok[2])
        else:
            rd = R(tok[0]); rs1 = R(tok[1]); imm = resolve_hi_lo(tok[2], labels)
        return ((imm & 0xFFF)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|opc

    if fmt == "IS":
        _, opc, f3, f7 = info
        rd = R(tok[0]); rs1 = R(tok[1]); shamt = parse_int(tok[2]) & 0x1F
        return (f7<<25)|(shamt<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|opc

    if fmt == "S":
        _, opc, f3 = info
        rs2 = R(tok[0]); imm = parse_int(tok[1]) & 0xFFF; rs1 = R(tok[2])
        return ((imm>>5)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|((imm&0x1F)<<7)|opc

    if fmt == "B":
        _, opc, f3 = info
        rs1 = R(tok[0]); rs2 = R(tok[1]); imm = lbl_offset(tok[2])
        return (((imm>>12)&1)<<31)|(((imm>>5)&0x3F)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(((imm>>1)&0xF)<<8)|(((imm>>11)&1)<<7)|opc

    if fmt == "U":
        _, opc = info
        rd = R(tok[0]); imm = resolve_hi_lo(tok[1], labels) & 0xFFFFF
        return (imm<<12)|(rd<<7)|opc

    if fmt == "J":
        _, opc = info
        rd = R(tok[0]); imm = lbl_offset(tok[1])
        return (((imm>>20)&1)<<31)|(((imm>>1)&0x3FF)<<21)|(((imm>>11)&1)<<20)|(((imm>>12)&0xFF)<<12)|(rd<<7)|opc

    if fmt == "SYS":
        _, opc, code = info
        return (code<<20)|opc

    raise ValueError(f"未知格式: {fmt}")

# ─────────────────────────────────────────────────────────────────────────────
#  GNU 指令过滤
# ─────────────────────────────────────────────────────────────────────────────
def should_skip(line):
    if not line or line.startswith('//'): return True
    return bool(re.match(r'^\.(file|option|attribute|globl|type|size|ident)', line))

# ─────────────────────────────────────────────────────────────────────────────
#  主汇编流程
# ─────────────────────────────────────────────────────────────────────────────
def assemble(src_path,
             rodata_base=DEFAULT_RODATA_BASE,
             stack_top=DEFAULT_STACK_TOP,
             imem_path="imem.hex",
             dmem_path="dmem.hex"):

    stem = os.path.splitext(src_path)[0]

    # ── 读取 & 预处理 ─────────────────────────────────────────────────────────
    with open(src_path, encoding="utf-8", errors="replace") as f:
        raw = f.readlines()
    lines = []
    for line in raw:
        line = re.split(r'(?<!\S)#|//|@', line)[0].strip()
        if line: lines.append(line)

    # ── 分段收集 ──────────────────────────────────────────────────────────────
    section       = "text"
    text_raw      = []
    rodata_data   = []
    rodata_labels = {}
    rodata_pc     = 0

    for line in lines:
        lo = line.lower()
        if lo.startswith('.section') and '.rodata' in lo: section = "rodata"; continue
        if lo in ('.text',) or lo.startswith('.text '): section = "text"; continue
        if lo == '.data':   section = "data";   continue
        if lo == '.rodata': section = "rodata"; continue
        if should_skip(line): continue
        if re.match(r'\.(align|p2align|balign)\s', lo): continue

        if line.endswith(':') or (re.match(r'^[\w.]+\s*:', line) and not line.startswith('.')):
            lbl  = re.match(r'^([\w.]+)\s*:', line).group(1)
            rest = line[line.index(':')+1:].strip()
            if section == "rodata":
                rodata_labels[lbl] = rodata_pc
            else:
                text_raw.append(('LABEL', lbl))
            if rest:
                text_raw.append(('CODE', rest))
            continue

        if lo.startswith('.word') and section == "rodata":
            val = parse_int(line.split(None, 1)[1].strip())
            rodata_data.append(val & 0xFFFFFFFF)
            rodata_pc += 4
            continue

        if section == "text":
            text_raw.append(('CODE', line))

    # ── 注入启动存根：li sp, STACK_TOP ───────────────────────────────────────
    startup = []
    if stack_top != 0:
        if -2048 <= stack_top < 2048:
            startup = [('CODE', f"addi sp,x0,{stack_top}")]
        else:
            h = hi20(stack_top); l = lo12(stack_top)
            startup = [('CODE', f"lui sp,{h}"), ('CODE', f"addi sp,sp,{l}")]
    text_raw = startup + text_raw

    # ── Pass 1：展开伪指令，分配字节 PC，收集标签 ────────────────────────────
    labels = {}
    for lbl, offset in rodata_labels.items():
        labels[lbl] = rodata_base + offset

    instructions = []   # (byte_pc, emn, eargs, orig_mn, orig_args)
    inst_idx = 0

    for item_type, item_val in text_raw:
        if item_type == 'LABEL':
            labels[item_val] = inst_idx * BYTES_PER_INST
            continue
        m = re.match(r'([\w.]+)(.*)', item_val)
        if not m: continue
        mn   = m.group(1).strip().lower()
        args = m.group(2).strip().lstrip(',').strip()
        for (emn, eargs) in expand_pseudo(mn, args):
            byte_pc = inst_idx * BYTES_PER_INST
            instructions.append((byte_pc, emn, eargs, mn, args))
            inst_idx += 1

    total_insts = len(instructions)
    if total_insts == 0:
        print("[WARN] 没有找到任何指令"); return {}

    total_slots  = total_insts * SLOTS_PER_INST
    halt_byte_pc = (total_insts - 1) * BYTES_PER_INST

    # ── Pass 2：编码 ──────────────────────────────────────────────────────────
    encoded = []
    for (byte_pc, emn, eargs, orig_mn, orig_args) in instructions:
        slot_idx = byte_pc // BYTES_PER_SLOT
        try:
            word = encode_one(emn, eargs, byte_pc, labels)
        except Exception as e:
            raise RuntimeError(
                f"\n[编码错误] byte_pc={byte_pc}  {orig_mn} {orig_args}\n"
                f"  展开为: {emn} {eargs}\n  {e}")
        encoded.append((byte_pc, slot_idx, word, orig_mn, orig_args, emn, eargs))

    # ── 打印汇总 ──────────────────────────────────────────────────────────────
    print(f"\n{'='*60}")
    print(f" 汇编成功（固定 2 NOP / 指令）")
    print(f"  真实指令数  : {total_insts}")
    print(f"  总 slots    : {total_slots}")
    print(f"  HALT byte PC: {halt_byte_pc}  (slot {halt_byte_pc//4})")
    print(f"  STACK_TOP   : 0x{stack_top:04X} = {stack_top}")
    print(f"  RODATA_BASE : 0x{rodata_base:04X} → Dcache word {rodata_base//4}")
    if rodata_data:
        print(f"  .rodata     : {len(rodata_data)} words → "
              f"Dcache[{rodata_base//4}..{rodata_base//4+len(rodata_data)-1}]")
    print(f"\n  标签地址:")
    for k, v in sorted(labels.items(), key=lambda x: x[1]):
        if v < rodata_base:
            print(f"    {k:25s} byte={v:5d}  slot={v//4:4d}")
        else:
            print(f"    {k:25s} byte=0x{v:04X}  Dcache word {v//4}")
    print(f"{'='*60}\n")

    # ── slot → 标签名映射（用于 listing / vh 注释）──────────────────────────
    slot2lbl = {}
    for lbl, bpc in labels.items():
        if bpc < rodata_base:
            slot2lbl.setdefault(bpc // BYTES_PER_SLOT, []).append(lbl)

    # ── 生成 Listing ──────────────────────────────────────────────────────────
    with open(stem + ".listing", "w", encoding="utf-8") as lf:
        lf.write(f"RV32I Listing — {os.path.basename(src_path)}\n")
        lf.write(f"  RODATA_BASE=0x{rodata_base:04X}  STACK_TOP=0x{stack_top:04X}\n")
        lf.write(f"  {total_insts} insts  {total_slots} slots  HALT byte PC={halt_byte_pc}\n")
        lf.write("─"*72 + "\n")
        lf.write(f"{'BytePC':>7} {'Slot':>5}  {'Hex':>10}  Assembly\n")
        lf.write("─"*72 + "\n")
        for (byte_pc, slot_idx, word, orig_mn, orig_args, emn, eargs) in encoded:
            for lbl in slot2lbl.get(slot_idx, []):
                lf.write(f"{'':>7} {'':>5}  {'':>10}  <{lbl}>:\n")
            asm_str  = f"{orig_mn} {orig_args}".strip()
            real_str = f"{emn} {eargs}".strip()
            expand   = f"  [{real_str}]" if real_str != asm_str else ""
            lf.write(f"{byte_pc:7d} {slot_idx:5d}  0x{word:08X}  {asm_str}{expand}\n")
            for k in range(1, SLOTS_PER_INST):
                lf.write(f"{'':>7} {slot_idx+k:5d}  0x{NOP_WORD:08X}  (NOP)\n")
        lf.write("─"*72 + "\n")
        lf.write(f"Total slots: {total_slots}\n")

    # ── 生成 Verilog .vh ──────────────────────────────────────────────────────
    with open(stem + ".vh", "w", encoding="utf-8") as vf:
        vf.write(f"// {'='*58}\n")
        vf.write(f"// Auto-generated by rv32i_asm.py\n")
        vf.write(f"// Source : {os.path.basename(src_path)}\n")
        vf.write(f"// Insts  : {total_insts}   Slots: {total_slots}\n")
        vf.write(f"// HALT byte PC = {halt_byte_pc}  (slot {halt_byte_pc//4})\n")
        vf.write(f"// STACK_TOP    = 0x{stack_top:04X} = {stack_top}\n")
        vf.write(f"// RODATA_BASE  = 0x{rodata_base:04X} → Dcache word {rodata_base//4}\n")
        if rodata_data:
            s0_est  = stack_top - 4
            arr_est = s0_est - 44
            vf.write(f"// Array result (bubble sort): arr_base≈0x{arr_est:04X}"
                     f" → Dcache word {arr_est//4}..{arr_est//4+len(rodata_data)-1}\n")
        vf.write(f"// {'='*58}\n\n")

        vf.write("task load_icache;\n")
        vf.write("integer _ki;\n")
        vf.write("begin\n")
        vf.write("    for (_ki = 0; _ki < 512; _ki = _ki + 1)\n")
        vf.write("        dut.Imm.mem[_ki] = 32'h00000013; // NOP\n\n")
        for (byte_pc, slot_idx, word, orig_mn, orig_args, emn, eargs) in encoded:
            lbls = slot2lbl.get(slot_idx, [])
            if lbls:
                vf.write(f"    // ── {'  '.join('<'+l+'>' for l in lbls)} (byte {byte_pc}) ──\n")
            asm_str = f"{orig_mn} {orig_args}".strip()
            vf.write(f"    dut.Imm.mem[{slot_idx:3d}] = 32'h{word:08X}; // {asm_str}\n")
            for k in range(1, SLOTS_PER_INST):
                vf.write(f"    dut.Imm.mem[{slot_idx+k:3d}] = 32'h{NOP_WORD:08X}; // NOP\n")
        vf.write(f"\n    $display(\"[ICACHE] {total_insts} insts, {total_slots} slots,"
                 f" HALT byte PC={halt_byte_pc}\");\n")
        vf.write("end\nendtask\n\n")

        vf.write("task load_dcache;\n")
        vf.write("integer _kd;\n")
        vf.write("begin\n")
        vf.write("    for (_kd = 0; _kd < 512; _kd = _kd + 1)\n")
        vf.write("        dut.mm_stage_inst.Dmm.mem[_kd] = 32'h00000000;\n\n")
        if rodata_data:
            vf.write(f"    // .rodata → Dcache word {rodata_base//4} 起\n")
            vf.write(f"    // ★ 修改测试输入请改这里 ★\n")
            bw = rodata_base // 4
            for idx, val in enumerate(rodata_data):
                sv = val if val < 0x80000000 else val - 0x100000000
                vf.write(f"    dut.mm_stage_inst.Dmm.mem[{bw+idx}]"
                         f" = 32'h{val & 0xFFFFFFFF:08X}; // {sv}\n")
        else:
            vf.write("    // 无 .rodata；如需预设数据请在此添加\n")
        vf.write(f"\n    $display(\"[DCACHE] 数据预加载完成\");\n")
        vf.write("end\nendtask\n")

    print(f"[输出] {stem}.listing")
    print(f"[输出] {stem}.vh")

    # ── 生成 imem.hex ─────────────────────────────────────────────────────────
    # 格式：每行 0x<WORD>，顺序列出，pip_reg 从 word 0 起自动递增地址
    with open(imem_path, "w", encoding="utf-8") as hf:
        hf.write(f"# imem.hex — generated from {os.path.basename(src_path)}\n")
        hf.write(f"# {total_insts} insts  {total_slots} slots\n")
        hf.write(f"# HALT byte PC={halt_byte_pc}  (word slot {halt_byte_pc//4})\n")
        hf.write(f"# STACK_TOP=0x{stack_top:04X}  RODATA_BASE=0x{rodata_base:04X}\n")
        hf.write(f"# Format: 0x<word>  (sequential, no address field)\n")
        hf.write("#\n")
        for (byte_pc, slot_idx, word, orig_mn, orig_args, emn, eargs) in encoded:
            lbls = slot2lbl.get(slot_idx, [])
            if lbls:
                hf.write(f"# <{'  '.join(lbls)}> (byte {byte_pc}, slot {slot_idx})\n")
            asm_str = f"{orig_mn} {orig_args}".strip()
            hf.write(f"0x{word:08X}  # [{slot_idx}] {asm_str}\n")
            for k in range(1, SLOTS_PER_INST):
                hf.write(f"0x{NOP_WORD:08X}  # [{slot_idx+k}] NOP\n")

    print(f"[输出] {imem_path}")

    # ── 生成 dmem.hex ─────────────────────────────────────────────────────────
    # 格式：每行 0x<WORD>，顺序列出
    # pip_reg 以 rodata_base//4 为起始 word 地址自动递增写入
    with open(dmem_path, "w", encoding="utf-8") as hf:
        hf.write(f"# dmem.hex — generated from {os.path.basename(src_path)}\n")
        hf.write(f"# .rodata: {len(rodata_data)} words\n")
        hf.write(f"# Dcache word base = {rodata_base//4}  (RODATA_BASE=0x{rodata_base:04X})\n")
        hf.write(f"# pip_reg usage: load dmem starting from word addr {rodata_base//4}\n")
        hf.write(f"# Format: 0x<word>  (sequential, no address field)\n")
        hf.write("#\n")
        if rodata_data:
            for idx, val in enumerate(rodata_data):
                sv = val if val < 0x80000000 else val - 0x100000000
                hf.write(f"0x{val & 0xFFFFFFFF:08X}  # [{rodata_base//4 + idx}] {sv}\n")
        else:
            hf.write("# (no .rodata data)\n")

    print(f"[输出] {dmem_path}")

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
    parser = argparse.ArgumentParser(
        description="RV32I Assembler for Early-Branch Pipeline (fixed 2-NOP per inst)")
    parser.add_argument("src",      help="汇编源文件 (.asm / .s)")
    parser.add_argument("--rodata", default=None,
                        help=f"rodata 字节基址（默认 0x{DEFAULT_RODATA_BASE:X}）")
    parser.add_argument("--stack",  default=None,
                        help=f"sp 初始值（默认 0x{DEFAULT_STACK_TOP:X}）")
    parser.add_argument("--imem",   default="imem.hex",
                        help="imem.hex 输出路径（默认 imem.hex）")
    parser.add_argument("--dmem",   default="dmem.hex",
                        help="dmem.hex 输出路径（默认 dmem.hex）")
    args = parser.parse_args()

    rodata_base = int(args.rodata, 16) if args.rodata else DEFAULT_RODATA_BASE
    stack_top   = int(args.stack,  16) if args.stack  else DEFAULT_STACK_TOP

    assemble(args.src,
             rodata_base=rodata_base,
             stack_top=stack_top,
             imem_path=args.imem,
             dmem_path=args.dmem)