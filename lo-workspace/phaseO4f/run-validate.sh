#!/bin/sh
# Check-only validation (phaseO4f). Deploy = sf project deploy quick --job-id <id> -o Production
cd "$(dirname "$0")"
sf project deploy validate -o Production -d force-app -l RunSpecifiedTests \
  -t PerfectDayHomeServiceTest -t PerfectDayHomeBuilderTest \
  -t ExternalLoActivityLogServiceTest -t LoWsActivityLogTest \
  --coverage-formatters json-summary --results-dir coverage \
  --wait 60 --json 2>/dev/null > validate.json
