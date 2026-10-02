#!/bin/sh
# Check-only validation of force-app against Production (no deploy).
sf project deploy validate -o Production -d force-app --test-level RunSpecifiedTests \
  --tests LoWsContactServiceTest --tests LoWsBorrowerServiceTest --tests LoWsLeadDetailsServiceTest --tests LoWsLeadIntakeServiceTest \
  --tests ExternalLoPortalServiceTest --tests ExternalLoPortalCoverageTest --tests LoWsPartnerTagServiceTest \
  --tests LoWsActivityLogTest --tests ExternalLoActivityLogServiceTest --tests PerfectDayHomeServiceTest \
  --wait 60 --json > validate.json
id=$(grep -o '0AfQi[0-9A-Za-z]*' validate.json | head -1); echo "job $id"
grep -o '"message": *"[^"]*"' validate.json | head -3
sf project deploy report -o Production --job-id $id --json > report.json 2>/dev/null
grep -o '"problem": *"[^"]*"' report.json | head -20
grep -o '"status": *"[A-Za-z]*"' report.json | head -1
