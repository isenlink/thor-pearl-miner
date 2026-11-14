#!/bin/bash
# GEN5 miner start script (cu13.1 compat stack, sm_110a)
# Adjust LD_LIBRARY_PATH to your compat-layer + cu13 runtime locations.
cd "$HOME/prl-test" || exit 1
export LD_LIBRARY_PATH=/path/to/compat-layer:/path/to/cu13/runtime/lib:$HOME/prl-test
export SPM_GOVERNOR_OFF=1 SPM_MEMORY_GUARD_OFF=1
export GEN5_MINE=1

pkill -f "spark-pearl-miner daemon" 2>/dev/null
sleep 1
if pgrep -f "spark-pearl-miner daemon" >/dev/null; then
  echo "old daemon cannot be killed"; exit 1
fi

nohup ./spark-pearl-miner daemon > miner-daemon.log 2>&1 &
echo "daemon started, waiting 20s for KAT..."
sleep 20
echo "--- known-answer / KAT lines ---"
grep -iE "known.answer|kat|ready" miner-daemon.log | tail -5
echo "--- start mining ---"
./spark-pearl-miner start 2>&1 | tail -3
sleep 5
echo "--- status ---"
./spark-pearl-miner status 2>&1 | head -24
