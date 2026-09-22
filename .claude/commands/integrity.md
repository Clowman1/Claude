---
description: Active file data integrity report (live read from Salesforce prod)
allowed-tools: Bash(node --no-deprecation .claude/integrity.mjs:*)
---

Run the active-file data integrity report against the connected Salesforce org:

!`node --no-deprecation .claude/integrity.mjs`

Summarize what changed in priority order. Lead with CRITICAL findings and name
the Loan Officer who owns each one, since they are the person who has to fix it.
Do not modify any record — this report is read-only. If the user asks for fixes,
propose the change and wait for confirmation before writing anything.
