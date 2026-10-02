#!/bin/sh
# Phase 5 validation only (--dry-run). Usage: sh run-dryrun.sh out.json
cd "$(dirname "$0")"
sf project deploy start -o Production --dry-run -d force-app \
  --test-level RunSpecifiedTests \
  --tests LoWsPartnerTagServiceTest --tests PersonAccountDuplicateServiceTest --tests BdCommandCenterControllerTest \
  --tests ExternalLoPortalServiceTest --tests ExternalLoPortalCoverageTest --tests ExternalLoCsvImportServiceTest \
  --tests ExternalLoPartnerCsvImporterTest --tests ExternalLoActivityLogServiceTest --tests PerfectDayHomeServiceTest \
  --wait 60 --json > "${1:-dryrun.json}"
