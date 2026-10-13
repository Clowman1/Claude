#!/usr/bin/env node
// Active-file data integrity report. Read-only: one SOQL SELECT, no writes.
//   node .claude/integrity.mjs            report to stdout + append to log
//   node .claude/integrity.mjs --daily    same, but silent on weekends / repeat sessions
//   node .claude/integrity.mjs --json     machine-readable, no log append
import { execFileSync } from 'node:child_process';
import { writeFileSync, appendFileSync, mkdtempSync, existsSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const LOG = join(import.meta.dirname, 'integrity-log.md');
const STAMP = join(import.meta.dirname, '.integrity-last-run');

const FIELDS = [
  'Id', 'Name', 'Status__c', 'Channel__c', 'MERS_Min__c', 'Loan_Number__c',
  'Loan_Amount_1st__c', 'Rate_1st_TD__c', 'Loan_Purpose__c', 'Loan_Type_1st_TD__c',
  'Loan_Type_2nd_TD__c', 'Loan_Program_1st__c', 'Lien_Position__c', 'Occupancy__c', 'Lead_Source__c', 'Biz_Dev__c', 'Property_Address__c', 'Property_City__c',
  'Property_State__c', 'Property_Postal_Code__c', 'Property_Type__c', 'Closing_Date__c',
  'Loan_Application_Date__c', 'TRID_Date__c',
  'Disclosures_Out_Date__c', 'Disclosures_Received_Date__c',
  'Borrower_SSN__c', 'Borrower_Name__c', 'Borrower_Name__r.Name',
  'Borrower_Name__r.IsPersonAccount', 'Borrower_Name__r.SSN__pc',
  'Borrower_Name__r.PersonBirthdate', 'Loan_Officer__r.Name',
];
const CLOSED = ['Post-Closed', 'Cancelled', 'Lost'];
const SOQL = `SELECT ${FIELDS.join(', ')} FROM Transaction__c ` +
  `WHERE Status__c NOT IN (${CLOSED.map(s => `'${s}'`).join(',')})`;

// Pipeline rank, in Status__c picklist order. PC Review sits AFTER Closing -- verified
// 2026-09-22: every PC Review file has a past closing date and a stamped Clear-to-Close,
// every Closing file is still in the future.
const RANK = {
  'TRID Application': 1, 'Open': 2, 'Disclosures Out': 3, 'Pre-Processing': 4,
  'Processing': 5, 'Submitted': 6, 'Suspended': 7, 'Waiting On Loan Officer': 8,
  'Conditionally Approved': 9, 'Re-Submitted': 10, 'Approved': 11, 'Closing': 12,
  'Funding': 13, 'PC Review': 15,
};
// A file is not expected to hold complete data until it reaches Pre-Processing, so
// everything earlier (TRID Application, Open, Disclosures Out) is out of scope.
const MIN_RANK = RANK['Pre-Processing'];
const SUBMITTED_RANK = RANK['Submitted'];
const CLOSING_RANK = RANK['Closing'];

const today = new Date(new Date().toDateString());

// Normalize everything to a calendar date in the org's timezone. Date fields arrive as
// plain YYYY-MM-DD; DateTime fields arrive in UTC, so reading the date straight off the
// UTC string pushes any late-afternoon Eastern timestamp into the next day and invents
// out-of-sequence findings. Org TimeZoneSidKey is America/New_York.
const ORG_TZ = 'America/New_York';
const tzFmt = new Intl.DateTimeFormat('en-CA', {
  timeZone: ORG_TZ, year: 'numeric', month: '2-digit', day: '2-digit',
});
const D = (v) => {
  if (v == null) return null;
  const s = String(v);
  if (/^\d{4}-\d{2}-\d{2}$/.test(s)) {            // date-only field, already local
    const p = s.split('-');
    return new Date(+p[0], +p[1] - 1, +p[2]);
  }
  const p = tzFmt.format(new Date(s)).split('-'); // en-CA formats as YYYY-MM-DD
  return new Date(+p[0], +p[1] - 1, +p[2]);
};
const dayDiff = (a, b) => Math.round((D(a) - D(b)) / 86400000);
const bizDays = (a, b) => {
  let s = new Date(D(a));
  const e = D(b);
  let n = 0;
  while (s < e) { s.setDate(s.getDate() + 1); const d = s.getDay(); if (d !== 0 && d !== 6) n++; }
  return n;
};
const digits = v => String(v).replace(/[^0-9]/g, '');
const isTest = x => /^test/i.test(x.Name || '') || /^(123456|1234|0+)$/.test(x.Loan_Number__c || '');

const CATS = {
  loan: 'LOAN DATA COMPLETENESS / INVALID VALUES',
  trid: 'TRID / DISCLOSURE DATES',
  mers: 'MERS MIN (CORRESPONDENT FILES)',
  borrower: 'BORROWER PERSON ACCOUNT / SSN / BIRTHDATE',
};

function evaluate(rows) {
  const F = { loan: [], trid: [], mers: [], borrower: [] };
  const add = (cat, x, reason) => F[cat].push({
    name: x.Name, id: x.Id, status: x.Status__c,
    lo: (x.Loan_Officer__r || {}).Name || '-', reason,
  });

  for (const x of rows) {
    const rank = RANK[x.Status__c] || 1;
    const b = x.Borrower_Name__r;

    // --- loan data completeness / invalid values ---
    if (x.Loan_Amount_1st__c == null) add('loan', x, 'Loan Amount is blank');
    else if (x.Loan_Amount_1st__c <= 0) add('loan', x, 'Loan Amount is not positive: ' + x.Loan_Amount_1st__c);
    else if (x.Loan_Amount_1st__c > 10000000) add('loan', x, 'Loan Amount implausibly high: ' + x.Loan_Amount_1st__c);

    // Down-payment-assistance seconds are routinely 0.00%, so a zero rate is expected there.
    const isDPA = x.Loan_Type_1st_TD__c === 'DPA 2nd' || x.Loan_Type_2nd_TD__c === 'DPA 2nd';
    if (x.Rate_1st_TD__c == null) add('loan', x, 'Interest Rate is blank');
    else if (x.Rate_1st_TD__c === 0 && isDPA) { /* expected for DPA 2nd */ }
    else if (x.Rate_1st_TD__c <= 0 || x.Rate_1st_TD__c > 15) add('loan', x, 'Interest Rate out of plausible range: ' + x.Rate_1st_TD__c);

    if (!x.Loan_Purpose__c) add('loan', x, 'Loan Purpose is blank');
    if (!x.Loan_Type_1st_TD__c) add('loan', x, 'Loan Type is blank');
    if (!x.Loan_Program_1st__c) add('loan', x, 'Loan Program is blank');
    if (!x.Lien_Position__c) add('loan', x, 'Lien Position is blank');
    // Blank only: Occupancy and Lead Source are unrestricted picklists full of legacy spellings
    // (Primary, 2ndHome, TikTok...) that are real data. Biz Dev 'None' is a deliberate value.
    if (!x.Occupancy__c) add('loan', x, 'Occupancy is blank');
    if (!x.Lead_Source__c) add('loan', x, 'Lead Source is blank');
    if (!x.Biz_Dev__c) add('loan', x, 'Biz Dev is blank');
    if (!x.Loan_Number__c) add('loan', x, 'Loan Number is blank');
    if (!x.Channel__c) add('loan', x, 'Channel is blank (neither Broker nor Correspondent)');
    if (!x.Property_Address__c) add('loan', x, 'Property Address is blank');
    if (!x.Property_City__c) add('loan', x, 'Property City is blank');
    if (!x.Property_State__c) add('loan', x, 'Property State is blank');
    else if (!/^[A-Za-z]{2}$/.test(x.Property_State__c.trim())) add('loan', x, 'Property State not a 2-letter code: ' + x.Property_State__c);
    if (!x.Property_Postal_Code__c) add('loan', x, 'Property Postal Code is blank');
    else if (/^[0-9]{9}$/.test(x.Property_Postal_Code__c.trim())) add('loan', x, 'Property Postal Code is ZIP+4 stored without hyphen: ' + x.Property_Postal_Code__c);
    else if (!/^[0-9]{5}(-[0-9]{4})?$/.test(x.Property_Postal_Code__c.trim())) add('loan', x, 'Property Postal Code malformed: ' + x.Property_Postal_Code__c);
    if (!x.Property_Type__c) add('loan', x, 'Property Type is blank');

    if (rank >= SUBMITTED_RANK && !x.Closing_Date__c) add('loan', x, 'Closing Date is blank at status ' + x.Status__c);
    // A past closing date is normal at Closing and beyond; it only signals a stalled file
    // when the status has not yet reached Closing.
    else if (x.Closing_Date__c && rank < CLOSING_RANK && dayDiff(x.Closing_Date__c, today) < 0) {
      add('loan', x, 'Closing Date passed (' + x.Closing_Date__c + ') but status is only ' + x.Status__c);
    }

    // --- TRID / disclosure dates ---
    // Loan_Application_Date__c and File_Open_Date__c are 0% populated org-wide (dead fields).
    // TRID_Date__c is the live application/TRID-clock anchor.
    // TRID compliance is tracked on Disclosures Out Date and Disclosures Received Date.
    // Received is stamped automatically when the borrower signs, so a blank Received on an
    // aging file means unsigned disclosures, not a data-entry gap.
    // Initial_Loan_Estimate__c (25/38) is NOT the compliance field and is not checked.
    // Disclosures_Due_Date__c is 0% populated org-wide and is not checked.
    const appDate = x.TRID_Date__c || x.Loan_Application_Date__c || null;
    if (!appDate) add('trid', x, 'No application/TRID date (TRID_Date__c blank)');

    if (!x.Disclosures_Out_Date__c) {
      add('trid', x, 'Disclosures Out Date blank at status ' + x.Status__c);
    } else if (appDate) {
      if (dayDiff(x.Disclosures_Out_Date__c, appDate) < 0) {
        add('trid', x, 'Disclosures sent BEFORE the TRID date');
      } else if (bizDays(appDate, x.Disclosures_Out_Date__c) > 3) {
        add('trid', x, 'Disclosures sent ' + bizDays(appDate, x.Disclosures_Out_Date__c) +
          ' business days after the TRID date (TRID limit 3)');
      }
    }

    if (x.Disclosures_Out_Date__c && x.Disclosures_Received_Date__c &&
        dayDiff(x.Disclosures_Received_Date__c, x.Disclosures_Out_Date__c) < 0) {
      add('trid', x, 'Disclosures received BEFORE they were sent');
    }
    if (x.Disclosures_Out_Date__c && !x.Disclosures_Received_Date__c &&
        dayDiff(today, x.Disclosures_Out_Date__c) > 7) {
      add('trid', x, 'Disclosures out ' + dayDiff(today, x.Disclosures_Out_Date__c) +
        ' days, still unsigned (no Received date)');
    }

    // --- MERS MIN, Correspondent channel only ---
    if (x.Channel__c === 'Correspondent') {
      if (!x.MERS_Min__c) add('mers', x, 'Correspondent file with no MERS MIN');
      else if (digits(x.MERS_Min__c).length !== 18) add('mers', x, 'MERS MIN not 18 digits (got ' + digits(x.MERS_Min__c).length + ')');
    }

    // --- borrower Person Account / SSN / birthdate ---
    // Presence and format only. SSN values are never printed or logged.
    if (!x.Borrower_Name__c) { add('borrower', x, 'No Borrower linked'); continue; }
    if (b && b.IsPersonAccount === false) add('borrower', x, 'Borrower is a business Account, not a Person Account');
    const ssn = (b && b.SSN__pc) || x.Borrower_SSN__c || null;
    if (!ssn) add('borrower', x, 'Borrower SSN missing (blank on both Person Account and Transaction)');
    else if (digits(ssn).length !== 9) add('borrower', x, 'Borrower SSN malformed (not 9 digits)');
    else if (/^(000|666|9)/.test(digits(ssn))) add('borrower', x, 'Borrower SSN fails SSA issuance rules (invalid area number)');
    if (!b || !b.PersonBirthdate) add('borrower', x, 'Borrower birthdate missing');
    else {
      const age = Math.floor(dayDiff(today, b.PersonBirthdate) / 365.25);
      if (age < 18) add('borrower', x, 'Borrower under 18 by birthdate (age ' + age + ')');
      else if (age > 100) add('borrower', x, 'Borrower birthdate implausible (age ' + age + ')');
    }
  }
  return F;
}

function fetchRows() {
  const f = join(mkdtempSync(join(tmpdir(), 'integ-')), 'q.soql');
  writeFileSync(f, SOQL);
  const out = execFileSync('sf', ['data', 'query', '--file', f, '--json'],
    { encoding: 'utf8', maxBuffer: 1 << 24, shell: true, stdio: ['ignore', 'pipe', 'ignore'] });
  return JSON.parse(out).result.records;
}

function report(rows, meta, F) {
  const total = Object.values(F).reduce((n, v) => n + v.length, 0);
  const affected = new Set();
  for (const k of Object.keys(F)) for (const f of F[k]) affected.add(f.id);

  const L = [];
  L.push('ACTIVE FILE DATA INTEGRITY -- ' + today.toDateString());
  L.push('Scope: status Pre-Processing or later, excluding test records.');
  L.push('Reviewed ' + rows.length + ' of ' + meta.totalActive + ' active files' +
    ' (skipped ' + meta.early.length + ' earlier than Pre-Processing, ' +
    meta.testRows.length + ' test)');
  if (meta.unknown.length) {
    L.push('  NOTE: ' + meta.unknown.length + ' file(s) skipped with unrecognized status: ' +
      [...new Set(meta.unknown.map(u => u.Status__c))].join(', '));
  }
  L.push('Records with at least one issue: ' + affected.size + ' of ' + rows.length + ' | Total issues: ' + total);
  for (const k of Object.keys(F)) L.push('  ' + CATS[k] + ': ' + F[k].length);

  for (const k of Object.keys(F)) {
    L.push('');
    L.push('===== ' + CATS[k] + ' (' + F[k].length + ') =====');
    if (!F[k].length) { L.push('  No issues found.'); continue; }
    const by = {};
    for (const f of F[k]) {
      const key = [f.name, f.id, f.status, f.lo].join('||');
      (by[key] ||= []).push(f.reason);
    }
    for (const key of Object.keys(by)) {
      const p = key.split('||');
      L.push('  ' + p[0] + '  |  ' + p[1] + '  |  ' + p[2] + '  |  LO: ' + p[3]);
      for (const rz of by[key]) L.push('      - ' + rz);
    }
  }
  return L.join('\n');
}

const stampToday = () => {
  const d = new Date();
  const p = n => String(n).padStart(2, '0');
  return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()) +
    ' ' + p(d.getHours()) + ':' + p(d.getMinutes());
};

