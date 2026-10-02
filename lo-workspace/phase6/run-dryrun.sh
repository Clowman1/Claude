#!/bin/sh
# Phase 6 check-only validation. Usage: sh run-dryrun.sh out.json
cd "$(dirname "$0")"
sf project deploy validate -o Production -d force-app \
  --test-level RunSpecifiedTests \
  --tests LoWsLeadIntakeServiceTest --tests LoWsPartnerTagServiceTest \
  --tests ExternalLoPortalServiceTest --tests ExternalLoPortalCoverageTest \
  --tests ExternalLoCsvImportServiceTest --tests ExternalLoPartnerCsvImporterTest \
  --tests PerfectDayHomeServiceTest \
  --wait 60 --json > "${1:-dryrun.json}"
