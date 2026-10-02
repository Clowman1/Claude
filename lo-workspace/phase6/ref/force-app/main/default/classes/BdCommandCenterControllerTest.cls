@IsTest
private class BdCommandCenterControllerTest {

    static User makeUser(String alias, String permSet) {
        User me = [SELECT ProfileId, TimeZoneSidKey, LocaleSidKey, EmailEncodingKey, LanguageLocaleKey FROM User WHERE Id = :UserInfo.getUserId()];
        User u = new User(
            FirstName = 'Test', LastName = alias, Alias = alias, Email = alias + '@example.com',
            Username = alias + '.' + Datetime.now().getTime() + '@reach-bd-test.com',
            ProfileId = me.ProfileId, TimeZoneSidKey = me.TimeZoneSidKey, LocaleSidKey = me.LocaleSidKey,
            EmailEncodingKey = me.EmailEncodingKey, LanguageLocaleKey = me.LanguageLocaleKey,
            UserPermissionsMarketingUser = true
        );
        insert u;
        insert new PermissionSetAssignment(
            AssigneeId = u.Id, PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = :permSet].Id
        );
        return u;
    }

    @IsTest
    static void repWorksTheirBook() {
        User rep = makeUser('bdrep', 'Business_Development');
        System.runAs(rep) {
            Id partnerId = BdCommandCenterController.createPartner('Pat', 'Partner', '(813) 555-0142', 'pat.partner@example.com', 'Acme CPAs', 'CPA');

            // Same phone again is blocked, and findDuplicates surfaces the existing person.
            Boolean blocked = false;
            try {
                BdCommandCenterController.createPartner('Pat', 'Again', '813-555-0142', null, null, 'CPA');
            } catch (AuraHandledException e) {
                blocked = true;
            }
            System.assert(blocked, 'duplicate phone must be blocked');
            System.assertEquals(partnerId, BdCommandCenterController.findDuplicates(null, '8135550142')[0].id);
            Test.startTest();

            BdCommandCenterController.Home h = BdCommandCenterController.getHome(null);
            System.assertEquals(1, h.partners.size());
            System.assertEquals('Prospect', h.partners[0].stage);
            System.assertEquals(true, h.canEdit);
            System.assertEquals(false, h.rcConnected, 'a rep with no RingCentral token is prompted to connect');
            System.assertEquals(1, h.stats.byIndustry.get('CPA'));
            Test.stopTest();
        }
    }

    @IsTest
    static void touchesAndStages() {
        User rep = makeUser('bdtch', 'Business_Development');
        System.runAs(rep) {
            Id partnerId = BdCommandCenterController.createPartner('Tia', 'Toucher', '(813) 555-0143', null, null, 'CPA');
            Test.startTest();
            BdCommandCenterController.Home h;
            // Any touch moves Prospect to Contacted; a note alone does not count.
            BdCommandCenterController.logTouch(partnerId, 'Note', 'likes golf');
            System.assertEquals('Prospect', BdCommandCenterController.getHome(null).partners[0].stage);
            BdCommandCenterController.logTouch(partnerId, 'In person', 'met at open house');
            h = BdCommandCenterController.getHome(null);
            System.assertEquals('Contacted', h.partners[0].stage);
            System.assertEquals(false, h.partners[0].needsTouch);

            System.assertEquals(true, BdCommandCenterController.isMyPartner(partnerId));
            BdCommandCenterController.setIndustry(partnerId, 'Insurance Agent');
            BdCommandCenterController.setStage(partnerId, 'Dormant');
            BdCommandCenterController.PartnerDetail d = BdCommandCenterController.getPartner(partnerId, null);
            System.assertEquals('Dormant', d.partner.stage);
            System.assertEquals('Insurance Agent', d.partner.industry);
            System.assertEquals(2, d.timeline.size());
            Test.stopTest();
        }
    }

    @IsTest
    static void callsMatchByPhone() {
        User rep = makeUser('bdcal', 'Business_Development');
        System.runAs(rep) {
            Id partnerId = BdCommandCenterController.createPartner('Cal', 'Caller', '(813) 555-0142', null, null, 'Realtor');
            Test.startTest();
            BdCommandCenterController.Home h;
            // An unassociated RingCentral call to the partner's number is matched by phone.
            Task call = new Task(OwnerId = rep.Id, Subject = 'Call', InteractionType__c = 'Call', CallType = 'Outbound',
                rcsfl__to_number__c = '+18135550142', Status = 'Completed');
            Task stranger = new Task(OwnerId = rep.Id, Subject = 'Call', InteractionType__c = 'Call', CallType = 'Outbound',
                rcsfl__to_number__c = '+14075550000', Status = 'Completed');
            insert new List<Task>{ call, stranger };
            h = BdCommandCenterController.getHome(null);
            System.assertEquals(1, h.calls.size());
            System.assertEquals(1, h.unmatchedCalls.size());
            BdCommandCenterController.linkCall(stranger.Id, partnerId);
            System.assertEquals(partnerId, [SELECT WhatId FROM Task WHERE Id = :stranger.Id].WhatId);
            Test.stopTest();
        }
    }

    @IsTest
    static void existingAccountsAndImport() {
        Account existing = new Account(
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId(),
            FirstName = 'Olive', LastName = 'Owned', PersonEmail = 'olive.owned@example.com', Type__c = 'Borrower Account'
        );
        insert existing;
        User rep = makeUser('bdimp', 'Business_Development');
        System.runAs(rep) {
            System.assert(!BdCommandCenterController.searchAccounts('Olive').isEmpty());
            BdCommandCenterController.addExisting(existing.Id, 'Financial Planner');
            Account a = [SELECT BD_Rep__c, BD_Stage__c, BD_Industry__c, Type__c FROM Account WHERE Id = :existing.Id];
            System.assertEquals(rep.Id, a.BD_Rep__c);
            System.assertEquals('Borrower Account', a.Type__c, 'borrower type is untouched');
            System.assertEquals('Financial Planner', a.BD_Industry__c);

            List<BdCommandCenterController.ImportRow> rows = new List<BdCommandCenterController.ImportRow>();
            rows.add(row(1, 'Olive', 'Owned', null, 'olive.owned@example.com', null));
            rows.add(row(2, 'New', 'Person', '(727) 555-0199', null, 'Title Agent'));
            rows.add(row(3, 'New', 'Person', '727.555.0199', null, null));
            rows.add(row(4, 'No', '', null, null, null));
            List<BdCommandCenterController.ImportRow> preview = BdCommandCenterController.previewImport(rows);
            System.assertEquals('link', preview[0].action);
            System.assertEquals('create', preview[1].action);
            System.assertEquals('skip', preview[2].action);
            System.assertEquals('error', preview[3].action);
            List<BdCommandCenterController.ImportRow> done = BdCommandCenterController.commitImport(rows, 'Realtor');
            System.assertEquals('Created.', done[1].message);
            System.assertEquals('Title Agent Account', [SELECT Type__c FROM Account WHERE Id = :done[1].matchId].Type__c);
        }
    }

    static BdCommandCenterController.ImportRow row(Integer n, String f, String l, String p, String e, String ind) {
        BdCommandCenterController.ImportRow r = new BdCommandCenterController.ImportRow();
        r.rowNumber = n; r.firstName = f; r.lastName = l; r.phone = p; r.email = e; r.industry = ind;
        return r;
    }

    // SeeAllData: a new campaign's default member statuses are invisible otherwise, and the
    // event engine then collides with them (same as RealtorEventRsvpServiceTest).
    @IsTest(SeeAllData=true)
    static void invitesAndMeetingConfirmation() {
        User rep = makeUser('bdinv', 'Business_Development');
        System.runAs(rep) {
            Id partnerId = BdCommandCenterController.createPartner('Ivy', 'Invitee', '(813) 555-0177', 'ivy.invitee@example.com', 'KW', 'Realtor');
            BdCommandCenterController.InviteRequest req = new BdCommandCenterController.InviteRequest();
            req.kind = 'Lunch';
            req.eventDate = Date.today().addDays(3);
            req.eventTime = '12:00';
            req.location = 'Ciccio';
            req.partnerIds = new List<Id>{ partnerId };
            Id campaignId = BdCommandCenterController.createInvite(req);

            Campaign c = [SELECT Name, Type FROM Campaign WHERE Id = :campaignId];
            System.assertEquals('Event', c.Type);
            System.assertEquals('Lunch', BdCommandCenterController.kindOf(c.Name));
            System.assertEquals('lunch', RealtorEventWorkspaceController.artworkTypeFor(c.Name));
            System.assert(RealtorEventWorkspaceController.getInvitationDraft(campaignId).emailBody.contains('Lunch is on us'));

            BdCommandCenterController.Home h = BdCommandCenterController.getHome(null);
            System.assertEquals('Meeting Set', h.partners[0].stage);
            System.assertEquals(1, h.upcoming.size());
            BdCommandCenterController.EventDetail d = BdCommandCenterController.getEvent(campaignId);
            System.assertEquals(1, d.invitees.size());

            BdCommandCenterController.confirmMeeting(campaignId, true);
            System.assertEquals('Met', [SELECT BD_Stage__c FROM Account WHERE Id = :partnerId].BD_Stage__c);
            System.assertEquals('Held', [SELECT BD_Outcome__c FROM Campaign WHERE Id = :campaignId].BD_Outcome__c);
        }
    }

    @IsTest
    static void referralMakesActivePartner() {
        User rep = makeUser('bdref', 'Business_Development');
        System.runAs(rep) {
            Id partnerId = BdCommandCenterController.createPartner('Rae', 'Referrer', '(813) 555-0166', 'rae.referrer@example.com', null, 'CPA');
            Id leadId = BdCommandCenterController.createReferralLead(partnerId, 'Bo', 'Borrower', '(813) 555-0155', null, 'first-time buyer');
            System.assertNotEquals(null, leadId);
            BdCommandCenterController.Home h = BdCommandCenterController.getHome(null);
            System.assertEquals('Active Partner', h.partners[0].stage);
            System.assertEquals(1, h.stats.referredLeads90);
            System.assertEquals(1, BdCommandCenterController.getPartner(partnerId, null).referredLeads.size());
        }
    }

    @IsTest
    static void managerSeesRepReadOnly() {
        User rep = makeUser('bdrp2', 'Business_Development');
        User mgr = makeUser('bdmgr', 'BD_Manager');
        System.runAs(rep) {
            BdCommandCenterController.createPartner('Max', 'Mgrview', '(813) 555-0133', null, null, 'Builder');
        }
        System.runAs(mgr) {
            BdCommandCenterController.Home h = BdCommandCenterController.getHome(rep.Id);
            System.assertEquals(false, h.canEdit);
            System.assertEquals(true, h.isManager);
            System.assertEquals(1, h.partners.size());
            Boolean refused = false;
            try {
                BdCommandCenterController.logTouch(h.partners[0].id, 'Call', 'x');
            } catch (AuraHandledException e) {
                refused = true;
            }
            System.assert(refused, 'managers are read-only');
        }
    }

    @IsTest
    static void phoneDigits() {
        System.assertEquals('8135550142', BdCommandCenterController.digits('+1 (813) 555-0142'));
        System.assertEquals(null, BdCommandCenterController.digits('555-0142'));
    }
}