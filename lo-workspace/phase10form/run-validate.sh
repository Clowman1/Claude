#!/bin/sh
# Step 1 check-only validation (no deploy).
sf project deploy validate -o Production -d force-app --test-level RunSpecifiedTests \
  --tests LoanSubmissionWizardControllerTest --wait 60 --json > validate.json
id=$(grep -o '0AfQi[0-9A-Za-z]*' validate.json | head -1); echo "job $id"
grep -o '"status": *[0-9A-Za-z"]*' validate.json | head -2
