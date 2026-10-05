#!/bin/sh
# Check-only validation (phase10client). Deploy = same command with `sf project deploy quick --job-id <id>` or `deploy start`.
cd "$(dirname "$0")"
sf project deploy validate -o Production -d force-app -l RunSpecifiedTests \
  -t ExternalLoPortalServiceTest -t ExternalLoPortalCoverageTest -t LoWsContactServiceTest -t LoWsPartnerTagServiceTest \
  -t PerfectDayHomeServiceTest -t LoWsActivityLogTest -t ExternalLoActivityLogServiceTest -t LoWsPastClientDetailTest \
  -t LoWsBorrowerServiceTest -t LoWsLeadDetailsServiceTest -t LoWsLeadIntakeServiceTest -t LoWsLeadStatusTest \
  --wait 60 --json 2>/dev/null > validate.json
