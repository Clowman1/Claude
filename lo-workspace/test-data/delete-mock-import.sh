#!/usr/bin/env bash
# Deletes what the mock CSVs created: Leads + Person Accounts with an @loimporttest email or a
# 555-01xx phone, created on/after SINCE (keeps the older 407-555-01xx "TEST" records), plus the
# partner tags (External_User_Assignment__c) pointing at them. Soft delete -> Recycle Bin.
# Usage: bash delete-mock-import.sh [SINCE=2026-10-09]        (lists only)
#        bash delete-mock-import.sh 2026-10-09 --yes          (deletes)
set -euo pipefail
SINCE="${1:-2026-10-09}T00:00:00Z"
ORG=Production
TMP="$(mktemp -d)"

LEAD_WHERE="CreatedDate >= $SINCE AND IsConverted = false AND (Email LIKE '%loimporttest%' OR Phone LIKE '%555_01%' OR Phone LIKE '%55501%' OR MobilePhone LIKE '%555_01%')"
ACCT_WHERE="IsPersonAccount = true AND CreatedDate >= $SINCE AND (PersonEmail LIKE '%loimporttest%' OR PersonMobilePhone LIKE '%555_01%' OR PersonMobilePhone LIKE '%55501%' OR Phone LIKE '%555_01%')"

echo "== Leads"; sf data query -o $ORG -q "SELECT Id, Name, Email, Phone, Owner.Name FROM Lead WHERE $LEAD_WHERE"
echo "== Person Accounts"; sf data query -o $ORG -q "SELECT Id, Name, PersonEmail, PersonMobilePhone, Type__c FROM Account WHERE $ACCT_WHERE"
echo "== Partner tags"; sf data query -o $ORG -q "SELECT Id, User__r.Name, Contact__r.Name FROM External_User_Assignment__c WHERE Contact__c IN (SELECT PersonContactId FROM Account WHERE $ACCT_WHERE)"

[ "${2:-}" = "--yes" ] || { echo; echo "Dry run. Re-run with: bash $0 ${1:-2026-10-09} --yes"; exit 0; }

del() { # $1 sobject, $2 soql
  sf data query -o $ORG -q "$2" --result-format csv > "$TMP/$1.csv"
  [ "$(wc -l < "$TMP/$1.csv")" -gt 1 ] || { echo "$1: nothing to delete"; return; }
  sed -i 's/\r$//; s/$/\r/' "$TMP/$1.csv"   # Bulk API wants CRLF
  sf data delete bulk -o $ORG -s "$1" -f "$TMP/$1.csv" --wait 10
}
del External_User_Assignment__c "SELECT Id FROM External_User_Assignment__c WHERE Contact__c IN (SELECT PersonContactId FROM Account WHERE $ACCT_WHERE)"
del Account "SELECT Id FROM Account WHERE $ACCT_WHERE"
del Lead "SELECT Id FROM Lead WHERE $LEAD_WHERE"
