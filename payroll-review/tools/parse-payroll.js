// Parses an expanded payroll workbook (see LOADING.md) into the PayrollReviewController.load payload
// and prints the pre-publish checks. Usage: node parse-payroll.js <expanded-xlsx-dir> [out.json]
// Main tab = what was paid; LOA rows come from the Raw Data tab (Loan Partner = person, 4 BPS).
const fs = require('fs');
const path = require('path');

// Who gets a review. Names must match the Salesforce User.Name exactly.
const LOS = ['Harold Ellis', 'Joe Olmsted', 'Zachary Fritz', 'Martin Rebagliati', 'Manuel Anagnostou', 'Joseph Carey', 'Megan Straight'];
const LOAS = ['Megan Straight', "Joey D'Alessandro"];
const BONUS = ['Byron Richie'];
const LOA_BPS = 4;

const dir = process.argv[2];
const out = process.argv[3];
const read = (f) => fs.readFileSync(path.join(dir, 'xl', f), 'utf8');
const unxml = (s) =>
    s.replace(/<[^>]+>/g, '').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'");

const shared = fs.existsSync(path.join(dir, 'xl', 'sharedStrings.xml'))
    ? [...read('sharedStrings.xml').matchAll(/<si>([\s\S]*?)<\/si>/g)].map((m) => unxml(m[1]))
    : [];

