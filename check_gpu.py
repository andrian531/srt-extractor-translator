import subprocess
import sys
import re

def run(cmd):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        return r.stdout + r.stderr
    except Exception:
        return ""

def get_cuda_version():
    """Deteksi versi CUDA dari nvidia-smi"""
    out = run(["nvidia-smi"])
    m = re.search(r'CUDA Version:\s*(\d+)\.(\d+)', out)
    if m:
        return int(m.group(1)), int(m.group(2))
    return None, None

def get_torch_cuda_url(cuda_major):
    """Pilih index URL PyTorch sesuai versi CUDA dan Python"""
    import sys
    py_minor = sys.version_info.minor
    py_major = sys.version_info.major

    # Python 3.13+ butuh PyTorch cu124 minimum
    if py_major == 3 and py_minor >= 13:
        if cuda_major >= 12:
            return "cu124", "https://download.pytorch.org/whl/cu124"
        elif cuda_major == 11:
            return "cu118", "https://download.pytorch.org/whl/cu118"
        else:
            return "cpu", None
    else:
        if cuda_major >= 12:
            return "cu121", "https://download.pytorch.org/whl/cu121"
        elif cuda_major == 11:
            return "cu118", "https://download.pytorch.org/whl/cu118"
        else:
            return "cpu", None

def check_pytorch_cuda():
    """Cek apakah PyTorch yang terinstall sudah support CUDA"""
    try:
        import torch
        return torch.cuda.is_available()
    except ImportError:
        return False

def detect_gpu_vendor():
    """Deteksi vendor GPU (NVIDIA / AMD / Intel / tidak ada)"""
    # Cek NVIDIA
    out = run(["nvidia-smi", "-L"])
    if "GPU" in out and "NVIDIA" in out.upper() or "GeForce" in out or "RTX" in out or "GTX" in out:
        return "nvidia"
    # Cek AMD via rocm-smi
    out = run(["rocm-smi", "--showproductname"])
    if out and "error" not in out.lower() and len(out.strip()) > 0:
        return "amd"
    # Cek via wmic (Windows)
    out = run(["wmic", "path", "win32_VideoController", "get", "name"])
    out_lower = out.lower()
    if "nvidia" in out_lower:
        return "nvidia"
    if "amd" in out_lower or "radeon" in out_lower:
        return "amd"
    if "intel" in out_lower:
        return "intel"
    return "unknown"

if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "check"

    if mode == "detect":
        vendor = detect_gpu_vendor()
        print(f"GPU_VENDOR={vendor}")

        if vendor == "nvidia":
            cuda_major, cuda_minor = get_cuda_version()
            if cuda_major:
                print(f"CUDA_VERSION={cuda_major}.{cuda_minor}")
                tag, url = get_torch_cuda_url(cuda_major)
                print(f"TORCH_TAG={tag}")
                print(f"TORCH_URL={url}")
            else:
                print("CUDA_VERSION=unknown")
                print("TORCH_TAG=cu121")
                print("TORCH_URL=https://download.pytorch.org/whl/cu121")
        elif vendor == "amd":
            print("CUDA_VERSION=ROCm")
            print("TORCH_TAG=rocm5.6")
            print("TORCH_URL=https://download.pytorch.org/whl/rocm5.6")
        else:
            print("CUDA_VERSION=none")
            print("TORCH_TAG=cpu")
            print("TORCH_URL=none")

    elif mode == "verify":
        ok = check_pytorch_cuda()
        print("CUDA_OK=true" if ok else "CUDA_OK=false")
        if ok:
            try:
                import torch
                vram_gb = round(torch.cuda.get_device_properties(0).total_memory / 1024**3, 1)
                print(f"GPU_NAME={torch.cuda.get_device_name(0)}")
                print(f"VRAM={vram_gb}GB")
                if vram_gb >= 10:
                    print("RECOMMENDED_MODEL=large-v3")
                    print("RECOMMENDED_REASON=10GB+ VRAM: full large-v3 fits comfortably")
                elif vram_gb >= 6:
                    print("RECOMMENDED_MODEL=large-v3-turbo")
                    print("RECOMMENDED_REASON=6-10GB VRAM: best balance of speed and accuracy")
                elif vram_gb >= 4:
                    print("RECOMMENDED_MODEL=medium")
                    print("RECOMMENDED_REASON=4-6GB VRAM: medium is the safe choice")
                else:
                    print("RECOMMENDED_MODEL=small")
                    print("RECOMMENDED_REASON=<4GB VRAM: small recommended to avoid OOM")
            except Exception:
                pass
        else:
            print("RECOMMENDED_MODEL=medium")
            print("RECOMMENDED_REASON=no GPU: medium runs well on CPU")

    elif mode == "duration":
        dur_str = sys.argv[2] if len(sys.argv) > 2 else "0"
        try:
            secs = float(dur_str)
            minutes = int(secs // 60)
            hours = minutes // 60
            mins_rem = minutes - hours * 60
            print(f"VID_MIN={minutes}")
            if hours > 0:
                print(f"VID_HHMM={hours}h {mins_rem}m")
            else:
                print(f"VID_HHMM={minutes}m")
        except Exception:
            print("VID_MIN=0")
            print("VID_HHMM=unknown")
