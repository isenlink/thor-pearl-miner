# OPERATIONS.md — running the GEN5 miner on a DRIVE Thor board

Assumes: DRIVE OS board, user `nvidia`, CUDA 12.8 native stack (or cu13.1 compat),
binaries deployed to `~/prl-test/` (see the Release assets or `deploy/`).

## 1. Status checks (read-only, safe anytime)

```bash
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$HOME/prl-test
~/prl-test/spark-pearl-miner status                 # rate / shares / pool / alerts
pgrep -fa "spark-pearl-miner" | grep -v bash        # daemon + worker, one each
timeout 3 tegrastats | head -1                      # GR3D / temps / RAM (idempotent)
grep HugePages_Free /proc/meminfo                   # full pool = no resident GPU allocations
```

The daemon log (`~/prl-test/miner-daemon.log`, truncated on every daemon restart)
is the primary diagnostic source.

## 2. Start / stop

```bash
# start (script: pkill old daemon → nohup → wait for KAT → start → status)
bash ~/prl-test/start.sh

# stop mining only (daemon stays up):
~/prl-test/spark-pearl-miner stop

# kill everything (run from a script FILE, not an ssh one-liner — see the pkill rule below):
cat > /tmp/killminer.sh <<'EOF'
#!/bin/bash
pkill -f "spark-pearl-miner"; sleep 2
pgrep -f "spark-pearl-miner" && echo "residue" || echo clean
EOF
bash /tmp/killminer.sh
```

⚠️ **pkill rule**: the pattern string must not appear in the outer ssh command line
(self-matching kills your own shell). Put it in a script file, or use the
bracket trick: `pgrep -f "[s]park-pearl-miner"`.

## 3. Redeployment after a board reset

**`tegrareset` (and a full power cycle) wipes the `/home` overlay** — config,
scripts and binaries in `~/` are gone. Keep a redeployment kit and re-stage:

```bash
# from the host that holds this repo's deploy/ directory:
scp deploy/spark-pearl-miner deploy/spark-pearl-gpu-worker deploy/start.sh \
    nvidia@<board-ip>:~/prl-test/
scp deploy/config.toml nvidia@<board-ip>:~/.config/spark-pearl-miner/config.toml
# on the board:
bash ~/prl-test/start.sh
```

Acceptance (all four):

1. daemon log known-answer line: `tiles=512 hits=13`
2. `status` shows pool 1 active
3. sha256 of both binaries matches `deploy/SHA256SUMS`
4. GR3D at 0 % before start, rising only after

Tip: keep the kit on a persistent partition (e.g. `/zeekr_data/` on Zeekr
boards) so it survives resets.

## 4. Kernel-test discipline (hard-won)

1. **Stop the miner first** (`pgrep -f spark-pearl-miner` until clean).
   Concurrent TMEM users wedge the GPU — a probe run alongside the miner
   produced a false 40.85 T-MAC/s reading and a wedged board.
2. Run a CUDA sanity check first (any small kernel that must pass).
3. Test serially, foreground, one command at a time.
4. After testing, verify zero residue: GR3D 0 %, hugepage pool full, no D-state
   processes, no leftover processes.
5. **Wedge symptoms**: D-state GPU process that `kill -9` cannot kill + GR3D 99 %.
   A soft reboot does NOT clear it. The reliable reset is MCU-level
   (`tegrareset x1` from the MCU shell) — and it wipes `/home` (redeploy per §3).
   Expect the board to be unreachable for several minutes after; poll, don't panic.

## 5. Pools and wallet

- Edit `~/.config/spark-pearl-miner/config.toml` (wallet, worker name, pools).
  The daemon hot-applies pool changes within seconds — no restart needed;
  share counters resetting is normal.
- The 2 % developer fee goes to the upstream project's wallet (protocol-fixed,
  not configurable).
- Your credited rate ≈ kernel rate × efficiency (node staleness, difficulty
  variance convergence, work rotation churn, dev fee).

## 6. Config template

`deploy/config.toml` is a working template — replace the wallet placeholder
with your own Pearl address (`prl1…`) and pick your pools.
