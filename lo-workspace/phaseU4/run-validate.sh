#!/bin/sh
# Check-only validation (phaseU4: LWC + one field + permission set, no Apex). Deploy = sf project deploy quick --job-id <id> -o Production
cd "$(dirname "$0")"
sf project deploy validate -o Production -d force-app -l RunSpecifiedTests -t EnhancedNoteControllerTest --wait 60 --json 2>/dev/null > validate.json
