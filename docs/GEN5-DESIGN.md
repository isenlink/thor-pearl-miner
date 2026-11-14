# GEN5-DESIGN.md — how the 2-SM UMMA mining kernel works

Condensed from the port design notes. All claims verified against the source
tree and the `spm-cpuref` oracle.

## 1. The pool's PoW semantics (oracle = authoritative)

The "hash" is an INT8 matrix multiplication. Per attempt:

- **Inputs**: `A' = fill_int7(gen_seed, DOMAIN_A) + E_A`, `B'ᵀ = fill + E_Bᵀ`
  (noise factors fixed by the commitment; the noise is purely additive — no
  denoise/correction terms).
- **GEMM**: `C' = A'·B'ᵀ` over the full K, exact i32 accumulation.
- **Hash tiles**: 8×16 output tiles selected by the pool config's
  `rows_pattern`/`cols_pattern`, scattered across the m×n output
  (`offset_is_valid`).
- **Transcript (per hash tile)**: K is sliced by rank r with `SLICE_K=128`
  (32 slices at K=4096). After each slice, XOR-fold **all 128 accumulated
  accumulator values** of the tile: `fold = XOR(acc as u32)`, then
  `t[s%16] = rotl13(t[s%16]) ^ fold` (16 transcript words, ROTL=13).
- After all slices: rotate back by `k_slices % 16` →
  `digest = compute_jackpot_hash(transcript, a_noise_seed)`.
- **Hit**: `digest < bound` (little-endian U256) → `Hit{t_rows, t_cols, digest}`.

The pure-Rust reference (`crates/spm-cpuref`) implements exactly this and is
the known-answer authority: the GPU kernel must be **bit-exact** against it.

## 2. How the gen4 kernel does it (reference: `cuda/gemm/gemm_tma.cuh`)

`mma.sync` IMMA: each thread owns exactly one hash tile's 128 accumulators
(fragment layout `2*(l%4)+{0,1,8,9,…,56,57}`). Per r=128 K columns
(2 stages × 64): thread-local XOR fold → rotl13 into the register transcript
(register rotation queue keeps static indices). After the K loop: rotate back
+ BLAKE3 digest + bound compare — all fused in one kernel.

## 3. The GEN5 UMMA kernel (`cuda/gemm/gemm_umma.{cuh,cu}`)

Built on the verified 2-SM UMMA GEMM base (256×256×128, 2×1 cluster, s5,
swizzle=8):

- **UMMA main loop** (tcgen05, 2-SM clusters) accumulates the full GEMM in
  TMEM.
- **Per-128-K-slice hash-tile readout**: the 16×8 pattern points of each hash
  tile are scattered inside the 128×256 CTA tile (32 hash tiles per CTA tile);
  each slice reads 4096 i32 ≈ 16 KB out of TMEM.
- **Register transcript**: each warp owns its lane range of pattern points —
  XOR fold + rotl13 exactly as the oracle.
- **Epilogue**: after K, BLAKE3 (reused from `cuda/`) + bound compare, fused.

### Chunking and abort

The kernel runs in chunks (bounded work per launch). The GEN5 abort contract
is **status-only**: the kernel checks a host-mapped abort word and exits
cleanly; it does NOT drain in-kernel (an early-exit drain poisoned the CUDA
context — that bug is fixed by the status-only abort commit). Worst-case
cancel latency ≈ 2 chunks × 8 ms, a documented deviation from the stock
single-chunk ≤10 ms rule, acceptable on a dedicated board with no co-resident
compute.

The chunk ceiling is derived from the **measured** UMMA rate (100.5 T-MAC/s
at 1.53 GHz pinned) with a 30 % slowdown margin, instead of the gen4
clock-floor constant — the fixed per-chunk cost (cluster launch, TMEM alloc,
pipeline init, tail wave, host round trip) otherwise eats 40–60 % of the wall
clock.

## 4. Wedge-prevention patches (default OFF)

From the static audit of all 15 UMMA call sites against the stock kernel:

- **`SPM_D2_SYNCWARP`** — warp-synchronisation guard around the TMEM readout
  window.
- **`SPM_D3_RENDEZVOUS`** — cluster rendezvous so both CTAs' MMA warps
  synchronise before either frees TMEM.

Both restore stock parity at the deviation points; both are off by default so
a plain build is upstream-identical.

## 5. Measured performance (14-SM Thor board)

| Config | 4096³ | 16384²×4096 |
|---|---|---|
| 256×256×128, 2×1, s5 (production) | 160.99 | **105.24** |
| 256×256×64, 2×1, s5 | 146.92 | 104.26 |
| 256×128×64, 2×2, s4 | 83.10 | 81.52 |
| 128×256×64, 2×1, s4 | — | **wedges (black-listed)** |

MMA-unit ceiling (NoSmem epilogue, no D store): 120.15 T-MAC/s at extreme K —
the single-kernel i8 limit is ~120 (81 % of the 149 T theoretical). The
mining shape (K=4096) pays ~11 % bandwidth loss; the production credited rate
is 101.05 T-MAC/s (cu13/sm_110a) / 100.53 (cu12/sm_101a).

**Black-list**: all M=128 tiles in 2×1 clusters are unstable (launch failure
or TMEM assertion → D-state wedge). M=256 tiles are all stable.
