"""__swift5_proto -> 协议一致性描述符 -> (类型名, 见证表) 映射"""
import struct, sys
from mo import MachO
from fieldmd import Nominal

class Conformances:
    def __init__(self, m, nm):
        self.m = m
        self.nm = nm
        self.items = []

    def _i32(self, addr):
        o = self.m.a2o(addr)
        if o is None or o+4 > len(self.m.data): return None
        return struct.unpack_from('<i', self.m.data, o)[0]

    def rel(self, addr):
        v = self._i32(addr)
        return None if v is None else addr + v

    def parse(self):
        s = self.m.sect('__swift5_proto')
        if not s: return []
        for i in range(s['size']//4):
            ea = s['addr'] + i*4
            desc = self.rel(ea)
            if not desc: continue
            proto = self.rel(desc + 0)
            typeref = self.rel(desc + 4)
            wt = self.rel(desc + 8)
            flags = self._i32(desc + 12) or 0
            type_name = None
            type_desc = None
            # TypeRef 可能是 indirect（flags bit0）
            if typeref:
                if flags & 1:
                    inner = self.rel(typeref)
                    type_desc = inner
                else:
                    type_desc = typeref
                if type_desc:
                    type_name = self.nm.desc_name(type_desc)
            proto_name = self.nm.desc_name(proto) if proto else None
            self.items.append(dict(desc=desc, proto=proto_name, proto_addr=proto, type=type_name,
                                   type_desc=type_desc, witness=wt, flags=flags))
        return self.items

def vt_entries(m, addr, limit=64, rebase=None):
    """见证表项：先按 rel32 试，失败则按 8 字节 fixup 指针解析"""
    t = m.sect('__text'); t0, t1 = t['addr'], t['addr']+t['size']
    out = []
    for i in range(limit):
        a = addr + i*4
        o = m.a2o(a)
        if o is None or o+4 > len(m.data): break
        v = struct.unpack_from('<i', m.data, o)[0]
        tgt = a + v
        if t0 <= tgt < t1:
            out.append(tgt); continue
        break
    if out: return out
    # 8 字节槽
    if rebase is None: return []
    for i in range(limit):
        a = addr + i*8
        if a not in rebase: break
        tgt = rebase[a]
        if not (t0 <= tgt < t1): break
        out.append(tgt)
    return out

if __name__ == '__main__':
    m = MachO(sys.argv[1])
    nm = Nominal(m); nm.load_types()
    from fx import parse_chained_fixups
    rebase, bind, _ = parse_chained_fixups(m)
    cf = Conformances(m, nm)
    items = cf.parse()
    print(f'{len(items)} conformances')
    for it in items:
        ent = vt_entries(m, it['witness'], limit=80, rebase=rebase) if it['witness'] else []
        print(f"{it['type'] or '?':50s} : {it['proto'] or '?':35s} wt={it['witness']:#x} entries={len(ent)}")
