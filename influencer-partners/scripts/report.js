// Summarise an `sf project deploy ... --json` output file: status, component errors, test failures, coverage.
const raw = require('fs').readFileSync(process.argv[2], 'utf8');
const j = JSON.parse(raw.slice(raw.indexOf('{')));
const r = j.result || j.data || j;
console.log(r.status, r.success === undefined ? '' : 'success=' + r.success, j.message ? '\n' + j.message : '');
const d = r.details || {};
for (const f of [].concat(d.componentFailures || [])) console.log('C', f.fullName, f.problem);
const t = d.runTestResult || {};
console.log('tests', t.numTestsRun, 'failures', t.numFailures);
for (const f of [].concat(t.failures || [])) console.log('T', f.name, f.methodName, f.message, (f.stackTrace || '').slice(0, 400));
for (const c of [].concat(t.codeCoverageWarnings || [])) console.log('W', c.name, c.message);
for (const c of [].concat(t.codeCoverage || [])) {
    const total = c.numLocations, miss = c.numLocationsNotCovered;
    if (total) console.log('cov', c.name, Math.round(((total - miss) / total) * 100) + '%');
}
