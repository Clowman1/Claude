#!/bin/sh
# Check-only validation (phaseU5). Deploy = sf project deploy quick --job-id <id> -o Production
cd "$(dirname "$0")"
sf project deploy validate -o Production -d force-app -l RunSpecifiedTests -t LoWsCommunicationsServiceTest \
  --wait 60 --json 2>/dev/null > validate.json
