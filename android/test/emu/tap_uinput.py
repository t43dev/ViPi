import json, sys
x, y = int(sys.argv[1]), int(sys.argv[2])
def ai(code, mx): return {"code": code, "info": {"value": 0, "minimum": 0, "maximum": mx, "fuzz": 0, "flat": 0, "resolution": 0}}
cmds = [{"id": 1, "command": "register", "name": "ViPi test touch", "vid": 0x18d1, "pid": 0x7e57, "bus": "virtual",
  "configuration": [{"type": 100, "data": [1, 3]}, {"type": 101, "data": [330]}, {"type": 103, "data": [47, 48, 53, 54, 57, 58]}, {"type": 110, "data": [1]}],
  "abs_info": [ai(47, 9), ai(48, 255), ai(53, 1079), ai(54, 2399), ai(57, 65535), ai(58, 255)]},
  {"id": 1, "command": "delay", "duration": 1500},
  {"id": 1, "command": "inject", "events": [3, 47, 0, 3, 57, 1, 3, 53, x, 3, 54, y, 3, 58, 60, 3, 48, 8, 1, 330, 1, 0, 0, 0]},
  {"id": 1, "command": "delay", "duration": 60},
  {"id": 1, "command": "inject", "events": [3, 47, 0, 3, 57, -1, 1, 330, 0, 0, 0, 0]},
  {"id": 1, "command": "delay", "duration": 300}]
print("\n".join(json.dumps(c) for c in cmds))
