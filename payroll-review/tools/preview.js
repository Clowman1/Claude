// Renders what each person's Payroll Review modal will show, from a parse-payroll.js payload.
// Usage: node preview.js <payload.json> <out.html>   (out goes in payroll-review/preview/, which is gitignored)
const fs = require('fs');
const [, , inFile, outFile] = process.argv;
const p = JSON.parse(fs.readFileSync(inFile, 'utf8'));

const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
const money = (n) => (n == null ? '' : n.toLocaleString('en-US', { style: 'currency', currency: 'USD' }));
const whole = (n) => (n == null ? '' : n.toLocaleString('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 }));
const longDate = (iso) => new Date(iso + 'T12:00:00').toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' });

function card(person, i) {
    const groups = [];
    for (const l of person.lines) {
        let g = groups.find((x) => x.name === l.section);
        if (!g) groups.push((g = { name: l.section, rows: [], sum: 0 }));
        g.rows.push(l);
        g.sum += l.commission || 0;
    }
    const sections = groups
        .map(
            (g) => `${g.name ? `<h3>${esc(g.name)}</h3>` : ''}
        <div class="scroll"><table>
          <thead><tr><th>Loan</th><th class="num">Loan Amount</th><th>Biz Dev</th><th class="num">Rate Applied</th><th class="num">Commission</th></tr></thead>
          <tbody>${g.rows
              .map((r) => `<tr><td>${esc(r.loan)}</td><td class="num">${whole(r.loanAmount)}</td><td>${esc(r.bizDev)}</td><td class="num">${esc(r.rate)}</td><td class="num">${money(r.commission)}</td></tr>`)
              .join('')}</tbody>
          ${groups.length > 1 ? `<tfoot><tr><td colspan="4">${esc(g.name)} subtotal</td><td class="num">${money(g.sum)}</td></tr></tfoot>` : ''}
        </table></div>`
        )
        .join('');
    return `<section class="modal" id="p${i}" ${i ? 'hidden' : ''} aria-label="${esc(person.name)}">
      <header class="mh">Payroll Review</header>
      <div class="mb">
        <p class="meta"><strong>${esc(p.period)} Payroll</strong><span>Pay Date ${longDate(p.payDate)}</span><span>Feedback by ${longDate(p.feedbackCloses)}</span><span>Review closes ${longDate(p.reviewCloses)}</span></p>
        ${sections}
        <div class="total"><span>Total</span><strong>${money(person.total)}</strong></div>
        <div class="actions"><button class="btn" type="button">Report an issue</button><button class="btn btn-primary" type="button">Looks good</button></div>
      </div>
    </section>`;
}

const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Payroll Review Preview</title>
<style>
:root{--ink:#1f2a37;--navy:#0b2545;--muted:#4b5563;--line:#e5e7eb;--head:#f9fafb;--bg:#eef1f5;--card:#fff}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--ink:#e5e7eb;--navy:#9cc3ff;--muted:#9ca3af;--line:#2d3748;--head:#1a2230;--bg:#0f141c;--card:#161d28}}
:root[data-theme="dark"]{--ink:#e5e7eb;--navy:#9cc3ff;--muted:#9ca3af;--line:#2d3748;--head:#1a2230;--bg:#0f141c;--card:#161d28}
*{box-sizing:border-box}body{margin:0;padding:24px 16px;background:var(--bg);color:var(--ink);font:14px/1.45 system-ui,-apple-system,"Segoe UI",sans-serif}
.wrap{max-width:860px;margin:0 auto}
h1{font-size:18px;margin:0 0 4px;color:var(--navy)}.sub{margin:0 0 16px;color:var(--muted)}
.picker{display:flex;flex-wrap:wrap;gap:6px;margin-bottom:16px}
.picker button{padding:6px 12px;border:1px solid var(--line);border-radius:999px;background:var(--card);color:var(--ink);font:inherit;cursor:pointer}
.picker button[aria-pressed="true"]{background:var(--navy);border-color:var(--navy);color:var(--card)}
.modal{background:var(--card);border-radius:8px;box-shadow:0 10px 30px -10px rgba(0,0,0,.35);overflow:hidden}
.mh{padding:14px 20px;border-bottom:1px solid var(--line);font-size:18px;font-weight:700;text-align:center;color:var(--navy)}
.mb{padding:16px 20px 20px}
.meta{display:flex;flex-wrap:wrap;gap:4px 16px;margin:0 0 12px;color:var(--muted)}.meta strong{color:var(--navy)}
h3{margin:12px 0 4px;font-size:13px;font-weight:700;text-transform:uppercase;letter-spacing:.03em;color:var(--navy)}
.scroll{overflow-x:auto}table{width:100%;border-collapse:collapse}
th,td{padding:6px 8px;border-bottom:1px solid var(--line);text-align:left;white-space:nowrap}
th{font-size:12px;font-weight:600;color:var(--muted);background:var(--head)}
.num{text-align:right;font-variant-numeric:tabular-nums}tfoot td{font-weight:600}
.total{display:flex;justify-content:space-between;align-items:baseline;margin-top:12px;padding:10px 8px;border-top:2px solid var(--navy);font-size:16px}
.total strong{font-size:20px;color:var(--navy);font-variant-numeric:tabular-nums}
.actions{display:flex;justify-content:flex-end;gap:8px;margin-top:12px}
.btn{padding:8px 16px;border:1px solid var(--line);border-radius:4px;background:var(--card);color:var(--navy);font:inherit;font-weight:600}
.btn-primary{background:var(--navy);border-color:var(--navy);color:var(--card)}
</style></head><body><div class="wrap">
<h1>Payroll Review preview: ${esc(p.period)}</h1>
<p class="sub">What each person would have seen. Pick a name.</p>
<div class="picker" role="group" aria-label="Employee">${p.people
    .map((x, i) => `<button type="button" data-i="${i}" aria-pressed="${i === 0}">${esc(x.name)}</button>`)
    .join('')}</div>
${p.people.map(card).join('\n')}
</div>
<script>
document.querySelector('.picker').addEventListener('click',e=>{const b=e.target.closest('button');if(!b)return;
document.querySelectorAll('.picker button').forEach(x=>x.setAttribute('aria-pressed',x===b));
document.querySelectorAll('.modal').forEach((m,i)=>m.hidden=String(i)!==b.dataset.i);});
</script></body></html>`;
fs.writeFileSync(outFile, html);
console.log('wrote', outFile);
