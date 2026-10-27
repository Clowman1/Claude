// Builds seed-templates.apex from the onboarding CSV (53 tasks). Run: node scripts/seed-templates.mjs, then
// sf apex run -f scripts/seed-templates.apex -o Production. Refuses to run twice (checks for existing Onboarding templates).
import fs from 'node:fs';

const CSV = new URL('../../Onboarding Checklist - Salesforce Import.csv', import.meta.url);
const USERS = { Bianca: '0055x00000Bf9iaAAB', Chris: '005f2000009OtLnAAK' };

function parse(text) {
    const rows = [];
    for (const line of text.split(/\r?\n/).filter(Boolean)) {
        const cells = [];
        let cur = '', q = false;
        for (const ch of line) {
            if (ch === '"') q = !q;
            else if (ch === ',' && !q) { cells.push(cur); cur = ''; }
            else cur += ch;
        }
        cells.push(cur);
        rows.push(cells);
    }
    return rows;
}

const APPLIES = {
    'All': {},
    'Loan Officers / Branch Managers': { roles: 'Loan Officer;Branch Manager' },
    'Loan Officers (if applicable)': { roles: 'Loan Officer', optional: true },
    'Loan Officers': { roles: 'Loan Officer' },
    'Loan Officers / Processors': { roles: 'Loan Officer;Processor' },
    'Loan Officers / Processors / Closers': { roles: 'Loan Officer;Processor;Closer' },
    'Processors': { roles: 'Processor' },
    'Remote / Hybrid': { arr: 'Remote;Hybrid' },
    'In-Office': { arr: 'In-Office' }
};
const PHASE = { 'Pre-Start': 'Pre-Start', 'Day 1': 'Day 1', 'Week 1': 'Week 1', '30 Days': '30 Days', '90 Days': '90 Days' };
// Bianca's docx templates (Salesforce send in phase 2) vs. the ones she sends through DocuSign (decision 39).
const EMAIL = { 3: 'PH-3', 4: 'PH-4', 9: 'PH-7', 12: 'PH-8' };
// Rows 13 (Licensing Store) and 16 (KB Technologies) became web forms on 2026-10-27; their links are in the description.
const DOCUSIGN = { 11: 'PH-6', 14: 'PH-10', 30: 'Day 1 Instructions', 32: 'Team Announcement' };
const SEND_TO = { 14: 'cmorgan1@uwm.com' };
const EXAM = {
    Regulatory: [12, 13, 31, 40, 47],
    Documentation: [3, 4, 5, 6, 11, 34, 35, 36, 46],
    Systems: [16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 38]
};

const s = (v) => v == null || v === '' ? 'null' : `'${String(v).replace(/\\/g, '\\\\').replace(/'/g, "\\'")}'`;
const [, ...rows] = parse(fs.readFileSync(CSV, 'utf8'));
const lines = rows.map(([order, phase, subject, desc, who, offset, applies]) => {
    const n = Number(order);
    const a = APPLIES[applies];
    if (!a) throw new Error(`Unknown Applies To "${applies}" on row ${n}`);
    if (!PHASE[phase]) throw new Error(`Unknown phase "${phase}" on row ${n}`);
    const assignee = /^Chris/.test(who) ? USERS.Chris : USERS.Bianca;
    const led = who === 'Angelina' ? 'Angelina' : /Manager/.test(who) ? 'Manager' : n === 42 ? 'Chris + Brandon Dobos' : n === 2 ? 'Adam' : null;
    const exam = Object.keys(EXAM).find((k) => EXAM[k].includes(n));
    return `new People_Template_Task__c(Name = ${s(subject.slice(0, 80))}, Checklist_Type__c = 'Onboarding', Sort_Order__c = ${n * 10}, ` +
        `Phase__c = ${s(PHASE[phase])}, Description__c = ${s(desc)}, Default_Assignee__c = '${assignee}', Led_By__c = ${s(led)}, ` +
        `Offset_Days__c = ${Number(offset)}, Roles__c = ${s(a.roles)}, Work_Arrangements__c = ${s(a.arr)}, Optional__c = ${!!a.optional}, ` +
        `Email_Template__c = ${s(EMAIL[n] || DOCUSIGN[n])}, Via_DocuSign__c = ${!!DOCUSIGN[n]}, Send_To__c = ${s(SEND_TO[n])}, ` +
        `Exam_Section__c = ${s(exam)}, Sets_Status__c = ${n === 4 ? "'Pre-Start'" : 'null'}, Active__c = true, ` +
        // 30/90-day items count calendar days and email reminders; the Salesforce user task completes when the user is linked.
        `Offset_Unit__c = '${n >= 50 ? 'Calendar Days' : 'Business Days'}', Remind__c = ${n >= 50}, ` +
        `Auto_Complete__c = ${n === 25 ? "'Salesforce user linked'" : 'null'})`;
});

fs.writeFileSync(new URL('./seed-templates.apex', import.meta.url),
    `if ([SELECT COUNT() FROM People_Template_Task__c WHERE Checklist_Type__c = 'Onboarding'] > 0) { throw new HandledException('Onboarding templates already loaded'); }\n` +
    `insert new List<People_Template_Task__c>{\n    ${lines.join(',\n    ')}\n};\n` +
    `System.debug('SEEDED ' + [SELECT COUNT() FROM People_Template_Task__c]);\n`);
console.log('rows', lines.length);
