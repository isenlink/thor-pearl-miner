# Thor Pearl Miner — GEN5 UMMA mining kernel for NVIDIA DRIVE Thor

**Run the [Spark Pearl Miner](https://github.com/xXGuilasXx/spark-pearl-miner) on NVIDIA DRIVE Thor (Tegra264, sm_110a / sm_101a) with a 5th-generation 2-SM UMMA INT8 kernel — 101 T-MAC/s measured, bit-exact against the pure-Rust reference.**

This repository is a fork of `xXGuilasXx/spark-pearl-miner` (base commit `6536563`) carrying the GEN5 port: a 2-SM UMMA (tcgen05) mining kernel for DRIVE Thor hardware, its wedge-prevention patches, a pure-Rust reference oracle, and a complete cross-compilation + deployment guide for DRIVE OS boards.

> **Unofficial project.** Not affiliated with, sponsored by, or endorsed by NVIDIA or Pearl Research Labs. Upstream is built for the DGX Spark (GB10); this fork adds the DRIVE Thor path.

## Why DRIVE Thor

The upstream miner targets the DGX Spark's GB10 (`sm_121a`). DRIVE Thor (Tegra264) has a different tensor-core generation — the 5th-gen UMMA (tcgen05) instructions with 2-SM clusters — and a different CUDA stack (DRIVE OS ships CUDA 12.8 natively; CUDA 13.1 is available as a compat layer). The GEN5 kernel exploits exactly that hardware:

| Metric | Value | Conditions |
|---|---|---|
| **Credited mining rate** | **101.05 T-MAC/s** | cu13.1 compat stack, sm_110a, 256×256×128 tile, 2×1 cluster, s5 |
| Alternative stack | 100.53 T-MAC/s | cu12.8 native, sm_101a (no compat layer needed) |
| Bit-exactness | PASS | 512-tile known-answer test vs `spm-cpuref` oracle, both stacks |
| Theoretical ceiling | ~120 T-MAC/s | 14 SM × 2.6 GHz × 4096 MAC/clk ≈ 149; MMA-unit measured limit 120.15 |
| GPU power (mining) | ~60 W class | well below the board's thermal envelope |

The credited rate is what the pool pays for; it moves in steps because the pool credits whole attempts (7.04e13 MACs each). What that earns depends on network difficulty and the PRL price — check your pool's website. This is not financial advice.

## What's in this fork (vs upstream `6536563`)

1. **`GEN5_MINE` kernel** — `cuda/gemm/gemm_umma.{cuh,cu}`: 2-SM UMMA INT8 GEMM with per-128-K-slice hash-tile transcript (XOR fold + rotl13), BLAKE3 digest, bound comparison — the full Pearl PoW fused in one kernel.
2. **status-only abort** — in-kernel early-exit drain poisoned the CUDA context; abort is now status-only (documented deviation from the stock single-chunk ≤10 ms rule: worst-case cancel latency ≈ 2 chunks × 8 ms, acceptable on a dedicated board).
3. **Adaptive chunk ceiling** — re-derived from the measured UMMA rate (100.5 T-MAC/s @ 1.53 GHz pinned) with a 30 % slowdown margin, instead of the gen4-calibrated clock-floor constant.
4. **`SPM_STEP2_UNIQ`** — Step2 unique-slot fold, +7 % credited throughput (50.4 → 53.9 T-MAC/s credited), **default OFF**.
5. **`SPM_D2_SYNCWARP` / `SPM_D3_RENDEZVOUS`** — wedge-prevention patches (warp synchronisation guard; cluster rendezvous before TMEM free), stock parity, **default OFF**.
6. **cpuref oracle** — `tile_from_rows_fold_every` in `crates/spm-cpuref`: pure-Rust reference for the (frozen, not being pursued) `SPM_FOLD_EVERY=N` proposal. `cargo test -p spm-cpuref` passes (11 tests).

**All experimental kernels are opt-in via preprocessor macros** injected through the standard `SPM_NVCC_FLAGS` build variable. A plain build produces exactly the upstream semantics. See the "Experimental GPU kernels" section of the README in the tree.

## Quick start (prebuilt binaries)

Prebuilt aarch64 binaries for DRIVE Thor (DRIVE OS, CUDA 12.8 native stack) are in the [Releases](https://github.com/isenlink/thor-pearl-miner/releases). Verify with `SHA256SUMS`, then:

```bash
# on the board (user nvidia)
mkdir -p ~/prl-test && cd ~/prl-test
# copy spark-pearl-miner, spark-pearl-gpu-worker, start.sh, config.toml here
bash start.sh
~/prl-test/spark-pearl-miner status
```

Acceptance checklist (all four must hold):

1. daemon log shows the known-answer line: `tiles=512 hits=13`
2. `status` shows pool 1 active
3. binary sha256 matches `SHA256SUMS`
4. `tegrastats` GR3D starts at 0 % and rises only after mining starts

## Build from source (cross-compile on x86)

Full recipe: [docs/BUILD.md](docs/BUILD.md). Summary:

```bash
rustup toolchain install 1.98.1 --profile minimal
rustup target add --toolchain 1.98.1 aarch64-unknown-linux-gnu
sudo apt install gcc-13-aarch64-linux-gnu g++-13-aarch64-linux-gnu

export NVCC=~/bin/nvcc-aarch64-shim-cu12.sh        # see docs/BUILD.md
export CUDA_HOME=~/cuda-aarch64-link-128           # aarch64 libcudart link dir
export SPM_CUDA_ARCH=sm_101a                       # cu12.8; sm_110a needs cu13 nvcc
export SPM_NVCC_FLAGS="--expt-relaxed-constexpr -DNDEBUG"
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc

touch cuda/gemm cuda/common cuda/prep              # build.rs rerun trap, see BUILD.md
cargo build --release --target aarch64-unknown-linux-gnu -p spm-gpu -p spark-pearl-miner
touch crates/spm-worker/src/bin/spark-pearl-gpu-worker.rs
cargo build --release --target aarch64-unknown-linux-gnu -p spm-worker
```

## Operations

Runbook (status checks, start/stop, post-reset redeployment, kernel-test discipline, wedge symptoms and handling): [docs/OPERATIONS.md](docs/OPERATIONS.md).

Two rules that matter most:

- **Never run kernel experiments while the miner is running** — concurrent TMEM users wedge the GPU (D-state processes, GR3D 99 %, `kill -9` ineffective). Stop the miner first, test serially in the foreground, verify zero residue afterwards.
- **A wedged GPU does not recover from a soft reboot.** On DRIVE OS the reliable reset is `tegrareset x1` (MCU-level) — and it wipes the `/home` overlay, so keep a redeployment kit (binaries + config + start script) ready; see OPERATIONS.md §3.

## Technical design

[docs/GEN5-DESIGN.md](docs/GEN5-DESIGN.md): the pool's PoW semantics (transcript, fold, digest), how the gen4 kernel works, and how the GEN5 UMMA kernel reads hash tiles out of TMEM per K-slice.

## Benchmarks

[docs/BENCH-RESULTS.md](docs/BENCH-RESULTS.md): full tile/cluster/stage sweep on a 14-SM Thor board, wedge black-list (M=128 tiles in 2×1 clusters are unstable), MMA-unit ceiling measurements, and the theoretical-peak analysis.

## Relationship to upstream

- Upstream: `xXGuilasXx/spark-pearl-miner` — the canonical project, built for DGX Spark.
- This fork: `isenlink/thor-pearl-miner` — the DRIVE Thor distribution point. The same commits are proposed upstream via PR [xXGuilasXx/spark-pearl-miner#5](https://github.com/xXGuilasXx/spark-pearl-miner/pull/5); once merged, this repo tracks upstream + Thor-specific docs.
- Fee logic, pool list, and default mining behaviour are unchanged from upstream. The 2 % developer fee goes to the upstream project's wallet (protocol-fixed, not configurable).

## License

Apache-2.0, same as upstream.
