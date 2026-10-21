"""ObjC 运行时元数据还原（relative method list + chained fixups）"""
import struct, sys
from mo import MachO
from fx import parse_chained_fixups

class ObjC:
    def __init__(self, m):
        self.m = m
        self.rebase, self.bind, self.imports = parse_chained_fixups(m)

    def ptr(self, addr):
        """解析一个 8 字节指针槽"""
        if addr in self.rebase: return self.rebase[addr]
        if addr in self.bind: return ('bind', self.bind[addr]['name'])
        v = self.m.u64(addr)
        return v

    def i32(self, addr):
        o = self.m.a2o(addr)
        if o is None or o+4 > len(self.m.data): return None
        return struct.unpack_from('<i', self.m.data, o)[0]

    def u32(self, addr):
        o = self.m.a2o(addr)
        if o is None or o+4 > len(self.m.data): return None
        return struct.unpack_from('<I', self.m.data, o)[0]

    def relptr(self, addr):
        """rel32: 从该字段地址出发"""
        v = self.i32(addr)
        return None if v is None else addr + v

    def cstr_at_field(self, addr):
        t = self.relptr(addr)
        return self.m.cstr(t) if t else None

    def method_list(self, addr):
        if not addr or isinstance(addr, tuple): return []
        entsize_flags = self.u32(addr)
        count = self.u32(addr+4)
        if entsize_flags is None or count is None: return []
        out = []
        rel = bool(entsize_flags & 0x80000000)
        entsize = entsize_flags & 0xffff
        if rel:
            for i in range(count):
                e = addr + 8 + i*12
                name = self.cstr_at_field(e)
                types = self.cstr_at_field(e+4)
                impp = self.relptr(e+8)
                out.append(dict(sel=name, types=types, imp=impp))
        else:
            for i in range(count):
                e = addr + 8 + i*24
                name = self.m.cstr(self.ptr(e)) if isinstance(self.ptr(e), int) else None
                types = self.m.cstr(self.ptr(e+8)) if isinstance(self.ptr(e+8), int) else None
                impp = self.ptr(e+16)
                out.append(dict(sel=name, types=types, imp=impp))
        return out

    def ivar_list(self, addr):
        if not addr or isinstance(addr, tuple): return []
        entsize = self.u32(addr); count = self.u32(addr+4)
        if entsize is None or entsize > 128: return []
        out = []
        for i in range(count or 0):
            e = addr + 8 + i*entsize
            offp = self.ptr(e)
            np_ = self.ptr(e+8)
            tp = self.ptr(e+16)
            name = self.m.cstr(np_) if isinstance(np_, int) else None
            types = self.m.cstr(tp) if isinstance(tp, int) else None
            off = self.u32(offp) if isinstance(offp, int) else None
            align = self.u32(e+24)
            size = self.u32(e+28)
            out.append(dict(name=name, type=types, size=size, align=align, offset=off, offset_ptr=offp))
        return out

    def property_list(self, addr):
        if not addr or isinstance(addr, tuple): return []
        entsize = self.u32(addr); count = self.u32(addr+4)
        out = []
        for i in range(count or 0):
            e = addr + 8 + i*entsize
            name = self.cstr_at_field(e)
            attrs = self.cstr_at_field(e+4)
            out.append(dict(name=name, attrs=attrs))
        return out

    def classes(self):
        s = self.m.sect('__objc_classlist')
        out = []
        for i in range(s['size']//8):
            a = s['addr'] + i*8
            cls = self.ptr(a)
            if not isinstance(cls, int): continue
            info = dict(addr=cls, name=None, superclass=None, methods=[], ivars=[], props=[], protocols=[])
            data = self.ptr(cls+32)
            if isinstance(data, int):
                data &= ~0x7
                info['ro'] = data
                namep = self.ptr(data+24)
                if isinstance(namep, int):
                    info['name'] = self.m.cstr(namep)
                ml = self.ptr(data+32)
                if isinstance(ml, int):
                    info['methods'] = self.method_list(ml)
                pl = self.ptr(data+40)
                if isinstance(pl, int):
                    info['protocols_addr'] = pl
                iv = self.ptr(data+48)
                if isinstance(iv, int):
                    info['ivars'] = self.ivar_list(iv)
                pr = self.ptr(data+64)
                if isinstance(pr, int):
                    info['props'] = self.property_list(pr)
            sup = self.ptr(cls+8)
            if isinstance(sup, int):
                sdata = self.ptr(sup+32)
                if isinstance(sdata, int):
                    np_ = self.ptr((sdata & ~7)+24)
                    if isinstance(np_, int):
                        info['superclass'] = self.m.cstr(np_)
            elif isinstance(sup, tuple):
                info['superclass'] = sup[1]
            out.append(info)
        return out

if __name__ == '__main__':
    m = MachO(sys.argv[1])
    oc = ObjC(m)
    for c in oc.classes():
        print(f"=== {c['name']}  @{c['addr']:#x}  : {c['superclass']}")
        if c['props']:
            print('   props:', ', '.join(f"{p['name']}({p['attrs']})" for p in c['props']))
        if c['ivars']:
            print('   ivars:', ', '.join(f"{v['name']}:{v['type']}" for v in c['ivars']))
        print(f"   methods({len(c['methods'])}):")
        for me in c['methods']:
            imp = me['imp']
            print(f"      {me['sel']:55s} {('0x%x'%imp) if isinstance(imp,int) else imp}  {me['types']}")
