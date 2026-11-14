# BUILD.md — cross-compiling the GEN5 miner for DRIVE Thor

Full, copy-paste-able recipe for building `spark-pearl-miner` (daemon) and
`spark-pearl-gpu-worker` (worker) on an x86 host for a DRIVE Thor board
(Tegra264, aarch64, DRIVE OS).

Two CUDA stacks are supported:

| Stack | nvcc | arch | Notes |
|---|---|---|---|
| **cu12.8 native** (recommended) | DRIVE OS's own CUDA 12.8 | `sm_101a` | no compat layer; `DT_NEEDED=libcudart.so.12` |
| cu13.1 compat | CUDA 13.1 sysroot nvcc | `sm_110a` | needs the compat driver layer on the board |

Measured: cu12.8/sm_101a = **100.53 T-MAC/s**, cu13.1/sm_110a = **101.05 T-MAC/s**
(bit-exact known-answer test passes on both).

## 0. One-time environment setup (x86 build host)

```bash
# Rust toolchain (rust-toolchain.toml pins 1.98.1; rustup installs it automatically)
rustup toolchain install 1.98.1 --profile minimal
rustup target add --toolchain 1.98.1 aarch64-unknown-linux-gnu

# aarch64 cross g++
sudo apt install gcc-13-aarch64-linux-gnu g++-13-aarch64-linux-gnu
which aarch64-linux-gnu-g++
```

### nvcc ccbin shim

nvcc must be told to use the cross g++ for host code. Create a shim:

```bash
mkdir -p ~/bin
# cu12.8 stack (nvcc from a CUDA 12.8 install on the host, or the board's):
printf '#!/bin/bash\nexec /usr/local/cuda-12.8/bin/nvcc -ccbin /usr/bin/aarch64-linux-gnu-g++ "$@"\n' \
  > ~/bin/nvcc-aarch64-shim-cu12.sh && chmod +x ~/bin/nvcc-aarch64-shim-cu12.sh
# cu13.1 stack (nvcc from your CUDA 13.1 sysroot):
printf '#!/bin/bash\nexec /path/to/cu13-sysroot/bin/nvcc -ccbin /usr/bin/aarch64-linux-gnu-g++ "$@"\n' \
  > ~/bin/nvcc-aarch64-shim-cu13.sh && chmod +x ~/bin/nvcc-aarch64-shim-cu13.sh
```

### CUDA_HOME link directory

`build.rs` links `-lcudart` from `CUDA_HOME`, so it needs an aarch64
`libcudart.so` laid out in the CUDA directory structure:

```bash
# cu12: pull libcudart.so.12.8.90 from the board (it ships with DRIVE OS)
mkdir -p ~/cuda-aarch64-link-128/targets/sbsa-linux/lib ~/cuda-aarch64-link-128/lib64
scp nvidia@<board-ip>:/usr/local/cuda/lib64/libcudart.so.12.8.90 \
    ~/cuda-aarch64-link-128/targets/sbsa-linux/lib/
cd ~/cuda-aarch64-link-128/targets/sbsa-linux/lib
ln -sf libcudart.so.12.8.90 libcudart.so.12 && ln -sf libcudart.so.12.8.90 libcudart.so
cp -a libcudart.so.12 libcudart.so ~/cuda-aarch64-link-128/lib64/

# cu13: the sysroot ships libcudart.so.13
mkdir -p ~/cuda-aarch64-link-131/lib64 ~/cuda-aarch64-link-131/targets/sbsa-linux/lib
ln -sf /path/to/cu13-sysroot/lib/libcudart.so.13 ~/cuda-aarch64-link-131/lib64/libcudart.so.13
ln -sf /path/to/cu13-sysroot/lib/libcudart.so.13 ~/cuda-aarch64-link-131/lib64/libcudart.so
ln -sf /path/to/cu13-sysroot/lib/libcudart.so.13 ~/cuda-aarch64-link-131/targets/sbsa-linux/lib/libcudart.so
ln -sf /path/to/cu13-sysroot/lib/libcudart.so.13 ~/cuda-aarch64-link-131/targets/sbsa-linux/lib/libcudart.so.13
```

