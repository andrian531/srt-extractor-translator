import subprocess, sys
result = subprocess.run(["stable-ts", "--help"], capture_output=True, text=True, timeout=30)
print("STDOUT:", result.stdout[:5000])
print("STDERR:", result.stderr[:3000])
