#!/bin/sh
# O3 backfill: runs backfill-90d.apex for the 9 ten-day windows, oldest first (90, 80 ... 10 days ago).
# Run ONLY after the O3 deploy:  sh lo-workspace/phaseO3/run-backfill.sh
cd "$(dirname "$0")"
for d in 90 80 70 60 50 40 30 20 10; do
  sed "s/^Integer START_DAYS_AGO = [0-9]*;/Integer START_DAYS_AGO = $d;/" backfill-90d.apex > .backfill-window.apex
  sf apex run -o Production -f .backfill-window.apex 2>/dev/null | grep -o 'O3 backfill.*' || { echo "window $d FAILED - stop and check"; exit 1; }
done
rm -f .backfill-window.apex
