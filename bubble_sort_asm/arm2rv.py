#!/usr/bin/env python3
"""
ARM (armv4t/arm7tdmi) → RV32I Assembly Translator
将 GCC 生成的 ARM 汇编自动翻译为 RISC-V RV32I 汇编。

核心挑战：
  1. ARM 条件码系统 (CPSR)            →  RV 合并比较-分支
  2. ldmia / stmia 批量传输           →  展开为多条 lw / sw
  3. push / pop 寄存器列表            →  展开并调整栈指针
  4. PC 相对字面量池（符号地址）       →  lui + addi (%hi/%lo)
  5. PC 相对字面量池（数值常量）       →  li 立即数内联
  6. 前索引写回  str rd,[rn,#imm]!    →  addi rn,rn,imm + sw rd,0(rn)
  7. 后索引写回  ldr rd,[rn],#imm     →  lw rd,0(rn) + addi rn,rn,imm
  8. smull / umull / smlal            →  mul + mulh[u]

用法:
  python3 arm_to_rv32i.py input_arm.s [output_rv32i.s]
"""

import re
import sys
from typing import Dict, List, Optional, Set, Tuple

# ═══════════════════════════════════════════════════════════════════════════
#  寄存器映射  ARM → RV32I  (尽量保持 ABI 语义一致)
# ═══════════════════════════════════════════════════════════════════════════
_REG_MAP: Dict[str, str] = {
    'r0': 'a0', 'r1': 'a1', 'r2': 'a2',  'r3': 'a3',
    'r4': 'a4', 'r5': 'a5', 'r6': 'a6',  'r7': 'a7',
    'r8': 's1', 'r9': 's2', 'r10': 's3', 'r11': 's4',
    'r12': 't0', 'r13': 'sp', 'r14': 'ra', 'r15': 't6',
    'fp':  's0', 'ip':  't0', 'sp':  'sp', 'lr':  'ra', 'pc':  't6',
}

def rmap(arm: str) -> str:
    return _REG_MAP.get(arm.strip().lower().rstrip('!'), arm.strip())


# ═══════════════════════════════════════════════════════════════════════════
#  操作数分割（遵守 [] 和 {} 嵌套）
# ═══════════════════════════════════════════════════════════════════════════
def split_ops(s: str) -> List[str]:
    result, cur, depth = [], [], 0
    for ch in s:
        if ch in '[{':   depth += 1; cur.append(ch)
        elif ch in ']}': depth -= 1; cur.append(ch)
        elif ch == ',' and depth == 0:
            result.append(''.join(cur).strip()); cur = []
        else:
            cur.append(ch)
    if cur:
        result.append(''.join(cur).strip())
    return [x for x in result if x]


# ═══════════════════════════════════════════════════════════════════════════
#  寄存器列表解析  {r0, r1-r3, fp, lr}
# ═══════════════════════════════════════════════════════════════════════════
_NAME_TO_IDX = {'fp': 11, 'ip': 12, 'sp': 13, 'lr': 14, 'pc': 15}
_IDX_TO_NAME = {v: k for k, v in _NAME_TO_IDX.items()}

def _reg_idx(r: str) -> int:
    r = r.lower().strip()
    if r in _NAME_TO_IDX: return _NAME_TO_IDX[r]
    m = re.match(r'^r(\d+)$', r)
    return int(m.group(1)) if m else -1

def _reg_from_idx(n: int) -> str:
    return _IDX_TO_NAME.get(n, f'r{n}')

def parse_reglist(s: str) -> List[str]:
    s = s.strip().strip('{}')
    result = []
    for token in re.split(r',\s*', s):
        token = token.strip()
        if '-' in token and not token.startswith('-'):
            lo_s, hi_s = token.split('-', 1)
            lo, hi = _reg_idx(lo_s.strip()), _reg_idx(hi_s.strip())
            result.extend(_reg_from_idx(i) for i in range(lo, hi + 1))
        else:
            result.append(token)
    return result


