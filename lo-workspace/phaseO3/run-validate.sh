#!/bin/sh
# Check-only validation (phaseO3). Deploy = sf project deploy quick --job-id <id> -o Production
cd "$(dirname "$0")"
sf project deploy validate -o Production -d force-app -l RunSpecifiedTests \
  -t LoWsTextsServiceTest -t ExternalLoStampServiceTest -t LoWsCommunicationsServiceTest -t PerfectDayHomeServiceTest \
  --wait 60 --json 2>/dev/null > validate.json
node -e "const r=require('./validate.json').result||{};const d=r.details||{};const t=(d.runTestResult||{});console.log(r.id,r.status);[].concat((d.runTestResult||{}).codeCoverage||[]).forEach(c=>console.log('COVER',c.name,c.numLocations,c.numLocationsNotCovered));console.log(r.id,r.status,'tests',t.numTestsRun,'fail',t.numFailures);[].concat(d.componentFailures||[]).forEach(f=>console.log('COMP',f.fullName,f.problem));[].concat(t.failures||[]).forEach(f=>console.log('TEST',f.name+'.'+f.methodName,f.message));[].concat(t.codeCoverageWarnings||[]).forEach(w=>console.log('COV',w.name,w.message))"
