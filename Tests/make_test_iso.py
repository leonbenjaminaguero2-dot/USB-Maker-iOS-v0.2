#!/usr/bin/env python3
"""Make a tiny, structurally valid ISO9660 for BootMaker reader verification.
Uses a dummy PE-signature loader, NEVER a real bootable OS for tests."""
from pathlib import Path
import struct, sys
sector=2048
out=bytearray(sector*32)

def rec(name, extent, size, directory=False):
    if isinstance(name,str): name=name.encode('ascii')
    n=len(name)
    length=33+n+(n%2==0)
    b=bytearray(length);b[0]=length;b[2:6]=struct.pack('<I',extent);b[6:10]=struct.pack('>I',extent)
    b[10:14]=struct.pack('<I',size);b[14:18]=struct.pack('>I',size)
    b[25]=2 if directory else 0;b[28:30]=struct.pack('<H',1);b[30:32]=struct.pack('>H',1)
    b[32]=n;b[33:33+n]=name
    return b

def put(sector_no, records):
    data=b''.join(records)
    assert len(data)<sector
    out[sector_no*sector:sector_no*sector+len(data)]=data

put(20,[rec(b'\0',20,2048,True),rec(b'\1',20,2048,True),rec('EFI',21,2048,True),rec('README.TXT;1',24,10)])
put(21,[rec(b'\0',21,2048,True),rec(b'\1',20,2048,True),rec('BOOT',22,2048,True)])
put(22,[rec(b'\0',22,2048,True),rec(b'\1',21,2048,True),rec('BOOTX64.EFI;1',23,2048)])
loader=bytearray(2048)
loader[:2]=b'MZ';loader[0x3c:0x40]=struct.pack('<I',128);loader[128:132]=b'PE\0\0';loader[132:134]=struct.pack('<H',0x8664)
loader[128+20:128+22]=struct.pack('<H',240)
loader[128+24:128+26]=struct.pack('<H',0x20b)
loader[128+24+68:128+24+70]=struct.pack('<H',10) # EFI application subsystem
out[23*sector:24*sector]=loader
out[24*sector:24*sector+10]=b'hello iso!'
pvd=bytearray(sector)
pvd[0]=1;pvd[1:6]=b'CD001';pvd[6]=1
pvd[40:72]=b'BOOTMAKER_TEST'.ljust(32,b' ')
pvd[80:84]=struct.pack('<I',32);pvd[84:88]=struct.pack('>I',32)
pvd[128:130]=struct.pack('<H',2048);pvd[130:132]=struct.pack('>H',2048)
pvd[156:190]=rec(b'\0',20,2048,True)
out[16*sector:17*sector]=pvd
term=bytearray(sector);term[0]=255;term[1:6]=b'CD001';term[6]=1
out[17*sector:18*sector]=term
Path(sys.argv[1] if len(sys.argv)>1 else '/tmp/bootmaker_test.iso').write_bytes(out)
