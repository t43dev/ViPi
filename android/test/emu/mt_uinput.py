"""Write a uinput JSON script for a two-finger rollover: finger0 down, finger1 down, finger0 up, finger1 up."""
import json, sys
x0, y0, x1, y1 = map(int, sys.argv[1:5])
def ai(code, mx):
    return {"code": code, "info": {"value": 0, "minimum": 0, "maximum": mx, "fuzz": 0, "flat": 0, "resolution": 0}}
cmds = [
    {"id": 1, "command": "register", "name": "ViPi test touch", "vid": 0x18d1, "pid": 0x7e57, "bus": "virtual",
     "configuration": [
         {"type": 100, "data": [1, 3]},
         {"type": 101, "data": [330]},
         {"type": 103, "data": [47, 48, 53, 54, 57, 58]},
         {"type": 110, "data": [1]},
     ],
     "abs_info": [ai(47, 9), ai(48, 255), ai(53, 1079), ai(54, 2399), ai(57, 65535), ai(58, 255)]},
    {"id": 1, "command": "delay", "duration": 1500},
    {"id": 1, "command": "inject", "events": [3, 47, 0, 3, 57, 1, 3, 53, x0, 3, 54, y0, 3, 58, 60, 3, 48, 8, 1, 330, 1, 0, 0, 0]},
    {"id": 1, "command": "delay", "duration": 80},
    {"id": 1, "command": "inject", "events": [3, 47, 1, 3, 57, 2, 3, 53, x1, 3, 54, y1, 3, 58, 60, 3, 48, 8, 0, 0, 0]},
    {"id": 1, "command": "delay", "duration": 50},
    {"id": 1, "command": "inject", "events": [3, 47, 0, 3, 57, -1, 0, 0, 0]},
    {"id": 1, "command": "delay", "duration": 50},
    {"id": 1, "command": "inject", "events": [3, 47, 1, 3, 57, -1, 1, 330, 0, 0, 0, 0]},
    {"id": 1, "command": "delay", "duration": 500},
]
print("\n".join(json.dumps(c) for c in cmds))
