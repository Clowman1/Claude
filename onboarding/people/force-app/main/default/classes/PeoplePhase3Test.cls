@IsTest
private class PeoplePhase3Test {

    static People_Template_Task__c tpl(String type, String name, Decimal offset) {
        return new People_Template_Task__c(Name = name, Checklist_Type__c = type, Phase__c = 'Renewal', Offset_Days__c = offset,
            Offset_Unit__c = 'Calendar Days', Default_Assignee__c = UserInfo.getUserId(), Active__c = true, Sort_Order__c = 10);
    }

    static People_Employee__c activeEmployee(String states) {
        People_Employee__c e = new People_Employee__c(Name = 'Lee Staff', First_Name__c = 'Lee', Last_Name__c = 'Staff', Role__c = 'Loan Officer',
            Work_Arrangement__c = 'Remote', Status__c = 'Active', Start_Date__c = Date.newInstance(2024, 1, 8), Licensed_States__c = states);
        insert e;
        return e;
    }

    @IsTest
    static void renewalsRepeatPerStateAndRunOnce() {
        People_Template_Task__c perState = tpl('Renewal', 'Renew {STATE} license in NMLS', -30);
        perState.Per_State__c = true;
        insert new List<People_Template_Task__c>{ perState, tpl('Renewal', 'Annual BSA/AML refresher', -30) };
        People_Employee__c e = activeEmployee('FL;NV');
        System.assertEquals(1, PeopleController.getBoard().renewalEligible);

        System.assertEquals(1, PeopleController.generateRenewals(2026));
        System.assertEquals(0, PeopleController.generateRenewals(2026), 'second run skips');
        People_Checklist__c cl = [SELECT Id, Name, Anchor_Date__c, Renewal_Year__c FROM People_Checklist__c WHERE Employee__c = :e.Id];
        System.assertEquals(Date.newInstance(2026, 12, 31), cl.Anchor_Date__c);
        Set<String> names = new Set<String>();
        for (People_Task__c t : [SELECT Name, Due_Date__c FROM People_Task__c WHERE Checklist__c = :cl.Id]) {
            names.add(t.Name);
            System.assertEquals(Date.newInstance(2026, 12, 1), t.Due_Date__c);
        }
        System.assertEquals(new Set<String>{ 'Renew FL license in NMLS', 'Renew NV license in NMLS', 'Annual BSA/AML refresher' }, names);

        PeopleController.Board b = PeopleController.getBoard();
        System.assertEquals(1, b.cards.size());
        System.assertEquals('Renewal', b.cards[0].type);
        System.assertEquals(1, b.staff.size());
        System.assertEquals(0, b.renewalEligible);
    }

    @IsTest
    static void offboardingEndsInTermination() {
        insert new List<People_Template_Task__c>{ tpl('Offboarding', 'Disable all accesses', 0), tpl('Offboarding', 'COBRA paperwork sent', 5) };
        People_Employee__c e = activeEmployee(null);
        e.User__c = UserInfo.getUserId();
        update e;
        Date lastDay = Date.newInstance(2026, 11, 13);
        Id cl = PeopleController.offboard(e.Id, lastDay, 'Resigned');
        try {
            PeopleController.offboard(e.Id, lastDay, 'Resigned');
            System.assert(false, 'only one open offboarding');
        } catch (AuraHandledException ex) {
            System.assert(true);
        }
        People_Employee__c after = [SELECT Status__c, Termination_Date__c FROM People_Employee__c WHERE Id = :e.Id];
        System.assertEquals('Offboarding', after.Status__c);
        System.assertEquals(lastDay, after.Termination_Date__c);

        PeopleController.Detail d = PeopleController.getDetail(e.Id, cl);
        System.assertEquals('Offboarding', d.checklist.Type__c);
        System.assertEquals(2, d.tasks.size());
        System.assertNotEquals(null, d.openLeads);
        System.assertNotEquals(null, d.openTransactions);

        People_Employee__c edit = d.employee;
        edit.Termination_Date__c = Date.newInstance(2026, 11, 20);
        PeopleController.saveEmployee(edit);
        System.assertEquals(Date.newInstance(2026, 11, 20), [SELECT Due_Date__c FROM People_Task__c WHERE Name = 'Disable all accesses'].Due_Date__c);

        for (People_Task__c t : d.tasks) {
            PeopleController.setTaskStatus(t.Id, 'Done');
        }
        PeopleController.signers = new Set<Id>{ UserInfo.getUserId() };
        PeopleController.signOff(cl);
        System.assertEquals('Terminated', [SELECT Status__c FROM People_Employee__c WHERE Id = :e.Id].Status__c);
        try {
            PeopleController.offboard(e.Id, lastDay, null);
            System.assert(false, 'already terminated');
        } catch (AuraHandledException ex) {
            System.assert(true);
        }
    }

