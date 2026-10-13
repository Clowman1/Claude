#!/bin/sh
# Check-only validation (phaseO4h). No Apex changed, so one fast test class. Deploy = sf project deploy quick --job-id <id> -o Production
cd "$(dirname "$0")"
sf project deploy validate -o Production -d force-app -l RunSpecifiedTests -t AppraisalOrderController_Test \
  --wait 60 --json 2>/dev/null > validate.json
