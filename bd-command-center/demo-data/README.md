# BD command center demo data (CEO presentation, 2026-09-30)

Fictional partners and activity loaded into **prod** under Fred Carlton so his home tab looks
lived-in. All of it comes out before Fred starts.

- `manifest.json` has every record ID created: 15 partner accounts, 22 tasks (RingCentral calls/texts,
  2 unmatched, 1 in-person touch), 9 events, 4 emails, 4 RingSense insights, 6 event campaigns with
  30 statuses and 12 invitees, and the 19 `Call_Log__c` rows the `Task_Create_Call_Log` flow made.
- Contact details are unreachable on purpose: phones `555-01xx`, emails `@example.com`. Invitee
  reminder timestamps are pre-set so the nightly reminder batch never emails them.
- No referred leads: inserting Leads would trigger lead routing, LO notifications and outbound
  integrations, so the "Referred leads" tile shows 0.

## Cleanup

```
cd bd-command-center/demo-data
node cleanup.js
```

It prints one `sf data delete bulk` command per object, in dependency order. Run them top to bottom.
Afterwards Fred's book is empty (his `BD_Rep__c` partners are all demo records). Also consider turning
`Marketing User` back off on clowman@reachhomeloans.com (turned on to create the demo campaigns).
