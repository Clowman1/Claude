# Email signature logo swap (2026-10-22)

All users' signature cards (`User.Email_Signature__c`) are built by `UserTriggerHandler` from the four
`EmailSignatureTemplate__mdt` records. The Reach logo in all four was replaced:

- Old: ContentVersion `Reach_Logo` (068Qi000007NmBH), 142x53. Templates as they were: `before/`.
- New: ContentVersion `Reach_Logo_2026` (068Qi000016R6zu), public ContentDistribution link, shown at 180x47.
- Every active user was re-saved so the trigger rebuilt their card: 28/29 updated. The integration user can't be edited.
- The "Beware" banner (068Qi000007NkxQ) is unchanged.

People emails (PH-3/4/7/8) append the sender's card, so they pick up the new logo too.
