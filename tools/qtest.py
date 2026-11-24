#!/usr/bin/env python3
"""Drive QEMU+OVMF through the monitor: send keys, grab screenshots."""
import subprocess, socket, time, sys, os
from PIL import Image

import os as _os
FW=["-bios","/usr/share/ovmf/OVMF.fd"]
if _os.environ.get("OVMF4M"):
    FW=["-drive","if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd","-drive","if=pflash,format=raw,file=/tmp/vars4m.fd"]

class Q:
    def __init__(self, drive_args, shots="/tmp/shots"):
        os.makedirs(shots, exist_ok=True); self.shots=shots
        self.sock="/tmp/qmon.sock"
        if os.path.exists(self.sock): os.unlink(self.sock)
        self.p=subprocess.Popen(["qemu-system-x86_64","-machine","q35","-m","256",
            *FW,"-vga","std","-display","none","-net","none",
            "-monitor","unix:%s,server,nowait"%self.sock]+drive_args,
            stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        for _ in range(50):
            if os.path.exists(self.sock): break
            time.sleep(0.1)
        self.s=socket.socket(socket.AF_UNIX); self.s.connect(self.sock); time.sleep(0.3); self.s.recv(65536)
    def cmd(self,c,wait=0.15):
        self.s.send((c+"\n").encode()); time.sleep(wait)
        try: self.s.settimeout(0.2); self.s.recv(65536)
        except Exception: pass
    MAP={' ':'spc','.':'dot','/':'slash','*':'asterisk',',':'comma','-':'minus','_':'shift-minus',':':'shift-semicolon'}
    def type(self,text):
        for ch in text:
            if ch in self.MAP: k=self.MAP[ch]
            elif ch.isupper(): k='shift-'+ch.lower()
            else: k=ch
            self.cmd("sendkey "+k,0.12)
    def enter(self): self.cmd("sendkey ret",0.5)
    def key(self,k,w=0.4): self.cmd("sendkey "+k,w)
    def shot(self,name):
        f="%s/%s.ppm"%(self.shots,name); self.cmd("screendump "+f,0.8)
        Image.open(f).save("%s/%s.png"%(self.shots,name)); return "%s/%s.png"%(self.shots,name)
    def close(self):
        try: self.cmd("quit")
        except Exception: pass
        self.p.kill()
