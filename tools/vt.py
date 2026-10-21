"""在类描述符尾部扫描 VTableDescriptorHeader{offset,size}，按自洽性定位真实 vtable"""
import struct, sys
from mo import MachO
from fieldmd import Nominal

HOOKS = ["UIApplicationHook","SpringBoardHook","SBApplicationHook","SBIconControllerHook",
         "_SBFluidSwitcherPanGestureRecognizerHook","SBGrabberTongueHook",
         "SBFluidSwitcherGestureManagerHook","SBMainDisplaySceneManagerHook",
         "UIApplicationSceneDeactivationManagerHook","FBSceneHook","BNContentViewControllerHook",
         "SBDeviceApplicationSceneViewControllerHook","SBApplicationControllerHook",
         "FBSceneManagerHook","FBSystemServiceHook","UIStatusBarWindowHook"]

def text_range(m):
    t = m.sect('__text')
    return t['addr'], t['addr'] + t['size']

def scan_vtable(m, desc, lo=40, hi=160):
    """返回 [(offset,size,impls)] 候选"""
    t0, t1 = text_range(m)
    o = m.a2o(desc)
    if o is None: return []
    out = []
    for delta in range(lo, hi, 4):
        if o + delta + 8 > len(m.data): break
        voff, vsize = struct.unpack_from('<II', m.data, o+delta)
        if not (1 <= vsize <= 200): continue
        if vsize * 4 + o + delta + 8 > len(m.data): continue
        impls = []
        ok = 0
        for j in range(vsize):
            ia = desc + delta + 8 + j*4
            io = m.a2o(ia)
            rel = struct.unpack_from('<i', m.data, io)[0]
            tgt = ia + rel
            impls.append(tgt)
            if t0 <= tgt < t1: ok += 1
        # 允许个别 0（未实现槽）
        if ok >= max(1, int(vsize*0.8)):
            out.append((delta, vsize, impls))
    return out

if __name__ == '__main__':
    m = MachO(sys.argv[1])
    nm = Nominal(m); nm.load_types()
    targets = {}
    for addr, t in nm.by_addr.items():
        short = t['name'].split('.')[-1]
        if short in HOOKS:
            targets.setdefault(short, []).append((addr, t['name']))
    t0, t1 = text_range(m)
    print(f'__text {t0:#x}-{t1:#x}')
    for name in HOOKS:
        for addr, full in targets.get(name, []):
            cands = scan_vtable(m, addr)
            print(f'\n=== {name} @{addr:#x}  candidates={len(cands)}')
            for delta, vsize, impls in cands:
                print(f'   hdr@{delta} size={vsize}')
                print('     ', ' '.join(f'{a:#x}' for a in impls))
