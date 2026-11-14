# deploy/ — deployment kit

| File | Purpose |
|---|---|
| `spark-pearl-miner` | daemon binary (cu12.8 native, sm_101a, step2-uniq + D2 + D3) |
| `spark-pearl-gpu-worker` | worker binary (same build) |
| `start.sh` | start script for the cu12.8 native stack |
| `start-cu13.sh` | start script template for the cu13.1 compat stack (adjust paths) |
| `config.toml` | config template — **replace the wallet placeholder** |
| `SHA256SUMS` | checksums for the two binaries (`sha256sum -c SHA256SUMS`) |
| `cu13-backup/` | cu13.1/sm_110a build of the same binaries (backup stack) + its SHA256SUMS |
| `shims/` | nvcc cross-compile shim (for building from source, see docs/BUILD.md) |

## Deploy

```bash
mkdir -p ~/prl-test
scp deploy/spark-pearl-miner deploy/spark-pearl-gpu-worker deploy/start.sh nvidia@<board>:~/prl-test/
scp deploy/config.toml nvidia@<board>:~/.config/spark-pearl-miner/config.toml
# edit the wallet in config.toml, then on the board:
bash ~/prl-test/start.sh
```

Acceptance: see docs/OPERATIONS.md §3 (KAT line `tiles=512 hits=13`, pool active,
sha match, GR3D 0 % before start).
