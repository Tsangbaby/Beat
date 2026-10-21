"""Swift 反射元数据 -> 类型/字段/类型名（fieldmd 完整解析）"""
import struct, sys, re
from mo import MachO

class Nominal:
    def __init__(self, m):
        self.m = m
        self.by_addr = {}   # descriptor addr -> (name, kind)
        self.loaded = False

    def _i32(self, addr):
        o = self.m.a2o(addr)
        if o is None or o+4 > len(self.m.data): return None
        return struct.unpack_from('<i', self.m.data, o)[0]

    def rel(self, addr):
        v = self._i32(addr)
        return None if v is None else addr + v

    def cstr_rel(self, addr):
        t = self.rel(addr)
        return self.m.cstr(t) if t else None

    def desc_name(self, addr, depth=0):
        if depth > 8: return '?'
        o = self.m.a2o(addr)
        if o is None: return '?'
        flags = struct.unpack_from('<I', self.m.data, o)[0]
        name = self.cstr_rel(addr+8)
        parent = self.rel(addr+4)
        if parent:
            pn = self.desc_name(parent, depth+1)
            if pn and pn not in ('?',):
                return f'{pn}.{name}'
        return name

    def load_types(self):
        if self.loaded: return
        s = self.m.sect('__swift5_types')
        for i in range(s['size']//4):
            ea = s['addr'] + i*4
            d = self.rel(ea)
            if not d: continue
            o = self.m.a2o(d)
            if o is None: continue
            flags = struct.unpack_from('<I', self.m.data, o)[0]
            kind = flags & 0x1f
            self.by_addr[d] = dict(addr=d, kind=kind, name=self.desc_name(d))
        self.loaded = True

    # ---- mangled type decoding ----
    BUILTIN = {
        'Si':'Int','Su':'UInt','Sd':'Double','Sf':'Float','Sb':'Bool','SS':'String',
        'SJ':'Character','Sv':'UnsafeMutableRawPointer','SP':'UnsafePointer','SV':'UnsafeRawPointer',
        'yt':'Any','yp':'AnyObject','s5NeverO':'Never','So':'NSObject',
        'SQ':'Optional','Sq':'Optional','s4Int8V':'Int8','s5Int16V':'Int16','s5Int32V':'Int32','s5Int64V':'Int64',
        's5UInt8V':'UInt8','s6UInt16V':'UInt16','s6UInt32V':'UInt32','s6UInt64V':'UInt64',
    }

    def demangle(self, s, depth=0):
        """解析常见 Swift 类型 mangling（用于字段类型）"""
        if not s: return None
        if depth > 10: return '...'
        i = 0
        out = self._parse_type(s, 0, depth)[0]
        return out if out else s

    def _ident(self, s, i):
        j = i
        while j < len(s) and s[j].isdigit(): j += 1
        if j == i: return None, i
        n = int(s[i:j])
        if j+n > len(s): return None, i
        return s[j:j+n], j+n

    def _parse_type(self, s, i, depth):
        if i >= len(s): return '?', i
        # 常见前缀
        for pref, pre in (('Say', 'Array<'), ('SDy', 'Dictionary<'), ('Shy', 'Set<'), ('Sny', 'Range<'), ('SnySiG','Range<Int>')):
            if s.startswith(pref, i):
                inner, j = self._parse_type(s, i+len(pref), depth+1)
                # 期望以 G 结束
                if j < len(s) and s[j] == 'G': j += 1
                return pre + inner + '>', j
        if s.startswith('So', i):
            nm, j = self._ident(s, i+2)
            if nm:
                if j < len(s) and s[j] == 'C': j += 1
                return nm, j
        if s.startswith('Sg', i):
            return 'Optional', i+2
        if s.startswith('SP', i) or s.startswith('SV', i):
            nm, j = self._ident(s, i+2)
            if nm:
                return f'UnsafePointer<{nm}>', j
        for k, v in self.BUILTIN.items():
            if s.startswith(k, i):
                # 处理 Sg 后缀 (Optional)
                return v, i+len(k)
        # 模块.类型
        mod, j = self._ident(s, i)
        if mod:
            # 尝试再取一个 identifier 作为类型名
            nm, j2 = self._ident(s, j)
            if nm:
                tail = ''
                if j2 < len(s) and s[j2] in 'CVO':  # class/struct/enum
                    tail = ''
                    j2 += 1
                base = f'{mod}.{nm}'
                return base, j2
            return mod, j
        return s[i:], len(s)

    def resolve_typeref(self, addr, depth=0):
        """field record 的 MangledTypeName (相对指针) -> 可读类型名"""
        if depth > 6: return '?'
        v = self._i32(addr)
        if v is None: return '?'
        if v & 1:
            # 符号引用：直接指向 nominal type descriptor
            tgt = addr + (v & ~1)
            if tgt in self.by_addr:
                return self.by_addr[tgt]['name']
            nm = self.desc_name(tgt)
            return nm or f'@{tgt:#x}'
        tgt = addr + v
        raw = self.m.cstr(tgt)
        if raw is None: return '?'
        if raw and raw[0] in ('\x01', '\x02'):
            # 间接符号引用
            inner = self.rel(tgt + 1)
            if inner:
                if inner in self.by_addr:
                    return self.by_addr[inner]['name']
                return self.desc_name(inner) or f'indirect@{tgt:#x}'
            return f'indirect@{tgt:#x}'
        return self.demangle(raw)

def _valid_fd(m, fptr):
    o = m.a2o(fptr)
    if o is None or o + 16 > len(m.data): return None
    d = m.data
    try:
        mangled_rel, super_rel, fkind, recsize, numfields = struct.unpack_from('<iiHHI', d, o)
    except Exception:
        return None
    if fkind not in (0, 1): return None
    if recsize not in (8, 12, 16, 20, 24): return None
    if numfields == 0 or numfields > 300: return None
    if o + 16 + recsize*numfields > len(d): return None
    # 校验前若干个字段名可读
    ok = 0
    for i in range(min(numfields, 4)):
        ro = o + 16 + i*recsize
        try:
            fl, t_rel, n_rel = struct.unpack_from('<Iii', d, ro)
        except Exception:
            return None
        nm = m.cstr(fptr + (ro-o) + 8 + n_rel)
        if not nm or len(nm) == 0 or len(nm) > 80: return None
        if not re.match(r'^[A-Za-z_][A-Za-z0-9_]*$', nm): return None
        ok += 1
    return (fkind, recsize, numfields) if ok else None


def parse_fields(m, desc_addr, nominal):
    """带校验的 FieldDescriptor 定位：尝试 +16 及其邻域"""
    o = m.a2o(desc_addr)
    if o is None: return [], None
    d = m.data
    flags = struct.unpack_from('<I', d, o)[0]
    kind = flags & 0x1f
    if kind not in (16, 17, 18): return [], None
    base = struct.unpack_from('<i', d, o+16)[0]
    cands = [desc_addr + 16 + base]
    for fptr in cands:
        v = _valid_fd(m, fptr)
        if not v: continue
        fkind, recsize, numfields = v
        fo = m.a2o(fptr)
        out = []
        for i in range(numfields):
            ro = fo + 16 + i*recsize
            fl, t_rel, n_rel = struct.unpack_from('<Iii', d, ro)
            fname = m.cstr(fptr + (ro - fo) + 8 + n_rel)
            taddr = fptr + (ro - fo) + 4
            ty = nominal.resolve_typeref(taddr)
            out.append(dict(flags=fl, name=fname, type=ty, taddr=taddr))
        return out, fptr
    return [], None
