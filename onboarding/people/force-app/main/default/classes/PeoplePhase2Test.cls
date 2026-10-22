@IsTest
private class PeoplePhase2Test {

    static Id employeeWithTasks(List<People_Template_Task__c> templates, Date start, String workEmail) {
        insert templates;
        return PeopleController.createEmployee(new People_Employee__c(
            First_Name__c = 'Pat', Last_Name__c = 'Sample', Role__c = 'Processor', Work_Arrangement__c = 'Remote',
            Start_Date__c = start, Personal_Email__c = 'pat.sample@example.com', Work_Email__c = workEmail, NMLS_ID__c = '99999'
        ));
    }

    static People_Template_Task__c tpl(String name, Decimal offset) {
        return new People_Template_Task__c(Name = name, Checklist_Type__c = 'Onboarding', Phase__c = 'Pre-Start', Offset_Days__c = offset,
            Default_Assignee__c = UserInfo.getUserId(), Active__c = true, Sort_Order__c = offset);
    }

    @IsTest
    static void calendarOffsetsRollOffWeekends() {
        Date mon = Date.newInstance(2026, 11, 2);
        System.assertEquals(Date.newInstance(2026, 12, 2), PeopleController.dueDate(mon, 30, 'Calendar Days'));
        System.assertEquals(Date.newInstance(2026, 11, 9), PeopleController.dueDate(mon, 5, 'Calendar Days'), 'Sat Nov 7 rolls to Mon');
        System.assertEquals(PeopleController.addBusinessDays(mon, 5), PeopleController.dueDate(mon, 5, 'Business Days'));
        System.assertEquals(null, PeopleController.dueDate(mon, null, 'Calendar Days'));
    }

    @IsTest
    static void emailDraftRendersAndSendCompletesTask() {
        People_Template_Task__c t = tpl('Send offer heads-up', -14);
        t.Email_Template__c = 'TEST-1';
        Id emp = employeeWithTasks(new List<People_Template_Task__c>{ t }, Date.today().addDays(40), null);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new EmailTemplate(DeveloperName = 'People_TEST_1', Name = 'People test', TemplateType = 'custom', FolderId = UserInfo.getUserId(),
                IsActive = true, Subject = 'Hi {!People_Employee__c.First_Name__c}',
                HtmlValue = '<p>Hello {!People_Employee__c.First_Name__c}, due {{SEND_DATE_PLUS_2}}</p>');
        }
        People_Task__c task = [SELECT Id FROM People_Task__c WHERE Checklist__r.Employee__c = :emp];
        PeopleController.EmailDraft d = PeopleController.getEmailDraft(task.Id);
        System.assertEquals('pat.sample@example.com', d.to);
        System.assert(d.body.contains('Pat'), d.body);
        System.assert(!d.body.contains('{{SEND_DATE_PLUS_2}}'), d.body);

        try {
            PeopleController.sendTaskEmail(task.Id, 'not-an-email', d.subject, d.body);
            System.assert(false, 'bad address');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        PeopleController.sendTaskEmail(task.Id, d.to, d.subject, d.body);
        task = [SELECT Status__c, Notes__c, Completed_By__c FROM People_Task__c WHERE Id = :task.Id];
        System.assertEquals('Done', task.Status__c);
        System.assert(task.Notes__c.startsWith('Emailed to pat.sample@example.com'), task.Notes__c);
    }

    @IsTest
    static void missingTemplateIsReported() {
        People_Template_Task__c t = tpl('No template', -14);
        t.Email_Template__c = 'NOPE-9';
        Id emp = employeeWithTasks(new List<People_Template_Task__c>{ t }, Date.today().addDays(40), null);
        try {
            PeopleController.getEmailDraft([SELECT Id FROM People_Task__c WHERE Checklist__r.Employee__c = :emp].Id);
            System.assert(false, 'should throw');
        } catch (AuraHandledException e) {
            System.assert(true, 'missing template reported');
        }
    }