## 1. cu12.8 native stack build (sm_101a)

```bash
export PATH=$HOME/.cargo/bin:$PATH
export NVCC=$HOME/bin/nvcc-aarch64-shim-cu12.sh
export CUDA_HOME=$HOME/cuda-aarch64-link-128
export SPM_CUDA_ARCH=sm_101a
export SPM_NVCC_FLAGS="--expt-relaxed-constexpr -DNDEBUG"
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc

# ⚠️ build.rs's rerun-if-changed watches the DIRECTORIES, not the files:
# after touching anything under cuda/ you MUST touch the directories!
touch cuda/gemm cuda/common cuda/prep

cargo build --release --target aarch64-unknown-linux-gnu -p spm-gpu -p spark-pearl-miner
# the gpu-worker binary sometimes doesn't re-link (fingerprint trap); force it:
touch crates/spm-worker/src/bin/spark-pearl-gpu-worker.rs
cargo build --release --target aarch64-unknown-linux-gnu -p spm-worker

sha256sum target/aarch64-unknown-linux-gnu/release/spark-pearl-{miner,gpu-worker}
```

## 2. cu13.1 compat stack build (sm_110a)

Same as §1 with:

```bash
export NVCC=$HOME/bin/nvcc-aarch64-shim-cu13.sh
export CUDA_HOME=$HOME/cuda-aarch64-link-131
export SPM_CUDA_ARCH=sm_110a
```

## 3. Single-file quick compile check

After editing a kernel, compile it standalone before a full build:

```bash
/usr/local/cuda-12.8/bin/nvcc -O3 -std=c++17 -DNDEBUG --expt-relaxed-constexpr -Xcompiler -fPIC \
  -I cuda/include -I third_party/cutlass/include \
  -gencode arch=compute_101a,code=sm_101a -ccbin /usr/bin/aarch64-linux-gnu-g++ \
  --compiler-options -static-libstdc++ -c cuda/gemm/gemm_umma.cu -o /tmp/gemm_umma_test.o -Xptxas -v
# cu13/sm_110a: swap nvcc for the sysroot one and arch for 110a
```

## 4. Known build traps (all hit in practice)

| Trap | Symptom | Fix |
|---|---|---|
| build.rs `rerun-if-changed` watches **directories** | edited a `.cu`, worker binary not re-linked (sha unchanged) | `touch cuda/gemm cuda/common cuda/prep` |
| gpu-worker fingerprint | daemon new, worker stale | touch the worker bin source, rebuild `-p spm-worker` |
| non-template `__global__` in a `.cuh` | link-time multiple definition (device stub) | kernel body in `.cu`; `.cuh` keeps types and declarations only |
| cu12.8 has no sm_110a | nvcc fatal: unsupported | use sm_101a on cu12; sm_110a requires cu13 nvcc |
| native libcuda + sm_110a TMA | `cuTensorMapEncodeTiled` error 999 | sm_110a needs the compat stack (compat layer ships its own libcuda) |
| cu13.1 has no sm_101a | nvcc fatal: unsupported | sysroot nvcc 13.1 only knows 100a/110a; use cu12.8 for 101a |
| `constexpr` `always_inline` host-side cute layout probes | g++ inlining failed | do layout validation at runtime on the board (kernel self-check, status=2), don't hardcode on host |

## 5. Reproducing the GEN5 port from upstream

This repo's tree = upstream clone at `6536563` + the GEN5 commits (see git log).
The ported files are: `cuda/gemm/gemm_umma.{cuh,cu}`, `cuda/common/job.cu`,
plus the `SPM_*` build switches in `crates/spm-gpu/build.rs`.
