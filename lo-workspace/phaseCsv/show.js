const r=require(process.argv[2]).result||{};const d=r.details||{};
console.log('status',r.status,'success',r.success,'id',r.id,'tests',r.numberTestsCompleted,'/',r.numberTestsTotal,'errors',r.numberTestErrors);
[].concat(d.componentFailures||[]).forEach(f=>console.log('COMP',f.fullName,f.lineNumber,f.problem));
[].concat((d.runTestResult||{}).failures||[]).forEach(f=>console.log('FAIL',f.name,f.methodName,f.message,(f.stackTrace||'').slice(0,200)));
[].concat((d.runTestResult||{}).codeCoverageWarnings||[]).forEach(w=>console.log('COV',w.name,w.message));
