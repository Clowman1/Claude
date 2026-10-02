#!/bin/sh
# Phase 1b validation: dry-run ONLY (no real deploy). Usage: sh run-dryrun.sh <out.json>
T="RecordAccessGuardTest CallInsightListControllerTests AccountRecordHeroControllerTest LeadNotesFormControllerTest TransactionNotesFormControllerTest SubmissionQualityChecklistTests NCS_ChecklistTest BPSVerificationServiceTest DocumentViewerControllerTest LeadReviewQueueTest LoanConditionControllerTest LoanConditionControllerAttachmentTest ConditionReviewServiceTest ConditionReviewQueueControllerTest DocumentControllerReviewDocumentTest ConditionCommentControllerTest LeadDocumentCollectionServiceTest LeadConditionAssignmentTest LeadPortalDocumentRequestFacadeTest LeadPortalPresetConditionTest LeadPortalSubmissionTest ExternalLoPortalCoverageTest BorrowerDocumentPortalControllerTest BorrowerPortalServiceGenericUploadTest"
args=""; for t in $T; do args="$args --tests $t"; done
sf project deploy start -o Production --dry-run -d force-app --test-level RunSpecifiedTests $args --wait 60 --json > "$1" 2>&1
node -e "
const r=JSON.parse(require('fs').readFileSync('$1','utf8').replace(/^[^{]*/,'')); const x=r.result||r; console.log('status',x.status,'success',x.success, r.message||'');
const d=x.details||{}; for(const f of [].concat(d.componentFailures||[])) console.log('COMPILE',f.fullName,f.lineNumber,f.problem);
const t=(d.runTestResult)||{}; console.log('tests',t.numTestsRun,'fail',t.numFailures);
for(const f of [].concat(t.failures||[])) console.log('FAIL',f.name+'.'+f.methodName,':',(f.message||'').slice(0,300),'\n   ',(f.stackTrace||'').replace(/\n/g,' | '));
for(const c of [].concat(t.codeCoverageWarnings||[])) console.log('COV',c.name,c.message);"
