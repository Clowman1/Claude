// Builds load-staff.apex from proposed-staff.csv (rows with Include = Y), after Chris has reviewed it (decision 19).
// Run: node load-staff.mjs, then sf apex run -f load-staff.apex -o Production.
// Creates Active People employees linked to their Salesforce user (no onboarding checklist), skipping any user already
// linked, then opens the 2026 renewals (decision 37).
import fs from 'node:fs';

const csv = fs.readFileSync(new URL('./proposed-staff.csv', import.meta.url), 'utf8');
const parse = (line) => {
    const out = [];
    let cur = '', q = false;
    for (let i = 0; i < line.length; i++) {
        const ch = line[i];
        if (ch === '"' && line[i + 1] === '"' && q) { cur += '"'; i++; }
        else if (ch === '"') q = !q;
        else if (ch === ',' && !q) { out.push(cur); cur = ''; }
        else cur += ch;
    }
    out.push(cur);
    return out;
};
const [head, ...lines] = csv.split(/\r?\n/).filter(Boolean);
const cols = parse(head);
const s = (v) => (v == null || v === '' ? 'null' : `'${String(v).replace(/\\/g, '\\\\').replace(/'/g, "\\'")}'`);
const d = (v) => {
    if (!v) return 'null';
    const m = v.match(/^(\d{4})-(\d{2})-(\d{2})$/) || v.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
    if (!m) throw new Error('Bad date ' + v + ' (use YYYY-MM-DD or M/D/YYYY)');
    return v.includes('-') ? `Date.newInstance(${+m[1]}, ${+m[2]}, ${+m[3]})` : `Date.newInstance(${+m[3]}, ${+m[1]}, ${+m[2]})`;
};
const rows = lines.map(parse).map((r) => Object.fromEntries(cols.map((c, i) => [c, r[i]]))).filter((r) => /^y/i.test(r.Include));
const items = rows.map((r) => {
    const [first, ...rest] = r.Name.trim().split(/\s+/);
    return `new People_Employee__c(Name = ${s(r.Name.trim())}, First_Name__c = ${s(first)}, Last_Name__c = ${s(rest.join(' '))}, ` +
        `Role__c = ${s(r.Role)}, Work_Arrangement__c = ${s(r['Work Arrangement'])}, Status__c = 'Active', Start_Date__c = ${d(r['Start Date'])}, ` +
        `Work_Email__c = ${s(r['Work Email'])}, NMLS_ID__c = ${s(r['NMLS ID'])}, Licensed_States__c = ${s(r['Licensed States'])}, User__c = ${s(r['Salesforce User Id'])})`;
});
fs.writeFileSync(new URL('./load-staff.apex', import.meta.url),
    `Set<Id> linked = new Set<Id>();\nfor (People_Employee__c e : [SELECT User__c FROM People_Employee__c WHERE User__c != null]) linked.add(e.User__c);\n` +
    `List<People_Employee__c> rows = new List<People_Employee__c>{\n    ${items.join(',\n    ')}\n};\n` +
    `List<People_Employee__c> fresh = new List<People_Employee__c>();\nfor (People_Employee__c e : rows) if (!linked.contains(e.User__c)) fresh.add(e);\n` +
    `insert fresh;\nSystem.debug('STAFF loaded ' + fresh.size() + ' of ' + rows.size() + '; renewals opened ' + PeopleController.generateRenewals(2026));\n`);
console.log('rows', items.length);