// --daily: used by the SessionStart hook. Silent on weekends and on the day's
// second-and-later sessions, so logging in ten times a day still reports once.
if (process.argv.includes('--daily')) {
  const day = today.getDay();
  if (day === 0 || day === 6) process.exit(0);
  const key = today.toDateString();
  if (existsSync(STAMP) && readFileSync(STAMP, 'utf8') === key) process.exit(0);
  writeFileSync(STAMP, key);
}

let rows;
try {
  rows = fetchRows();
} catch (e) {
  // A failed scan must never look like a clean scan, in the log or on screen.
  const msg = 'SCAN FAILED -- ' + stampToday() + ' -- Salesforce query did not run. ' +
    'Check `sf org display`; the CLI refresh token may have been revoked.';
  appendFileSync(LOG, '\n\n---\n\n## ' + stampToday() + ' -- SCAN FAILED\n\n```\n' + msg + '\n' +
    String(e.message || e).split('\n')[0] + '\n```\n');
  console.error(msg);
  process.exit(1);
}

const nonTest = rows.filter(x => !isTest(x));
const meta = {
  totalActive: rows.length,
  testRows: rows.filter(isTest),
  unknown: nonTest.filter(x => RANK[x.Status__c] == null),
  early: nonTest.filter(x => RANK[x.Status__c] != null && RANK[x.Status__c] < MIN_RANK),
};
const kept = nonTest.filter(x => RANK[x.Status__c] >= MIN_RANK);
const F = evaluate(kept);

if (process.argv.includes('--json')) {
  console.log(JSON.stringify({
    scanned: kept.length, totalActive: meta.totalActive,
    skippedEarly: meta.early.length, skippedTest: meta.testRows.length,
    skippedUnknownStatus: meta.unknown.length, findings: F,
  }, null, 2));
  process.exit(0);
}

const text = report(kept, meta, F);
const total = Object.values(F).reduce((n, v) => n + v.length, 0);
appendFileSync(LOG, '\n\n---\n\n## ' + stampToday() + ' -- ' + kept.length + ' reviewed, ' +
  total + ' issues (loan ' + F.loan.length + ' / trid ' + F.trid.length +
  ' / mers ' + F.mers.length + ' / borrower ' + F.borrower.length + ')\n\n```\n' + text + '\n```\n');
console.log(text);