# ═══════════════════════════════════════════════════════════════════════════
#  内存寻址模式解析
# ═══════════════════════════════════════════════════════════════════════════
def parse_mem_full(mem_ops: List[str]) -> dict:
    """
    解析 ARM ldr/str 的内存操作数（完整版，处理写回）。

    输入为 split_ops 分割后、rd 之后的所有操作数列表，例如：
      ['[sp, #-4]!']           → 前索引写回
      ['[sp]', '#4']           → 后索引写回
      ['[fp, #-8]']            → 普通偏移
      ['[r3, #-40]']           → 普通偏移

    返回 dict：
      mode   : 'imm' | 'reg' | 'regshift'
      base   : RV 寄存器名
      offset : 偏移字符串（模式 imm）或寄存器名（模式 reg）
      shift_type, shift_amt  （模式 regshift）
      writeback : None | ('pre', delta_str) | ('post', delta_str)
    """
    raw = mem_ops[0].strip()

    # ── 判断写回类型 ─────────────────────────────────────────────────────
    writeback = None
    if raw.endswith('!'):
        # 前索引写回：[rn, #imm]!
        raw = raw[:-1]
        writeback_type = 'pre'
    elif len(mem_ops) > 1:
        # 后索引写回：[rn], #imm
        post = mem_ops[1].strip()
        writeback_type = 'post'
        writeback_delta = post.lstrip('#')
    else:
        writeback_type = None

    # ── 解析 [base, offset] ─────────────────────────────────────────────
    inner = raw.strip().strip('[]')
    parts = [p.strip() for p in inner.split(',')]
    base  = rmap(parts[0])

    if len(parts) == 1:
        mode, offset, shift_type, shift_amt = 'imm', '0', None, None
    elif parts[1].startswith('#'):
        mode, offset, shift_type, shift_amt = 'imm', parts[1][1:], None, None
    elif len(parts) >= 3:
        sm = re.match(r'(lsl|lsr|asr|ror)\s+#(\d+)',
                      ','.join(parts[2:]).strip(), re.I)
        if sm:
            mode       = 'regshift'
            offset     = rmap(parts[1])
            shift_type = sm.group(1).lower()
            shift_amt  = sm.group(2)
        else:
            mode, offset, shift_type, shift_amt = 'reg', rmap(parts[1]), None, None
    else:
        mode, offset, shift_type, shift_amt = 'reg', rmap(parts[1]), None, None

    # ── 组装写回信息 ─────────────────────────────────────────────────────
    if writeback_type == 'pre':
        # 前索引：偏移量就是写回量
        writeback = ('pre', offset if mode == 'imm' else None)
    elif writeback_type == 'post':
        writeback = ('post', writeback_delta)

    return {
        'mode':       mode,
        'base':       base,
        'offset':     offset,
        'shift_type': shift_type,
        'shift_amt':  shift_amt,
        'writeback':  writeback,
    }


