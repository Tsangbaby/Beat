"""Swift 5 反射元数据还原：类型名、父类、字段、vtable 实现体"""
import struct, sys, os, json
from mo import MachO

KIND = {0:'Module',1:'Extension',2:'Anonymous',3:'Protocol',4:'OpaqueType',
        16:'Class',17:'Struct',18:'Enum'}

class SwiftMeta:
    def __init__(self, m):
        self.m = m
        self.rel = lambda addr, off: addr + off  # i32 rel from field addr
        self.types = []

    def _ok(self, o):
        return o is not None and 0 <= o and o + 4 <= len(self.m.data)

    def relstr(self, addr):
        o = self.m.a2o(addr)
        if not self._ok(o): return None
        off = struct.unpack_from('<i', self.m.data, o)[0]
        r = self.m.cstr(addr + off)
        return r

    def rel_target(self, addr):
        o = self.m.a2o(addr)
        if not self._ok(o): return None
        off = struct.unpack_from('<i', self.m.data, o)[0]
        return addr + off

    def type_name(self, desc_addr):
        """返回 (module.Type) 名字，递归 parent"""
        o = self.m.a2o(desc_addr)
        if o is None: return '?'
        flags = struct.unpack_from('<I', self.m.data, o)[0]
        kind = flags & 0x1f
        name = self.relstr(desc_addr + 8)
        parent = self.rel_target(desc_addr + 4)
        if parent:
            pname = self.type_name(parent)
            if pname and pname != '?':
                return f'{pname}.{name}'
        return name

    def parse_field_descriptor(self, addr):
        o = self.m.a2o(addr)
        if o is None: return []
        d = self.m.data
        mangled_rel, super_rel, kind, recsize, numfields = struct.unpack_from('<iiHHI', d, o)
        out = []
        for i in range(numfields):
            ro = o + 16 + i*recsize
            if ro + 12 > len(d): break
            fl, tname_rel, fname_rel = struct.unpack_from('<Iii', d, ro)
            # field name
            fo = self.m.a2o(addr + (ro - o) + 8)
            fname = self.m.cstr(addr + (ro - o) + 8 + fname_rel) if fo is not None else None
            # mangled type name (may be symbol ref: 0x01/0x02 prefix)
            taddr = (addr + (ro - o) + 4)
            tval = self.rel_target(taddr)
            out.append(dict(flags=fl, field=fname, typeref_addr=taddr, type_raw=tval))
        return out

    def parse_all(self):
        s = self.m.sect('__swift5_types')
        if not s: return []
        n = s['size']//4
        for i in range(n):
            ea = s['addr'] + i*4
            desc = self.rel_target(ea)
            o = self.m.a2o(desc)
            if o is None: continue
            d = self.m.data
            flags = struct.unpack_from('<I', d, o)[0]
            kind = flags & 0x1f
            name = self.relstr(desc+8)
            full = self.type_name(desc)
            info = dict(addr=desc, kind=KIND.get(kind, kind), name=full, short=name,
                        flags=flags, fields=[], vtable=[], superclass=None)
            if kind in (16,17,18):
                fptr = self.rel_target(desc+16)
                if fptr:
                    info['fields'] = self.parse_field_descriptor(fptr)
                if kind == 16:
                    sc = self.rel_target(desc+20)
                    if sc:
                        info['superclass'] = self.type_name(sc)
                        info['superclass_addr'] = sc
                    numimm = struct.unpack_from('<H', d, o+32)[0]
                    numfields = struct.unpack_from('<H', d, o+34)[0]
                    info['numImmediateMembers'] = numimm
                    info['numFields'] = numfields
                    # vtable header at +40
                    vo, vs = struct.unpack_from('<II', d, o+40)
                    impls = []
                    for j in range(vs):
                        ia = desc + 48 + j*4
                        tgt = self.rel_target(ia)
                        impls.append(tgt)
                    info['vtable_offset'] = vo
                    info['vtable'] = impls
            self.types.append(info)
        return self.types

def demangle_basic(mangled, types_by_addr):
    """极简：解析 0x01/0x02 符号引用到类型名"""
    if not mangled: return None
    if mangled & 1:  # direct pointer, low bit set
        addr = mangled & ~1
        for t in types_by_addr:
            if t['addr'] == addr: return t['name']
        return f'@{addr:#x}'
    return None

if __name__ == '__main__':
    p = sys.argv[1]
    m = MachO(p)
    sm = SwiftMeta(m)
    types = sm.parse_all()
    print(f'=== {len(types)} types in __swift5_types ===')
    for t in types:
        print(f"{t['addr']:#09x} {t['kind']:8s} {t['name']:60s} fields={len(t['fields'])} vt={len(t['vtable'])} super={t['superclass']}")
        for f in t['fields']:
            print(f"        . {f['field']}")
        if t['vtable']:
            print('        vt:', ' '.join(f'{a:#x}' if a else 'nil' for a in t['vtable']))
