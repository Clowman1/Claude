#!/bin/sh
# Check-only validation of Phase 8. Usage: sh run-validate.sh
cd "$(dirname "$0")"
sf project deploy validate -o Production -d force-app --test-level RunSpecifiedTests \
  --tests LoWsOversightControllerTest --tests ExternalLoPortalServiceTest --tests ExternalLoPortalCoverageTest \
  --wait 60 --json 2>/dev/null > validate.json
node -e "const r=require('./validate.json');const x=r.result||{};console.log(r.status,x.status,x.id,'comp',x.numberComponentsDeployed+'/'+x.numberComponentsTotal,'tests',x.numberTestsCompleted+'/'+x.numberTestsTotal,'err',x.numberTestErrors);const d=x.details||{};console.log(JSON.stringify([].concat(d.componentFailures||[]).map(f=>f.fullName+': '+f.problem),null,1));const t=d.runTestResult||{};console.log(JSON.stringify([].concat(t.failures||[]).map(f=>f.name+'.'+f.methodName+': '+f.message+' '+f.stackTrace),null,1));console.log(JSON.stringify([].concat(t.codeCoverageWarnings||[]).map(w=>w.name+': '+w.message)));(t.codeCoverage?[].concat(t.codeCoverage):[]).filter(c=>/LoWsOversight|ExternalLoPortalService/.test(c.name)).forEach(c=>console.log(c.name,c.numLocations-c.numLocationsNotCovered,'/',c.numLocations));if(!x.status)console.log(r.message)"
