#!/bin/sh
# Check-only validation (U8c). Deploy = sf project deploy quick --job-id <id> -o Production
cd "$(dirname "$0")"
sf project deploy validate -o Production -d force-app -l RunSpecifiedTests \
  -t LeadRecycleServiceTest -t ConvertLeadsInvocableTest -t LeadConversionGuardTest \
  -t LeadConvertedTransactionSyncServiceTest -t LoWsVolumeServiceTest -t DpaSecondTransactionServiceTest \
  -t TransactionStatusAgeServiceTest \
  --wait 60 --json 2>/dev/null > validate.json
