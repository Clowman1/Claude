#!/bin/sh
# Check-only validation of U8a+U8b together (compile + tests). Deploy order: U8a (fields+permset) first, then U8b.
cd "$(dirname "$0")"
sf project deploy validate -o Production -d force-app -l RunSpecifiedTests \
  -t LeadRecycleContextTest -t BizDevReachPreApprovalWebhookServiceTest -t LeadBdAttributionTest \
  -t LeadLoanPartnerAssignmentServiceTest -t ManualLeadOwnerNotificationServiceTest \
  --wait 60 --json 2>/dev/null > validate.json
