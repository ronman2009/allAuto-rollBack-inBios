#!/usr/bin/env python3
"""构造 cpio newc 归档（含设备节点，无需 root）。

initramfs 必须包含 /dev/console (c 5:1)，否则内核无法给 init 提供
stdio，表现为黑屏假死。mknod 需要 root，故直接在归档层面写入节点。
"""
import os
import struct
import sys

S_IFCHR = 0o020000
# 注入的设备节点: 路径 -> (mode, rmajor, rminor)
DEV_NODES = {
    "dev/console": (S_IFCHR | 0o600, 5, 1),
    "dev/null": (S_IFCHR | 0o666, 1, 3),
    "dev/tty": (S_IFCHR | 0o666, 5, 0),
}

def pad4(n):
    return (4 - n % 4) % 4

def entry(out, name, mode=0o40755, uid=0, gid=0, data=b"", nlink=1,
          rmaj=0, rmin=0, mtime=0):
    devmaj, devmin = 0, 0
    fsize = len(data) if not (mode & 0o170000 == S_IFCHR) else 0
    fields = [0, mode, uid, gid, nlink, mtime, fsize,
              devmaj, devmin, rmaj, rmin, len(name) + 1, 0]  # 13 字段(含ino/check)
    # newc 头部: magic 6 字节 + 13 个 8 位十六进制字段 = 110 字节
    hdr = b"070701" + b"".join(b"%08X" % f for f in fields)
    out.write(hdr)
    out.write(name.encode() + b"\0")
    out.write(b"\0" * pad4(110 + len(name) + 1))
    if fsize:
        out.write(data)
        out.write(b"\0" * pad4(fsize))

def main(rootdir, outfile):
    out = open(outfile, "wb")
    # 目录优先（排序保证父目录在前），文件随后
    paths = []
    for dirpath, dirnames, filenames in os.walk(rootdir):
        dirnames.sort()
        for d in dirnames:
            paths.append(os.path.join(dirpath, d))
        for f in sorted(filenames):
            paths.append(os.path.join(dirpath, f))
    seen = set()
    for p in paths:
        rel = os.path.relpath(p, rootdir)
        if rel in seen:
            continue
        seen.add(rel)
        st = os.lstat(p)
        if os.path.isdir(p):
            entry(out, rel, mode=0o40755)
        elif os.path.islink(p):
            entry(out, rel, mode=0o120777, data=os.readlink(p).encode())
        else:
            mode = 0o100000 | (0o755 if rel == "init" else st.st_mode & 0o7777)
            with open(p, "rb") as f:
                entry(out, rel, mode=mode, data=f.read())
    # 设备节点独立注入（盘上不存在这些文件，walk 不会覆盖到）
    for rel, (nmode, rmaj, rmin) in DEV_NODES.items():
        entry(out, rel, mode=nmode, rmaj=rmaj, rmin=rmin)
    entry(out, "TRAILER!!!", nlink=1)
    out.close()
    print("written: %s (%d entries)" % (outfile, len(seen) + len(DEV_NODES)))

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