    @IsTest
    static void branchChecklistStartsWithTargetDate() {
        People_Template_Task__c t = tpl('Branch', 'Branch license application', -45);
        t.Phase__c = 'Licensing';
        People_Template_Task__c opt = tpl('Branch', 'Optional branch item', -10);
        opt.Optional__c = true;
        insert new List<People_Template_Task__c>{ t, opt };
        Id br = PeopleController.saveBranch(new People_Branch__c(Name = 'Test Branch', State__c = 'NV'));
        System.assertEquals(0, [SELECT COUNT() FROM People_Checklist__c WHERE Branch__c = :br], 'no date, no checklist');
        System.assertEquals('Planning', [SELECT Status__c FROM People_Branch__c WHERE Id = :br].Status__c);

        PeopleController.saveBranch(new People_Branch__c(Id = br, Name = 'Test Branch', Target_Open_Date__c = Date.newInstance(2027, 2, 1)));
        PeopleController.Detail d = PeopleController.getDetail(br, null);
        System.assertEquals('Branch', d.checklist.Type__c);
        System.assertEquals(1, d.tasks.size());
        System.assertEquals(1, d.optional.size());
        System.assertEquals(false, d.canViewPersonal);
        PeopleController.addOptionalTask(d.checklist.Id, d.optional[0].Id);

        PeopleController.saveBranch(new People_Branch__c(Id = br, Name = 'Test Branch', Target_Open_Date__c = Date.newInstance(2027, 3, 1)));
        System.assertEquals(Date.newInstance(2027, 1, 15), [SELECT Due_Date__c FROM People_Task__c WHERE Name = 'Branch license application'].Due_Date__c);
        System.assertEquals(1, [SELECT COUNT() FROM People_Checklist__c WHERE Branch__c = :br], 'moving the date never duplicates');

        Test.setCurrentPage(Page.PeopleExamPdf);
        ApexPages.currentPage().getParameters().put('id', d.checklist.Id);
        PeopleExamPdfController pdf = new PeopleExamPdfController();
        System.assertEquals('Test Branch', pdf.branch.Name);
        System.assert(pdf.title.contains('Branch'));
        try {
            PeopleController.saveBranch(new People_Branch__c());
            System.assert(false, 'name required');
        } catch (AuraHandledException ex) {
            System.assert(true);
        }
    }

    @IsTest
    static void licensingFollowsTheNmlsIdNotTheRole() {
        People_Template_Task__c ce = tpl('Renewal', 'Complete NMLS CE', -46);
        ce.Roles__c = 'Loan Officer;Branch Manager';
        insert ce;
        People_Employee__c boss = activeEmployee('FL');
        boss.Role__c = 'Manager';
        boss.NMLS_ID__c = '342274';
        People_Employee__c ops = activeEmployee('FL');
        ops.Role__c = 'Loan Officer';
        update new List<People_Employee__c>{ boss, ops };
        PeopleController.generateRenewals(2026);
        System.assertEquals(1, [SELECT COUNT() FROM People_Task__c WHERE Checklist__r.Employee__c = :boss.Id], 'Manager with NMLS renews');
        System.assertEquals(0, [SELECT COUNT() FROM People_Task__c WHERE Checklist__r.Employee__c = :ops.Id], 'no NMLS ID, no licensing tasks');
    }

    @IsTest
    static void octoberFifteenthOpensRenewals() {
        insert tpl('Renewal', 'Annual handbook re-acknowledgment', -30);
        activeEmployee(null);
        PeopleDaily.run(Date.newInstance(2026, 10, 15));
        System.assertEquals(1, [SELECT COUNT() FROM People_Checklist__c WHERE Type__c = 'Renewal' AND Renewal_Year__c = 2026]);
    }
}
