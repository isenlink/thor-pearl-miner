#!/bin/bash
# GEN5 miner start script (cu12.8 native stack, sm_101a)
# Usage: bash ~/prl-test/start.sh   (binaries + this script in ~/prl-test/)
cd "$HOME/prl-test" || exit 1
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$HOME/prl-test
export SPM_GOVERNOR_OFF=1 SPM_MEMORY_GUARD_OFF=1
export GEN5_MINE=1
export RUST_LOG=spm_worker=debug   # attempt breakdown log (kernel_ms/wall_ms)

pkill -f "spark-pearl-miner daemon" 2>/dev/null
sleep 1
if pgrep -f "spark-pearl-miner daemon" >/dev/null; then
  echo "old daemon cannot be killed"; exit 1
fi

nohup ./spark-pearl-miner daemon > miner-daemon.log 2>&1 &
echo "daemon started, waiting 20s for KAT..."
sleep 20
echo "--- known-answer / KAT lines ---"
grep -iE "known.answer|ready" miner-daemon.log | tail -3
echo "--- start mining ---"
./spark-pearl-miner start 2>&1 | tail -2
sleep 5
echo "--- status ---"
./spark-pearl-miner status 2>&1 | head -10
