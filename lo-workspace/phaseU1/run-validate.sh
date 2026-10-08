#!/bin/sh
# Check-only validation (phaseU1). Deploy = sf project deploy quick --job-id <id> -o Production
cd "$(dirname "$0")"
sf project deploy validate -o Production -d force-app -l RunSpecifiedTests \
  -t ExternalLOBaselineHelperTest -t ExternalLoPortalServiceTest -t ExternalLoPortalCoverageTest -t ExternalLoPromptServiceTest \
  -t PerfectDayHomeServiceTest -t PerfectDayHomeBuilderTest -t LoWsCalendarServiceTest -t ExternalLoActivityLogServiceTest \
  -t LoWsActivityLogTest -t UserTriggerHandlerTest -t LoWsContactServiceTest -t LoWsPartnerTagServiceTest \
  -t LoWsPastClientDetailTest -t LoWsBorrowerServiceTest -t LoWsLeadDetailsServiceTest -t LoWsLeadIntakeServiceTest \
  -t LoWsLeadStatusTest \
  --wait 60 --json 2>/dev/null > validate.json