    @IsTest
    static void signOffLocksAndFilesThePdf() {
        Id emp = employeeWithTasks(new List<People_Template_Task__c>{ tpl('Only task', -14) }, Date.today().addDays(40), null);
        PeopleController.Detail d = PeopleController.getEmployee(emp);
        PeopleController.signers = new Set<Id>{ UserInfo.getUserId() };
        try {
            PeopleController.signOff(d.checklist.Id);
            System.assert(false, 'open task blocks sign-off');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        PeopleController.setTaskStatus(d.tasks[0].Id, 'Done');
        try {
            PeopleController.saveExamPdf(d.checklist.Id);
            System.assert(false, 'PDF needs sign-off');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        PeopleController.signOff(d.checklist.Id);
        Id doc = PeopleController.saveExamPdf(d.checklist.Id);
        People_Checklist__c c = [SELECT Status__c, Signed_Off_By__c, Exam_PDF_Id__c FROM People_Checklist__c WHERE Id = :d.checklist.Id];
        System.assertEquals('Signed Off', c.Status__c);
        System.assertEquals(UserInfo.getUserId(), c.Signed_Off_By__c);
        System.assertEquals(doc, c.Exam_PDF_Id__c);
        System.assertEquals(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :emp]);
        try {
            PeopleController.updateTask(d.tasks[0].Id, null, null, 'late edit');
            System.assert(false, 'locked');
        } catch (AuraHandledException e) {
            System.assert(true);
        }

        PeopleController.signers = new Set<Id>();
        try {
            PeopleController.signOff(d.checklist.Id);
            System.assert(false, 'not a signer');
        } catch (AuraHandledException e) {
            System.assert(true);
        }

        Test.setCurrentPage(Page.PeopleExamPdf);
        ApexPages.currentPage().getParameters().put('id', d.checklist.Id);
        PeopleExamPdfController pdf = new PeopleExamPdfController();
        System.assertEquals(1, pdf.sections.size());
        System.assertEquals('Other', pdf.sections[0].name);
        System.assertEquals('Complete', pdf.sections[0].rows[0].status);
        System.assertNotEquals(null, pdf.signedAt);
        System.assertNotEquals(null, pdf.attestation);
    }

    @IsTest
    static void userLinkCompletesTaskAndSyncsLicensing() {
        People_Template_Task__c t = tpl('Set up Salesforce user', -5);
        t.Auto_Complete__c = 'Salesforce user linked';
        String myEmail = [SELECT Email FROM User WHERE Id = :UserInfo.getUserId()].Email;
        Id emp = employeeWithTasks(new List<People_Template_Task__c>{ t }, Date.today().addDays(40), myEmail.toUpperCase());
        PeopleUserSync.linkEmployees();
        System.assertEquals(UserInfo.getUserId(), [SELECT User__c FROM People_Employee__c WHERE Id = :emp].User__c);
        System.assertEquals('Done', [SELECT Status__c FROM People_Task__c WHERE Checklist__r.Employee__c = :emp].Status__c);
        Test.startTest();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            new PeopleUserSync(true).execute(null);
        }
        Test.stopTest();
        System.assertEquals('99999', [SELECT NMLS__c FROM User WHERE Id = :UserInfo.getUserId()].NMLS__c);
    }

    @IsTest
    static void newUserTriggersSync() {
        Profile p = [SELECT Id FROM Profile WHERE UserLicense.Name = 'Salesforce' LIMIT 1];
        String u = 'people.sync.' + System.currentTimeMillis() + '@example.com';
        Test.startTest();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new User(Username = u, Email = u, LastName = 'Sync', Alias = 'psync', ProfileId = p.Id, TimeZoneSidKey = 'America/New_York',
                LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US');
        }
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM User WHERE Username = :u]);
    }

    @IsTest
    static void remindersGoOutOnTheDueDate() {
        People_Template_Task__c t = tpl('30-day check-in', 30);
        t.Remind__c = true;
        t.Offset_Unit__c = 'Calendar Days';
        Id emp = employeeWithTasks(new List<People_Template_Task__c>{ t }, Date.today().addDays(-30), null);
        People_Task__c task = [SELECT Id FROM People_Task__c WHERE Checklist__r.Employee__c = :emp];
        update new People_Task__c(Id = task.Id, Due_Date__c = Date.today());
        System.assertEquals(1, PeopleDaily.sendReminders(Date.today()));
        System.assertEquals(1, PeopleDaily.sendReminders(Date.today().addDays(-7)), '7 days ahead');
        System.assertEquals(0, PeopleDaily.sendReminders(Date.today().addDays(-3)));
    }
}
