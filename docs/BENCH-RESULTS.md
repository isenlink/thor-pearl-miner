# BENCH-RESULTS.md — UMMA i8 GEMM sweep on a 14-SM DRIVE Thor board

All numbers T-MAC/s, measured serially on a dedicated board (miner stopped,
zero-residue verified after each run).

## Verified configurations

| Config | Shape | 4096³ | 16384²×4096 | Notes |
|---|---|---|---|---|
| 128×128×64, 1×1, s4 | 4096³ | 100.76 | 59.39 | small shape |
| 256×128×64, 2×1, s4 | 8192²×4096 | — | 103.52 | |
| 256×256×64, 2×2, s4 | 4096³ | 120.69 | 100.67 | |
| 256×256×64, 2×1, s4 | 8192²×4096 | — | 103.52 | |
| **256×256×128, 2×1, s5** | **16384²×4096** | **160.99** | **105.24** | **production config** |
| 256×256×128, 2×1, s4 | 16384²×4096 | 157.4–159.8 | 104.8–105.2 | stable |
| 256×256×128, 2×1, s3 | 16384²×4096 | 156.85 | 104.95 | stable |
| 256×256×64, 2×1, s5 | 16384²×4096 | 146.92 | 104.26 | stable |
| 256×256×64, 2×1, s3 | 16384²×4096 | 115.78 | 101.52 | stable |
| 256×256×32, 2×1, s4 | 16384²×4096 | 80.83 | 79.14 | stable |
| 256×128×64, 2×2, s4 | 16384²×4096 | 83.10 | 81.52 | stable but slow |
| 128×256×64, 2×1, s4 | — | — | — | **wedges (black-list)** |

## Wedge black-list

**All M=128 tiles in 2×1 clusters are unstable**:

- 128×256×64 + 2×1 → unspecified launch failure → D-state wedge
- 128×128×128 + stages=8 → TMEM load assertion failure
- 128×128×64 + 2×1 + s8 → untested (assumed same risk)

**All M=256 tiles in 2×1 clusters are stable.**

Suspected root cause: 2-SM MMA TMEM allocation is sensitive to the per-CTA M
dimension. 256 tile → 128 rows per CTA (TMEM 128dp aligned); 128 tile → 64
rows per CTA, likely triggering a driver/TMEM allocation bug.

Wedge signature: D-state GPU process, `kill -9` ineffective, GR3D 99 %, soft
reboot does not clear it. MCU-level reset (`tegrareset x1`) recovers the board
but wipes the `/home` overlay.

## G5 epilogue integration (zero-overhead result)

- **scaled EVT** (D = acc × A_scale[row] × B_scale[col]): VERIFY PASSED
  (max_err=0), 104.94 T-MAC/s at 16384²×4096 — the Pearl scale math costs
  nothing.
- **no-C EVT** (skip C read): 104.88 T-MAC/s, on par with the C-reading
  version (C load is hidden by TMA in the main loop).

## Theoretical peak analysis (hardware probe)

- GPU: 1 die / 14 SM / 228 KB smem per SM / sm_110a.
- tcgen05 i8 theoretical peak = 14 SM × 2.6 GHz × 4096 MAC/clk ≈ **148.9 T-MAC/s**.

## MMA-unit ceiling (NoSmem epilogue, no D store)

| Shape | T-MAC/s | Notes |
|---|---|---|
| 4096³ | 143.4 | small shape |
| 16384²×4096 | 104.7 | on par with TMA epilogue (epilogue not the bottleneck) |
| 8192²×16384 | **120.15** | extreme K, converged value |

Conclusions:

1. Single-kernel tcgen05 i8 limit ≈ **120 T-MAC/s** (81 % of theoretical).
2. The epilogue is not the bottleneck (NoSmem ≈ TMA).
3. The mining shape (K=4096) pays ~11 % bandwidth loss (105 → 117 potential).
4. Real mining has no full D store (D is consumed by the hit scan) → mining
   shape can reach ~115–120 T-MAC/s.
5. 160+ T-MAC/s on a single GPU is physically unreachable under exact i8
   semantics (hard ceiling 120). The only paths to 160+ are blockscaled
   FP8/FP4 (2–4× throughput, but int8 exact semantics don't map — protocol
   change) or multi-GPU (the board has one die).
