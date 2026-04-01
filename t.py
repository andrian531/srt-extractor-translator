import subprocess
import time

try:
    p = subprocess.Popen(["cmd.exe", "/c", "run.bat"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    out, err = p.communicate("1\n1\n3\nS\n")
    with open("out.txt", "w", encoding="utf-8") as f:
        f.write(out)
    with open("err.txt", "w", encoding="utf-8") as f:
        f.write(err)
except Exception as e:
    with open("err.txt", "w") as f:
        f.write(str(e))