function sheet(n) {
    const rows = [];
    for (const r of read(`worksheets/sheet${n}.xml`).matchAll(/<row [^>]*>([\s\S]*?)<\/row>/g)) {
        const row = {};
        for (const c of r[1].matchAll(/<c r="([A-Z]+)\d+"([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g)) {
            const [, col, attrs, body = ''] = c;
            const t = (attrs.match(/t="(\w+)"/) || [])[1];
            const v = (body.match(/<v>([\s\S]*?)<\/v>/) || [])[1];
            let val;
            if (t === 's') val = shared[+v];
            else if (t === 'inlineStr') val = unxml(body);
            else if (t === 'str') val = v == null ? '' : unxml(v);
            else val = v == null ? '' : +v;
            if (val !== '') row[col] = typeof val === 'string' ? val.trim() : val;
        }
        rows.push(row);
    }
    return rows;
}

const norm = (s) => String(s || '').replace(/[–—]/g, '-').replace(/\s+/g, ' ').trim();
const cents = (n) => Math.round(n * 100) / 100;
const main = sheet(1);
const raw = sheet(2);

// Header lines
const title = norm(main[0].A); // "Reach Home Loans - September 2026 Payroll Calculations"
const period = (title.match(/([A-Z][a-z]+ \d{4}) Payroll/) || [])[1];
const payDateText = (norm(main[1].A).match(/Pay Date: ([A-Za-z]+ \d+, \d{4})/) || [])[1];
const pd = new Date(payDateText);
const iso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const payDate = iso(pd);
const feedbackCloses = iso(new Date(pd.getFullYear(), pd.getMonth(), 8));
const reviewCloses = iso(new Date(pd.getFullYear(), pd.getMonth(), 11));
const units = +((norm(main[1].A).match(/(\d+) Funded Files/) || [])[1] || 0);

// Main tab person blocks: "NAME - Role" header, then Loan rows, then "<Name> Total".
const blocks = {};
let cur = null;
let section = '';
for (const r of main) {
    const a = norm(r.A);
    const header = a.match(/^([A-Z][A-Z' .]+?) - (.+)$/);
    if (header && header[1] === header[1].toUpperCase()) {
        const name = [...LOS, ...LOAS, ...BONUS].find((n) => n.toUpperCase() === header[1]);
        cur = { name: name || header[1], lines: [], total: null, loaSubtotal: null };
        blocks[cur.name] = cur;
        section = '';
        continue;
    }
    if (!cur) continue;
    if (/^- As Loan Officer -$/.test(a)) section = 'As Loan Officer';
    else if (/^- As LOA/.test(a)) section = 'As LOA';
    else if (/^LOA Subtotal$/.test(a)) cur.loaSubtotal = r.H;
    else if (new RegExp(`^${cur.name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')} Total`, 'i').test(a)) {
        cur.total = r.H;
        cur = null;
    } else if (typeof r.B === 'number' && typeof r.H === 'number' && a && a !== 'Loan') {
        cur.lines.push({ section, loan: a, loanAmount: r.B, bizDev: norm(r.C), rate: norm(r.G), commission: r.H });
    }
}

// Raw Data tab: header row gives the columns.
const head = raw[0];
const col = (label) => Object.keys(head).find((k) => norm(head[k]).toLowerCase() === label.toLowerCase());
const C = { name: col('Transaction Name'), amt: col('Total Loan Amount'), lp: col('Loan Partner'), biz: col('Biz Dev') };
const rawLoans = raw
    .slice(1)
    .filter((r) => r[C.name] && !/^TOTALS/i.test(r[C.name]))
    .map((r) => ({ loan: norm(r[C.name]).split(' - ')[0], amount: +r[C.amt], lp: norm(r[C.lp]), bizDev: norm(r[C.biz]) }));

const people = [];
const checks = [];
for (const name of [...new Set([...LOS, ...LOAS, ...BONUS])]) {
    const b = blocks[name];
    if (BONUS.includes(name)) {
        const row = main.find((r) => norm(r.A) === name);
        if (!row) {
            checks.push(`MISSING: ${name} not found on the main tab`);
            continue;
        }
        const volume = rawLoans.reduce((s, l) => s + l.amount, 0);
        people.push({
            name,
            total: row.H,
            lines: [{ section: '', loan: `Company-funded volume (${units} units)`, loanAmount: volume, bizDev: '', rate: norm(row.G), commission: row.H }]
        });
        continue;
    }
    if (!b) {
        checks.push(`MISSING: no block for ${name} on the main tab`);
        continue;
    }
    // An LOA-only person's main-tab rows are all LOA rows; those come from Raw Data instead.
    let lines = LOS.includes(name) ? b.lines.filter((l) => l.section !== 'As LOA') : [];
    if (LOAS.includes(name)) {
        const loa = rawLoans
            .filter((l) => l.lp === name)
            .map((l) => ({ section: 'As LOA', loan: l.loan, loanAmount: l.amount, bizDev: l.bizDev, rate: `${LOA_BPS} BPS`, commission: cents((l.amount * LOA_BPS) / 10000) }));
        const loaSum = cents(loa.reduce((s, l) => s + l.commission, 0));
        const mainLoa = b.loaSubtotal ?? (lines.length ? null : b.total);
        if (mainLoa != null && Math.abs(loaSum - mainLoa) > 0.05) {
            checks.push(`LOA MISMATCH: ${name} Raw Data LOA rows = $${loaSum.toFixed(2)} vs main tab LOA = $${(+mainLoa).toFixed(2)}`);
        }
        if (lines.length) lines = lines.map((l) => ({ ...l, section: 'As Loan Officer' }));
        else lines = [];
        lines = [...lines, ...loa];
    } else {
        lines = lines.map((l) => ({ ...l, section: '' }));
    }
    const sum = cents(lines.reduce((s, l) => s + l.commission, 0));
    if (b.total == null) checks.push(`MISSING: no total row for ${name}`);
    else if (Math.abs(sum - b.total) > 0.05) checks.push(`TOTAL ≠ ROWS: ${name} rows = $${sum.toFixed(2)}, paid total shown = $${b.total.toFixed(2)}`);
    people.push({ name, total: b.total, lines });
}

const payload = { period, payDate, feedbackCloses, reviewCloses, people };
console.log(`${period} · pay date ${payDate} · feedback closes ${feedbackCloses} · review closes ${reviewCloses}`);
for (const p of people) console.log(`  ${p.name.padEnd(20)} ${String(p.lines.length).padStart(3)} rows   total $${p.total.toFixed(2)}`);
console.log(checks.length ? `\nCHECKS:\n  ${checks.join('\n  ')}` : '\nCHECKS: none');
if (out) fs.writeFileSync(out, JSON.stringify(payload, null, 2));

// Anonymous Apex that loads it: sf apex run -o Production -f <out>.apex
if (out) {
    const q = (s) => `'${String(s).replace(/\\/g, '\\\\').replace(/'/g, "\\'")}'`;
    const d = (s) => `Date.valueOf(${q(s)})`;
    fs.writeFileSync(
        out.replace(/\.json$/, '') + '.apex',
        `System.debug(PayrollReviewController.load(${q(period)}, ${d(payDate)}, ${d(feedbackCloses)}, ${d(reviewCloses)}, ${q(JSON.stringify(people))}).size() + ' reviews loaded');\n`
    );
}