# ═══════════════════════════════════════════════════════════════════════════
#  指令集翻译器主体
# ═══════════════════════════════════════════════════════════════════════════
class Translator:
    _COND_BRANCH: Dict[str, Tuple[str, bool]] = {
        'beq': ('beq',  False), 'bne': ('bne',  False),
        'blt': ('blt',  False), 'bge': ('bge',  False),
        'bgt': ('blt',  True),  'ble': ('bge',  True),
        'blo': ('bltu', False), 'bls': ('bgeu', True),
        'bhi': ('bltu', True),  'bhs': ('bgeu', False),
        'bcs': ('bgeu', False), 'bcc': ('bltu', False),
        'bpl': ('bge',  False), 'bmi': ('blt',  False),
    }

    _SHIFT_OPS = {
        'lsl': ('slli', 'sll'),
        'lsr': ('srli', 'srl'),
        'asr': ('srai', 'sra'),
    }

    _DROP = {
        '.cpu', '.eabi_attribute', '.arch', '.syntax', '.arm', '.thumb',
        '.fpu', '.code', '.force_thumb', '.thumb_func',
    }

    def __init__(self):
        self._out:            List[str]                  = []
        self._cmp:            Optional[Tuple[str, str]]  = None
        self._pool:           Dict[str, str]             = {}   # label → 符号名
        self._num_pool:       Dict[str, str]             = {}   # label → 数值字符串
        self._suppress_lines: Set[int]                   = set()

    # ── 公共入口 ─────────────────────────────────────────────────────────
    def translate(self, lines: List[str]) -> str:
        self._scan_literal_pool(lines)
        self._emit_rv_header()
        for idx, line in enumerate(lines):
            if idx not in self._suppress_lines:
                self._process_line(line)
        return '\n'.join(self._out) + '\n'

    def _emit(self, s: str):
        self._out.append(s)

    def _warn(self, msg: str):
        self._emit(f'\t# [WARNING] {msg}')

    # ── 第一遍：字面量池扫描 ──────────────────────────────────────────────
    def _scan_literal_pool(self, lines: List[str]):
        """
        扫描两类字面量池：
          .Lx: .word SYMBOL    → 符号地址池 _pool       → lui+addi
          .Lx: .word 12345     → 数值常量池 _num_pool   → li（内联，抑制原行）
        """
        i = 0
        while i < len(lines):
            m = re.match(r'^(\.L\w+)\s*:?\s*$', lines[i].strip())
            if m:
                label = m.group(1)
                j = i + 1
                while j < len(lines) and not lines[j].strip():
                    j += 1
                align_j = None
                if j < len(lines) and lines[j].strip().startswith('.align'):
                    align_j = j
                    j += 1
                if j < len(lines):
                    wm = re.match(r'^\s*\.word\s+(\S+)', lines[j])
                    if wm:
                        # 检查之后是否还有连续的 .word（多项数据数组不是字面量池）
                        k = j + 1
                        while k < len(lines) and not lines[k].strip():
                            k += 1
                        next_is_word = (k < len(lines) and
                                        bool(re.match(r'^\s*\.word\b', lines[k])))
                        if not next_is_word:
                            # 单项 .word：是字面量池，内联后抑制
                            val = wm.group(1)
                            self._suppress_lines.add(i)
                            if align_j is not None:
                                self._suppress_lines.add(align_j)
                            self._suppress_lines.add(j)
                            if re.match(r'^[\.a-zA-Z_]', val):
                                self._pool[label] = val       # 符号地址
                            else:
                                self._num_pool[label] = val   # 数值常量
            i += 1

    # ── RV32I 文件头 ──────────────────────────────────────────────────────
    def _emit_rv_header(self):
        self._emit('\t.option nopic')
        self._emit('\t.attribute arch, "rv32i2p0"')
        self._emit('\t.attribute unaligned_access, 0')
        self._emit('\t.attribute stack_align, 16')

    # ── 逐行处理 ─────────────────────────────────────────────────────────
    def _process_line(self, line: str):
        s = line.strip()
        if not s or s.startswith('@'):
            return

        lm = re.match(r'^([\.\w]+)\s*:', s)
        if lm:
            label = lm.group(1)
            self._emit(f'{label}:')
            rest = s[lm.end():].strip()
            if rest and not rest.startswith('@'):
                self._translate_instr_line(rest)
            return

        if s.startswith('.'):
            tok = s.split()[0].lower()
            if tok in self._DROP:
                return
            if tok == '.global':
                self._emit(line.rstrip().replace('.global', '.globl', 1))
            elif tok == '.file':
                self._emit(f'\t.file\t"translated_from_arm.s"')
            else:
                self._emit(line.rstrip())
            return

        self._translate_instr_line(s)

    def _translate_instr_line(self, s: str):
        s = re.sub(r'\s*@.*$', '', s).strip()
        if not s: return
        parts = s.split(None, 1)
        mnem  = parts[0].lower()
        ops_str = parts[1].strip() if len(parts) > 1 else ''
        self._dispatch(mnem, ops_str)

    # ═══════════════════════════════════════════════════════════════════════
    #  指令分发
    # ═══════════════════════════════════════════════════════════════════════
    def _dispatch(self, mnem: str, ops_str: str):
        ops = split_ops(ops_str)

        # ── 无条件转移 ───────────────────────────────────────────────────
        if mnem == 'b':
            self._emit(f'\tj\t{ops[0]}')
            self._cmp = None
            return

        if mnem == 'bl':
            self._emit(f'\tcall\t{ops[0]}')
            return

        if mnem == 'bx':
            r = rmap(ops[0]) if ops else 'ra'
            self._emit('\tret' if r == 'ra' else f'\tjr\t{r}')
            self._cmp = None
            return

        # ── 条件分支 ─────────────────────────────────────────────────────
        #
        # ARM:   cmp  r2, r3          CPSR ← r2 - r3
        #        ble  .L4             if r2 ≤ r3 goto .L4
        #
        # RV32I: bge  a3, a2, .L4    if a3 ≥ a2 goto .L4  （交换操作数）
        #
        if mnem in self._COND_BRANCH:
            label = ops[0]
            rv_br, swap = self._COND_BRANCH[mnem]
            if self._cmp:
                rs1, rs2 = self._cmp
                if swap:
                    rs1, rs2 = rs2, rs1
                self._emit(f'\t{rv_br}\t{rs1},{rs2},{label}')
                self._cmp = None
            else:
                self._warn(f'{mnem} 没有前置 cmp，默认与 zero 比较')
                self._emit(f'\t{rv_br}\tzero,zero,{label}')
            return

        # ── CMP ──────────────────────────────────────────────────────────
        if mnem in ('cmp', 'cmn'):
            rs1 = rmap(ops[0])
            op2 = ops[1]
            if op2.startswith('#'):
                imm = op2[1:]
                if imm == '0':
                    self._cmp = (rs1, 'zero')
                else:
                    self._emit(f'\tli\tt4,{imm}')
                    self._cmp = (rs1, 't4')
            else:
                self._cmp = (rs1, rmap(op2))
            return

        # ── MOV / MVN ────────────────────────────────────────────────────
        if mnem == 'mov':
            rd, src = rmap(ops[0]), ops[1]
            if src.startswith('#'):
                self._emit(f'\tli\t{rd},{src[1:]}')
            else:
                self._emit(f'\tmv\t{rd},{rmap(src)}')
            return

        if mnem == 'mvn':
            rd, src = rmap(ops[0]), ops[1]
            if src.startswith('#'):
                self._emit(f'\tli\t{rd},{~int(src[1:])}')
            else:
                self._emit(f'\tnot\t{rd},{rmap(src)}')
            return

        # ── 算术运算 ─────────────────────────────────────────────────────
        if mnem in ('add', 'adds'):
            rd, rn, op2 = rmap(ops[0]), rmap(ops[1]), ops[2]
            if op2.startswith('#'):
                self._emit(f'\taddi\t{rd},{rn},{op2[1:]}')
            else:
                self._emit(f'\tadd\t{rd},{rn},{rmap(op2)}')
            return

        if mnem in ('sub', 'subs'):
            rd, rn, op2 = rmap(ops[0]), rmap(ops[1]), ops[2]
            if op2.startswith('#'):
                self._emit(f'\taddi\t{rd},{rn},{-int(op2[1:])}')
            else:
                self._emit(f'\tsub\t{rd},{rn},{rmap(op2)}')
            return

        if mnem in ('rsb', 'rsbs'):
            rd, rn, op2 = rmap(ops[0]), rmap(ops[1]), ops[2]
            if op2 == '#0':
                self._emit(f'\tneg\t{rd},{rn}')
            else:
                self._emit(f'\tli\tt4,{op2[1:]}')
                self._emit(f'\tsub\t{rd},t4,{rn}')
            return

        if mnem in ('mul', 'muls'):
            rd, rn, rm = rmap(ops[0]), rmap(ops[1]), rmap(ops[2])
            self._emit(f'\tmul\t{rd},{rn},{rm}')
            return

        # ── smull / umull：64 位乘法 ──────────────────────────────────────
        #
        # ARM:   smull rdlo, rdhi, rn, rm   →  {rdhi:rdlo} = rn *s rm (64位)
        # RV32I: mul   rdlo, rn, rm         →  rdlo = 低32位
        #        mulh  rdhi, rn, rm         →  rdhi = 高32位（有符号）
        #
        # ARM:   umull rdlo, rdhi, rn, rm   →  同上，无符号
        # RV32I: mulhu rdhi, rn, rm
        #
        if mnem in ('smull', 'smulls'):
            rdlo, rdhi, rn, rm = (rmap(ops[i]) for i in range(4))
            self._emit(f'\tmul\t{rdlo},{rn},{rm}')
            self._emit(f'\tmulh\t{rdhi},{rn},{rm}')
            return

        if mnem in ('umull', 'umulls'):
            rdlo, rdhi, rn, rm = (rmap(ops[i]) for i in range(4))
            self._emit(f'\tmul\t{rdlo},{rn},{rm}')
            self._emit(f'\tmulhu\t{rdhi},{rn},{rm}')
            return

        # smlal: rdlo += (rn *s rm) 低32位，rdhi += 高32位（带累加）
        if mnem in ('smlal', 'smlals'):
            rdlo, rdhi, rn, rm = (rmap(ops[i]) for i in range(4))
            self._emit(f'\tmul\tt5,{rn},{rm}')
            self._emit(f'\tmulh\tt6,{rn},{rm}')
            self._emit(f'\tadd\t{rdlo},{rdlo},t5')
            # 处理低32位进位：if rdlo < t5 then rdhi++
            self._emit(f'\tsltu\tt5,{rdlo},t5')
            self._emit(f'\tadd\t{rdhi},{rdhi},t5')
            self._emit(f'\tadd\t{rdhi},{rdhi},t6')
            return

        if mnem == 'sdiv':
            rd, rn, rm = rmap(ops[0]), rmap(ops[1]), rmap(ops[2])
            self._emit(f'\tdiv\t{rd},{rn},{rm}')
            return

        if mnem == 'udiv':
            rd, rn, rm = rmap(ops[0]), rmap(ops[1]), rmap(ops[2])
            self._emit(f'\tdivu\t{rd},{rn},{rm}')
            return

        # ── 逻辑运算 ─────────────────────────────────────────────────────
        if mnem in ('and', 'ands'):
            rd, rn, op2 = rmap(ops[0]), rmap(ops[1]), ops[2]
            if op2.startswith('#'):
                self._emit(f'\tandi\t{rd},{rn},{op2[1:]}')
            else:
                self._emit(f'\tand\t{rd},{rn},{rmap(op2)}')
            return

        if mnem in ('orr', 'orrs'):
            rd, rn, op2 = rmap(ops[0]), rmap(ops[1]), ops[2]
            if op2.startswith('#'):
                self._emit(f'\tori\t{rd},{rn},{op2[1:]}')
            else:
                self._emit(f'\tor\t{rd},{rn},{rmap(op2)}')
            return

        if mnem in ('eor', 'eors'):
            rd, rn, op2 = rmap(ops[0]), rmap(ops[1]), ops[2]
            if op2.startswith('#'):
                self._emit(f'\txori\t{rd},{rn},{op2[1:]}')
            else:
                self._emit(f'\txor\t{rd},{rn},{rmap(op2)}')
            return

        if mnem == 'bic':
            rd, rn, op2 = rmap(ops[0]), rmap(ops[1]), ops[2]
            if op2.startswith('#'):
                self._emit(f'\tandi\t{rd},{rn},{~int(op2[1:])}')
            else:
                self._emit(f'\tnot\tt4,{rmap(op2)}')
                self._emit(f'\tand\t{rd},{rn},t4')
            return

        # ── 移位运算 ─────────────────────────────────────────────────────
        if mnem in self._SHIFT_OPS:
            imm_op, reg_op = self._SHIFT_OPS[mnem]
            rd, rn, op2 = rmap(ops[0]), rmap(ops[1]), ops[2]
            if op2.startswith('#'):
                self._emit(f'\t{imm_op}\t{rd},{rn},{op2[1:]}')
            else:
                self._emit(f'\t{reg_op}\t{rd},{rn},{rmap(op2)}')
            return

        if mnem == 'ror':
            rd, rn, op2 = rmap(ops[0]), rmap(ops[1]), ops[2]
            if op2.startswith('#'):
                amt = int(op2[1:])
                self._emit(f'\tsrli\tt4,{rn},{amt}')
                self._emit(f'\tslli\t{rd},{rn},{32 - amt}')
                self._emit(f'\tor\t{rd},{rd},t4')
            else:
                rv_amt = rmap(op2)
                self._emit(f'\tsrl\tt4,{rn},{rv_amt}')
                self._emit(f'\tli\tt5,32')
                self._emit(f'\tsub\tt5,t5,{rv_amt}')
                self._emit(f'\tsll\t{rd},{rn},t5')
                self._emit(f'\tor\t{rd},{rd},t4')
            return

        # ── 加载指令 ─────────────────────────────────────────────────────
        if mnem in ('ldr', 'ldrb', 'ldrh', 'ldrsb', 'ldrsh'):
            op_map = {'ldr': 'lw', 'ldrb': 'lbu', 'ldrh': 'lhu',
                      'ldrsb': 'lb', 'ldrsh': 'lh'}
            rv_op = op_map[mnem]
            rd  = rmap(ops[0])
            mem = ops[1]

            # ① PC 相对字面量池引用（符号地址池）
            if re.match(r'^\.L\w+$', mem):
                if mem in self._pool:
                    sym = self._pool[mem]
                    self._emit(f'\tlui\t{rd},%hi({sym})')
                    self._emit(f'\taddi\t{rd},{rd},%lo({sym})')
                elif mem in self._num_pool:
                    # 数值常量池：直接内联为 li（大常量由汇编器展开 lui+addi）
                    val = self._num_pool[mem]
                    self._emit(f'\tli\t{rd},{val}')
                else:
                    self._warn(f'未找到字面量池 {mem}，尝试 la 加载')
                    self._emit(f'\tla\t{rd},{mem}')
                return

            # ② 常规内存访问（含前/后索引写回）
            self._emit_load(rv_op, rd, ops[1:])
            return

        # ── 存储指令 ─────────────────────────────────────────────────────
        if mnem in ('str', 'strb', 'strh'):
            op_map = {'str': 'sw', 'strb': 'sb', 'strh': 'sh'}
            rv_op = op_map[mnem]
            rs = rmap(ops[0])
            self._emit_store(rv_op, rs, ops[1:])
            return

        # ── PUSH / POP ────────────────────────────────────────────────────
        if mnem == 'push':
            regs = parse_reglist(ops_str)
            n = len(regs)
            self._emit(f'\taddi\tsp,sp,{-4 * n}')
            for i, r in enumerate(regs):
                self._emit(f'\tsw\t{rmap(r)},{4 * i}(sp)')
            return

        if mnem == 'pop':
            regs = parse_reglist(ops_str)
            n = len(regs)
            for i, r in enumerate(regs):
                self._emit(f'\tlw\t{rmap(r)},{4 * i}(sp)')
            self._emit(f'\taddi\tsp,sp,{4 * n}')
            if 'pc' in [r.lower() for r in regs]:
                self._emit('\tret')
            return

        # ── LDM / STM 批量传输 ────────────────────────────────────────────
        if mnem in ('ldm', 'ldmia', 'ldmfd', 'ldmda', 'ldmdb', 'ldmib'):
            wb   = ops[0].endswith('!')
            base = rmap(ops[0].rstrip('!'))
            bi   = ops_str.index('{')
            regs = parse_reglist(ops_str[bi:])
            for i, r in enumerate(regs):
                self._emit(f'\tlw\t{rmap(r)},{4 * i}({base})')
            if wb:
                self._emit(f'\taddi\t{base},{base},{4 * len(regs)}')
            return

        if mnem in ('stm', 'stmia', 'stmea', 'stmda', 'stmdb', 'stmfd'):
            wb   = ops[0].endswith('!')
            base = rmap(ops[0].rstrip('!'))
            bi   = ops_str.index('{')
            regs = parse_reglist(ops_str[bi:])
            for i, r in enumerate(regs):
                self._emit(f'\tsw\t{rmap(r)},{4 * i}({base})')
            if wb:
                self._emit(f'\taddi\t{base},{base},{4 * len(regs)}')
            return

        # ── 其他 ─────────────────────────────────────────────────────────
        if mnem == 'nop':
            self._emit('\tnop')
            return

        if mnem in ('swi', 'svc'):
            self._emit(f'\tecall\t# {mnem} {ops_str}')
            return

        self._emit(f'\t# [UNTRANSLATED] {mnem} {ops_str}')

    # ═══════════════════════════════════════════════════════════════════════
    #  Load / Store 辅助（统一处理前索引写回、后索引写回、普通偏移）
    # ═══════════════════════════════════════════════════════════════════════
    #
    #  三种情形：
    #
    #  A. 普通偏移    ldr rd, [rn, #imm]
    #       → lw rd, imm(rn)
    #
    #  B. 前索引写回  ldr rd, [rn, #imm]!
    #       → addi rn, rn, imm        （先更新 base）
    #          lw   rd, 0(rn)
    #
    #  C. 后索引写回  ldr rd, [rn], #imm
    #       → lw   rd, 0(rn)          （先加载）
    #          addi rn, rn, imm       （再更新 base）
    #
    _SHIFT_TO_RV = {'lsl': 'slli', 'lsr': 'srli', 'asr': 'srai'}

    def _compute_addr(self, info: dict, tmp: str = 't5') -> str:
        """
        根据 parse_mem_full 结果计算有效地址。
        - 对于 imm 模式直接返回 'imm(base)' 字符串
        - 对于 reg/regshift 模式先 emit 地址计算指令，返回 '0(tmp)'
        """
        if info['mode'] == 'imm':
            return f"{info['offset']}({info['base']})"
        elif info['mode'] == 'reg':
            self._emit(f"\tadd\t{tmp},{info['base']},{info['offset']}")
            return f'0({tmp})'
        else:  # regshift
            rv_sh = self._SHIFT_TO_RV.get(info['shift_type'], 'slli')
            self._emit(f"\t{rv_sh}\t{tmp},{info['offset']},{info['shift_amt']}")
            self._emit(f"\tadd\t{tmp},{info['base']},{tmp}")
            return f'0({tmp})'

    def _emit_load(self, op: str, rd: str, mem_ops: List[str]):
        info = parse_mem_full(mem_ops)
        wb   = info['writeback']

        if wb and wb[0] == 'pre' and wb[1] is not None:
            # 前索引写回：先更新 base，再加载
            base  = info['base']
            delta = wb[1]
            self._emit(f'\taddi\t{base},{base},{delta}')
            self._emit(f'\t{op}\t{rd},0({base})')
        elif wb and wb[0] == 'post' and wb[1] is not None:
            # 后索引写回：先加载，再更新 base
            base  = info['base']
            delta = wb[1]
            self._emit(f'\t{op}\t{rd},0({base})')
            self._emit(f'\taddi\t{base},{base},{delta}')
        else:
            # 普通访问
            addr = self._compute_addr(info)
            self._emit(f'\t{op}\t{rd},{addr}')

    def _emit_store(self, op: str, rs: str, mem_ops: List[str]):
        info = parse_mem_full(mem_ops)
        wb   = info['writeback']

        if wb and wb[0] == 'pre' and wb[1] is not None:
            # 前索引写回：先更新 base，再存储
            base  = info['base']
            delta = wb[1]
            self._emit(f'\taddi\t{base},{base},{delta}')
            self._emit(f'\t{op}\t{rs},0({base})')
        elif wb and wb[0] == 'post' and wb[1] is not None:
            # 后索引写回：先存储，再更新 base
            base  = info['base']
            delta = wb[1]
            self._emit(f'\t{op}\t{rs},0({base})')
            self._emit(f'\taddi\t{base},{base},{delta}')
        else:
            addr = self._compute_addr(info)
            self._emit(f'\t{op}\t{rs},{addr}')


# ═══════════════════════════════════════════════════════════════════════════
#  命令行入口
# ═══════════════════════════════════════════════════════════════════════════
def main():
    if len(sys.argv) < 2:
        print(f'用法: python3 {sys.argv[0]} input_arm.s [output_rv32i.s]',
              file=sys.stderr)
        sys.exit(1)

    with open(sys.argv[1], 'r') as f:
        lines = f.readlines()

    result = Translator().translate(lines)

    if len(sys.argv) >= 3:
        with open(sys.argv[2], 'w') as f:
            f.write(result)
        print(f'translated → {sys.argv[2]}')
    else:
        sys.stdout.write(result)


if __name__ == '__main__':
    main()