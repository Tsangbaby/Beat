"""综合反汇编分析器：寄存器值追踪 + 语义标注 + 函数级摘要"""
import struct, sys, json, os, pickle, bisect
from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM
from capstone.arm64 import ARM64_OP_IMM, ARM64_OP_MEM, ARM64_OP_REG
from mo import MachO
from fx import parse_chained_fixups

class DX:
    def __init__(self, path):
        self.m = MachO(path)
        self.rebase, self.bind, self.imports = parse_chained_fixups(self.m)
        self.text = self.m.sect('__text')
        self.build_strings()
        self.build_funcs()
        self.build_stubs()
        self.summ = None

    # ---------- 数据 ----------
    def slot(self, addr):
        if addr in self.rebase: return ('ptr', self.rebase[addr])
        if addr in self.bind: return ('bind', self.bind[addr]['name'])
        v = self.m.u64(addr)
        return ('raw', v)

    def build_strings(self):
        self.cstrings = {}
        self.cfstrings = {}
        self.methnames = {}
        for secname, table in (('__cstring', self.cstrings), ('__objc_methname', self.methnames)):
            s = self.m.sect(secname)
            if not s: continue
            o = self.m.a2o(s['addr']); blob = self.m.data[o:o+s['size']]
            p = 0
            while p < len(blob):
                e = blob.find(b'\x00', p)
                if e < 0: e = len(blob)
                if e > p: table[s['addr']+p] = blob[p:e].decode('utf-8','replace')
                p = e+1
        s = self.m.sect('__cfstring')
        if s:
            for i in range(s['size']//32):
                a = s['addr'] + i*32
                t = self.slot(a+16)
                dptr = t[1] if t[0] == 'ptr' else self.m.u64(a+16)
                if dptr:
                    txt = self.m.cstr(dptr)
                    if txt is not None: self.cfstrings[a] = txt

    def build_funcs(self):
        dataoff = None
        for cmd, sz, off, body in self.m.cmds:
            if cmd == 0x26:
                dataoff, datasize = struct.unpack_from('<II', body, 8)
        self.funcs = []
        if dataoff:
            d = self.m.data; off = dataoff; addr = self.text['addr']
            while off < len(d):
                b = d[off]; off += 1
                if b == 0: break
                val = b & 0x7f; shift = 0
                while b & 0x80:
                    b = d[off]; off += 1
                    val |= (b & 0x7f) << (shift+7); shift += 7
                if val == 0: break
                addr += val
                self.funcs.append(addr)
        if not self.funcs: self.funcs = [self.text['addr']]
        self.func_set = set(self.funcs)

    def build_stubs(self):
        self.stub_imp = {}
        self.stub_sel = {}
        md = Cs(CS_ARCH_ARM64, CS_MODE_ARM); md.detail = True
        for secname in ('__auth_stubs', '__stubs', '__objc_stubs'):
            s = self.m.sect(secname)
            if not s: continue
            blob = self.m.read(s['addr'], s['size']) or b''
            block = []
            for ins in md.disasm(blob, s['addr']):
                block.append(ins)
                if ins.mnemonic in ('br','braa','braaz','brab','brabz','bra','ret','blr','b'):
                    self._classify(block); block = []
            if block: self._classify(block)

    def _classify(self, block):
        if not block: return
        start = block[0].address
        rv = {}
        imp = None; sel = None
        for ins in block:
            self._eval(ins, rv)
            if ins.mnemonic == 'ldr' and len(ins.operands) >= 2:
                try: mem = ins.operands[1].mem
                except Exception: continue
                if mem.base in rv:
                    a = rv[mem.base] + mem.disp
                    t = self.slot(a)
                    if t[0] == 'bind': imp = t[1]
                    elif t[0] == 'ptr':
                        st = self.m.cstr(t[1])
                        if st is not None: sel = st
        if sel is not None: self.stub_sel[start] = sel
        elif imp is not None: self.stub_imp[start] = imp

    def _eval(self, ins, rv):
        """更新寄存器值表"""
        try:
            return self._eval_inner(ins, rv)
        except Exception:
            return

    def _eval_inner(self, ins, rv):
        mn = ins.mnemonic
        if mn == 'adrp':
            rv[ins.operands[0].reg] = ins.operands[1].imm
        elif mn == 'add' and len(ins.operands) == 3:
            d, s1, s2 = ins.operands
            if s1.type == ARM64_OP_REG and s1.reg in rv and s2.type == ARM64_OP_IMM:
                rv[d.reg] = rv[s1.reg] + s2.imm
        elif mn == 'sub' and len(ins.operands) == 3:
            d, s1, s2 = ins.operands
            if s1.type == ARM64_OP_REG and s1.reg in rv and s2.type == ARM64_OP_IMM:
                rv[d.reg] = rv[s1.reg] - s2.imm
        elif mn in ('mov','movz'):
            if len(ins.operands) == 2 and ins.operands[1].type == ARM64_OP_IMM:
                rv[ins.operands[0].reg] = ins.operands[1].imm
        elif mn in ('ldr','ldur','ldrb','ldrh','ldrsw','ldrsb') and len(ins.operands) >= 2:
            try: mem = ins.operands[1].mem
            except Exception:
                rv.pop(ins.operands[0].reg, None); return
            if mem.base in rv:
                a = rv[mem.base] + mem.disp
                t = self.slot(a)
                if t[0] == 'ptr' and self.m.a2o(t[1]) is not None:
                    rv[ins.operands[0].reg] = t[1]
                else:
                    rv.pop(ins.operands[0].reg, None)
            else:
                rv.pop(ins.operands[0].reg, None)
        elif mn in ('str','strb','strh'):
            pass
        elif mn == 'mov' and len(ins.operands) == 2 and ins.operands[1].type == ARM64_OP_REG:
            if ins.operands[1].reg in rv: rv[ins.operands[0].reg] = rv[ins.operands[1].reg]
        else:
            # 其他指令可能写寄存器 -> 保守清理目的寄存器
            if ins.operands and ins.operands[0].type == ARM64_OP_REG and mn not in ('cmp','tst','cbz','cbnz','b','bl'):
                rv.pop(ins.operands[0].reg, None)

    # ---------- 标注 ----------
    def tag(self, a):
        for s in self.m.sects:
            if s['addr'] <= a < s['addr'] + s['size']:
                sec = s['name']
                if sec == '__cstring':
                    st = self.cstrings.get(a)
                    return f'STR"{st}"' if st else f'__cstring+{a-s["addr"]:#x}'
                if sec == '__objc_methname':
                    st = self.methnames.get(a)
                    return f'SELNAME"{st}"' if st else f'methname+{a-s["addr"]:#x}'
                if sec == '__cfstring':
                    st = self.cfstrings.get(a)
                    return f'CFSTR"{st}"' if st else 'CFSTR?'
                if sec == '__objc_selrefs':
                    t = self.slot(a)
                    if t[0] == 'ptr':
                        st = self.m.cstr(t[1])
                        return f'SELREF("{st}")' if st else 'SELREF?'
                    return 'SELREF?'
                if sec == '__objc_classrefs':
                    t = self.slot(a)
                    if t[0] == 'bind': return 'CLASSREF(' + t[1].replace('_OBJC_CLASS_$_','') + ')'
                    if t[0] == 'ptr': return f'CLASSREF({t[1]:#x})'
                    return 'CLASSREF?'
                if sec in ('__auth_got','__got','__la_symbol_ptr'):
                    t = self.slot(a)
                    if t[0] == 'bind': return 'GOT(' + t[1] + ')'
                    if t[0] == 'ptr': return f'GOT->{t[1]:#x}'
                    return 'GOT?'
                if sec in ('__auth_ptr','__objc_data'):
                    t = self.slot(a)
                    if t[0] == 'ptr': return f'{sec}->{t[1]:#x}'
                    if t[0] == 'bind': return f'{sec}(' + t[1] + ')'
                if sec in ('__data','__const','__bss','__common'):
                    t = self.slot(a)
                    if t[0] == 'bind': return f'{sec}[{t[1]}]'
                    if t[0] == 'ptr': return f'{sec}->{t[1]:#x}'
                return f'{sec}+{a-s["addr"]:#x}'
        return f'{a:#x}'

    def call_tag(self, t):
        if t in self.stub_imp: return 'IMP:' + self.stub_imp[t]
        if t in self.stub_sel: return 'msgSend[' + self.stub_sel[t] + ']'
        if t in self.func_set: return f'f_{t:x}'
        return f'sub_{t:x}'

    # ---------- 反汇编 ----------
    def disas(self, start, count=200, stop_ret=True):
        md = Cs(CS_ARCH_ARM64, CS_MODE_ARM); md.detail = True; md.skipdata = True
        blob = self.m.read(start, count*4+64)
        if blob is None: return []
        out = []; rv = {}
        for ins in md.disasm(blob, start):
            note = ''
            # 先标注（用旧 rv），再更新
            mn = ins.mnemonic
            if mn in ('ldr','ldur','ldrb','ldrh','ldrsw','ldrsb','str','strb','strh','ldraa','ldrab','add') and len(ins.operands) >= 2:
                try:
                    mem = ins.operands[1].mem
                    if mem.base in rv:
                        note = self.tag(rv[mem.base] + mem.disp)
                except Exception:
                    if mn == 'add' and len(ins.operands) == 3 and ins.operands[1].type == ARM64_OP_REG:
                        b = ins.operands[1].reg
                        if b in rv and ins.operands[2].type == ARM64_OP_IMM:
                            note = self.tag(rv[b] + ins.operands[2].imm)
            if mn in ('bl','b') and ins.operands and ins.operands[0].type == ARM64_OP_IMM:
                note = self.call_tag(ins.operands[0].imm)
            if mn == 'adr' and ins.operands and ins.operands[1].type == ARM64_OP_IMM:
                note = self.tag(ins.operands[1].imm)
            self._eval(ins, rv)
            ins._note = note
            out.append(ins)
            if len(out) >= count: break
            if stop_ret and mn == 'ret': break
        return out

    # ---------- 函数摘要 ----------
    def summarize(self):
        if self.summ is not None: return self.summ
        md = Cs(CS_ARCH_ARM64, CS_MODE_ARM); md.detail = True; md.skipdata = True
        blob = self.m.read(self.text['addr'], self.text['size'])
        base = self.text['addr']
        per = {}
        cur = None; rv = {}
        for ins in md.disasm(blob, base):
            if ins.address in self.func_set:
                cur = ins.address
                rv = {}
                per[cur] = dict(calls=[], sels=[], strs=[], cfstrs=[], classes=[], got=[], other=[], size=0)
            if cur is None: continue
            e = per[cur]; e['size'] += 4
            mn = ins.mnemonic
            if mn in ('ldr','ldur','ldrb','ldrh','ldrsw','ldrsb','str','strb','strh') and len(ins.operands) >= 2:
                try:
                    mem = ins.operands[1].mem
                    if mem.base in rv:
                        a = rv[mem.base] + mem.disp
                        tg = self.tag(a)
                        if tg.startswith('SELREF'): e['sels'].append(tg[8:-2])
                        elif tg.startswith('STR"'): e['strs'].append(tg[4:-1])
                        elif tg.startswith('CFSTR"'): e['cfstrs'].append(tg[6:-1])
                        elif tg.startswith('CLASSREF('): e['classes'].append(tg[9:-1])
                        elif tg.startswith('GOT('): e['got'].append(tg[4:-1])
                        else: e['other'].append(tg)
                except Exception:
                    pass
            if mn == 'add' and len(ins.operands) == 3 and ins.operands[1].type == ARM64_OP_REG and ins.operands[1].reg in rv and ins.operands[2].type == ARM64_OP_IMM:
                a = rv[ins.operands[1].reg] + ins.operands[2].imm
                tg = self.tag(a)
                if tg.startswith('SELREF'): e['sels'].append(tg[8:-2])
                elif tg.startswith('STR"'): e['strs'].append(tg[4:-1])
                elif tg.startswith('CLASSREF('): e['classes'].append(tg[9:-1])
            if mn in ('bl','b') and ins.operands and ins.operands[0].type == ARM64_OP_IMM:
                t = ins.operands[0].imm
                if t in self.stub_imp: e['calls'].append(self.stub_imp[t])
                elif t in self.stub_sel: e['sels'].append('MSG:' + self.stub_sel[t])
                elif t in self.func_set and mn == 'bl': e['calls'].append(f'f_{t:x}')
            self._eval(ins, rv)
        for k in per:
            for f in ('calls','sels','strs','cfstrs','classes','got','other'):
                per[k][f] = sorted(set(per[k][f]))
        self.summ = per
        return per

    def fname(self, a):
        """未被符号表覆盖，用地址；若有 ObjC/Swift 线索则附加"""
        return f'f_{a:x}'

if __name__ == '__main__':
    dx = DX(sys.argv[1])
    print('funcs', len(dx.funcs), 'stub_imp', len(dx.stub_imp), 'stub_sel', len(dx.stub_sel))
    print('cstrings', len(dx.cstrings), 'methnames', len(dx.methnames), 'cfstrings', len(dx.cfstrings))
    for k, v in dx.stub_sel.items(): print(f'  sel {k:#x} {v}')
    s = dx.summarize()
    print('summarized', len(s))
