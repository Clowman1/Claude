# O4g (2026-10-09) - check-only validated, NOT deployed

Validation: 0AfQi000001UQcPKAW (30 tests, 0 failures). Deploy: `sf project deploy quick --job-id 0AfQi000001UQcPKAW -o Production`
Built from org copies retrieved into ref/ on 2026-10-09. Test classes only; no production code changed.

Root cause (both classes): tests ran as the CLI user (Chris), who holds LO_Workspace_Demo, so
LoWsPartnerTagService.isTagMode() = true and the portal tests took the LO Workspace path
(first+last name required on Add lead; tag-based realtor visibility). CoverageTest also hit MIXED_DML:
AesKey__c insert, then PermissionSetAssignment insert (Chris lacks Lead_Access/All_Leads, so grantPortalAccess inserted).

1. ExternalLoPortalTestHelper: createPortalAdmin(alias) / portalAdmin(alias) - fresh user on the running admin's profile
   + portal permsets + ConditionPermissions (admin profile has no Condition__c.Type__c read; the loan-detail
   snapshot reads it WITH USER_MODE and fails with "Variable does not exist: tmpVar1" without it).
2. ExternalLoPortalServiceTest / ExternalLoPortalCoverageTest: run as portalAdmin; CoverageTest's AesKey__c insert moved inside runAs.

TaskRepository coverage with these two tests: 75.3% (97 lines, 24 uncovered) - check-only 0AfQi000001UQe1KAG (not for deploy).
Open: hellis@ (Harold, RHL Community User) has no Condition__c read at all -> getLoanDetail's USER_MODE condition query would throw for him (pre-existing).
