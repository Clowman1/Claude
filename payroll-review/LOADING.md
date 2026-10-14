# Payroll Review — monthly load

Design: [DESIGN.md](DESIGN.md). Run around the 2nd–3rd of the month, once Bianca's workbook is final.

1. **Expand the workbook** (into the scratchpad, not the repo; it is everyone's pay):
   ```powershell
   Copy-Item "<workbook>.xlsx" "$dir\p.zip"; Expand-Archive "$dir\p.zip" "$dir\x" -Force
   ```
2. **Parse + checks**: `node tools/parse-payroll.js "$dir\x" "$dir\payroll-payload.json"`
   - Prints each person's row count and paid total, then `CHECKS`.
   - `LOA MISMATCH` = the Raw Data LOA rows don't add up to the main tab's LOA pay. **Tell Christopher before loading.**
   - `TOTAL ≠ ROWS` = rows shown won't add up to the paid total (Martin's minimum guarantee did this in Sep 2026). Tell Christopher.
   - `MISSING` = a person's block or total wasn't found; the layout changed. Fix the parser.
3. **Preview**: `node tools/preview.js "$dir\payroll-payload.json" preview/<month>.html` (preview/ is gitignored). Show Christopher.
4. **Load** after his OK: `sf apex run -o Production -f "$dir\payroll-payload.apex"`
   - Fails and loads nothing if a name doesn't match exactly one active User.
   - Re-running for the same period (a correction) replaces that person's rows, keeps their feedback, and resets them to Not Reviewed so it pops up again.
5. **New person?** Add their exact User.Name to `LOS`, `LOAS` or `BONUS` at the top of `tools/parse-payroll.js`, and assign the **Payroll Review Access** permission set (without it they silently see nothing).

Status: report **Payroll Review › Payroll Review Status**. Reviews disappear for employees after Review Closes (the 11th).
