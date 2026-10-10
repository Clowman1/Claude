@IsTest
private class LoRecruitingControllerTest {
    static final Id RT_ID = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName()
        .get('Loan_Officer_Lead_Record_Type').getRecordTypeId();

    static void grantAccess() {
        Id psId = [SELECT Id FROM PermissionSet WHERE Name = 'LO_Recruiting'].Id;
        if ([SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSetId = :psId] == 0) {
            insert new PermissionSetAssignment(AssigneeId = UserInfo.getUserId(), PermissionSetId = psId);
        }
    }

    static Lead recruit(String last) {
        Lead l = new Lead(
            RecordTypeId = RT_ID, FirstName = 'Test', LastName = last, Company = 'Rival Mortgage', Status = 'New',
            NMLS__c = '123456', MobilePhone = '407-555-0101', Email = last.toLowerCase() + '@rival.test',
            Recruit_Stage__c = 'New', Loan_Volume__c = 25000000, Volume_Period__c = '12mo', Recruit_List__c = 'Test'
        );
        insert l;
        return l;
    }

    @IsTest
    static void homeTouchAndStages() {
        System.runAs(new User(Id = UserInfo.getUserId())) { grantAccess(); }
        Lead l = recruit('Alpha');

        LoRecruitingController.Home h = LoRecruitingController.getHome();
        Boolean found = false;
        for (LoRecruitingController.Recruit r : h.recruits) if (r.id == l.Id) found = true;
        System.assert(found, 'recruit listed');
        System.assertNotEquals(null, LoRecruitingController.getWeekStats(null));
        System.assertNotEquals(null, LoRecruitingController.getWeekStats(UserInfo.getUserId()));

        System.assertEquals(Date.today().addDays(3), LoRecruitingController.suggestNextTouch(l.Id, false));
        LoRecruitingController.logTouch(l.Id, 'Call', 'Left a voicemail', false, Date.today().addDays(3));
        System.assertEquals('Contacted', [SELECT Recruit_Stage__c FROM Lead WHERE Id = :l.Id].Recruit_Stage__c);
        System.assertEquals(Date.today().addDays(7), LoRecruitingController.suggestNextTouch(l.Id, false));

        LoRecruitingController.logTouch(l.Id, 'Note', 'Just a note', true, null);
        System.assertEquals('Contacted', [SELECT Recruit_Stage__c FROM Lead WHERE Id = :l.Id].Recruit_Stage__c, 'notes never move the stage');

        LoRecruitingController.logTouch(l.Id, 'Call', 'Good talk', true, Date.today().addDays(3));
        System.assertEquals('Conversation', [SELECT Recruit_Stage__c FROM Lead WHERE Id = :l.Id].Recruit_Stage__c);

        LoRecruitingController.setStage(l.Id, 'Not Now');
        System.assertEquals(Date.today().addDays(90), [SELECT Next_Touch_Date__c FROM Lead WHERE Id = :l.Id].Next_Touch_Date__c);
        LoRecruitingController.setStage(l.Id, 'Not Interested');
        Lead out = [SELECT DoNotCall, HasOptedOutOfEmail FROM Lead WHERE Id = :l.Id];
        System.assert(out.DoNotCall && out.HasOptedOutOfEmail, 'Not Interested opts out');

        LoRecruitingController.setNextTouch(l.Id, Date.today());
        LoRecruitingController.setRecruiter(l.Id, UserInfo.getUserId());

        LoRecruitingController.addNote(l.Id, 'Comp plan sent\nFollow up Friday');

        LoRecruitingController.Detail d = LoRecruitingController.getRecruit(l.Id);
        System.assert(d.timeline.size() >= 2, 'call touches on the timeline');
        // 'Left a voicemail', 'Just a note', 'Good talk' (touch notes) + the typed note
        System.assert(d.notes.size() >= 4, 'every typed note lands in Recruiting Notes');
        Boolean typed = false;
        for (LoRecruitingController.NoteRow n : d.notes) if (n.body == 'Comp plan sent\nFollow up Friday') typed = true;
        System.assert(typed, 'note body round-trips as plain text');
    }

    // SeeAllData: the invite engine creates Campaign member statuses, which collide with invisible defaults otherwise.
    @IsTest(SeeAllData=true)
    static void inPersonInviteToRecruit() {
        System.runAs(new User(Id = UserInfo.getUserId())) { grantAccess(); }
        Lead l = recruit('Charlie');

        BdCommandCenterController.InviteRequest req = new BdCommandCenterController.InviteRequest();
        req.kind = 'Coffee';
        req.eventDate = Date.today().addDays(3);
        req.eventTime = '08:30';
        req.minutes = 60;
        req.location = 'Starbucks';
        req.partnerIds = new List<Id>{ l.Id };
        req.scope = 'recruit';
        Id campaignId = BdCommandCenterController.createInvite(req);

        CampaignMember m = [SELECT LeadId, ContactId, Status FROM CampaignMember WHERE CampaignId = :campaignId];
        System.assertEquals(l.Id, m.LeadId, 'the recruit Lead is the invitee');
        System.assertEquals('Invitation Queued', m.Status);

        LoRecruitingController.Detail d = LoRecruitingController.getRecruit(l.Id);
        System.assertEquals('Meeting Set', d.recruit.stage, 'an upcoming invite moves the recruit to Meeting Set');
        Boolean onTimeline = false;
        for (LoRecruitingController.TimelineItem t : d.timeline) if (t.title.startsWith('In person: ')) onTimeline = true;
        System.assert(onTimeline, 'invite on the timeline');

        req.partnerIds = new List<Id>{ [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1].Id };
        try {
            BdCommandCenterController.createInvite(req);
            System.assert(false, 'recruit scope only invites recruit leads');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void plainTextStripsNoteHtml() {
        System.assertEquals('a & b\nc', LoRecruitingController.plainText('<p>a &amp; b<br>c</p>'));
    }

    @IsTest
    static void autoAdvanceAndHire() {
        System.runAs(new User(Id = UserInfo.getUserId())) { grantAccess(); }
        Lead l = recruit('Bravo');
        insert new Event(WhoId = l.Id, Subject = 'Coffee', StartDateTime = Datetime.now().addDays(2), DurationInMinutes = 30);
        LoRecruitingController.getHome();
        System.assertEquals('Meeting Set', [SELECT Recruit_Stage__c FROM Lead WHERE Id = :l.Id].Recruit_Stage__c);

        Id accountId = LoRecruitingController.markHired(l.Id);
        Lead hired = [SELECT Recruit_Stage__c, Candidate_Account__c FROM Lead WHERE Id = :l.Id];
        System.assertEquals('Hired', hired.Recruit_Stage__c);
        System.assertEquals(accountId, hired.Candidate_Account__c);
        System.assertEquals(accountId, LoRecruitingController.markHired(l.Id), 'second call reuses the account');

        try {
            LoRecruitingController.setStage(l.Id, 'Hired');
            System.assert(false, 'Hired only through markHired');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void stageAfterTouchRules() {
        System.assertEquals('Contacted', LoRecruitingController.stageAfterTouch('New', false));
        System.assertEquals('Conversation', LoRecruitingController.stageAfterTouch('New', true));
        System.assertEquals('Met', LoRecruitingController.stageAfterTouch('Met', true));
    }
}
