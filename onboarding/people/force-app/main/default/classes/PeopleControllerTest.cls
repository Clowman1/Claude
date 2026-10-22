@IsTest
private class PeopleControllerTest {

    @TestSetup
    static void setup() {
        Id me = UserInfo.getUserId();
        insert new List<People_Template_Task__c>{
            new People_Template_Task__c(Name = 'Welcome call', Checklist_Type__c = 'Onboarding', Phase__c = 'Pre-Start', Sort_Order__c = 10,
                Offset_Days__c = -14, Default_Assignee__c = me, Active__c = true),
            new People_Template_Task__c(Name = 'Collect background info', Checklist_Type__c = 'Onboarding', Phase__c = 'Pre-Start', Sort_Order__c = 20,
                Offset_Days__c = -13, Default_Assignee__c = me, Sets_Status__c = 'Pre-Start', Active__c = true),
            new People_Template_Task__c(Name = 'Confirm NMLS ID', Checklist_Type__c = 'Onboarding', Phase__c = 'Pre-Start', Sort_Order__c = 30,
                Offset_Days__c = -10, Roles__c = 'Loan Officer;Branch Manager', Active__c = true),
            new People_Template_Task__c(Name = 'Set up VPN', Checklist_Type__c = 'Onboarding', Phase__c = 'Pre-Start', Sort_Order__c = 40,
                Offset_Days__c = -5, Work_Arrangements__c = 'Remote;Hybrid', Active__c = true),
            new People_Template_Task__c(Name = 'FHA Connection ID', Checklist_Type__c = 'Onboarding', Phase__c = 'Pre-Start', Sort_Order__c = 50,
                Offset_Days__c = -7, Roles__c = 'Loan Officer', Optional__c = true, Active__c = true),
            new People_Template_Task__c(Name = 'Retired task', Checklist_Type__c = 'Onboarding', Phase__c = 'Day 1', Sort_Order__c = 60,
                Offset_Days__c = 0, Active__c = false)
        };
    }

    static People_Employee__c hire(String role, String arrangement, Date start) {
        return new People_Employee__c(First_Name__c = 'Test', Last_Name__c = 'Hire', Role__c = role, Work_Arrangement__c = arrangement, Start_Date__c = start);
    }

    @IsTest
    static void businessDaysSkipWeekendsAndHolidays() {
        Date mon = Date.newInstance(2026, 11, 2);
        System.assertEquals(Date.newInstance(2026, 10, 30), PeopleController.addBusinessDays(mon, -1), 'Monday minus 1 is Friday');
        System.assertEquals(Date.newInstance(2026, 11, 9), PeopleController.addBusinessDays(mon, 5));
        System.assertEquals(mon, PeopleController.addBusinessDays(mon, 0));
        System.assertEquals(null, PeopleController.addBusinessDays(mon, null));
        System.assert(!PeopleController.isWorkday(Date.newInstance(2026, 10, 31)), 'Saturday');
        if ([SELECT COUNT() FROM BusinessHours WHERE Name = 'TRID' AND IsActive = true] > 0) {
            System.assert(!PeopleController.isWorkday(Date.newInstance(2026, 11, 26)), 'Thanksgiving is a TRID holiday');
        }
    }

    @IsTest
    static void createGeneratesMatchingTasksOnly() {
        Date start = Date.newInstance(2026, 11, 30);
        Map<String, Object> preview = PeopleController.previewChecklist('Processor', 'In-Office', start);
        System.assertEquals(2, preview.get('count'), 'Welcome + background only');
        System.assertEquals(0, preview.get('optional'));

        Id lo = PeopleController.createEmployee(hire('Loan Officer', 'Remote', start));
        PeopleController.Detail d = PeopleController.getEmployee(lo);
        System.assertEquals('Test Hire', d.employee.Name);
        System.assertEquals('Candidate', d.employee.Status__c);
        System.assertEquals(4, d.tasks.size(), 'Welcome, background, NMLS, VPN; not optional or inactive');
        System.assertEquals(1, d.optional.size());
        System.assertEquals(PeopleController.addBusinessDays(start, -14), d.tasks[0].Due_Date__c);

        PeopleController.addOptionalTask(d.checklist.Id, d.optional[0].Id);
        PeopleController.addCustomTask(d.checklist.Id, 'Order nameplate', 'Day 1', start, UserInfo.getUserId());
        d = PeopleController.getEmployee(lo);
        System.assertEquals(6, d.tasks.size());
        System.assertEquals(0, d.optional.size());
    }

    @IsTest
    static void createRequiresBasics() {
        try {
            PeopleController.createEmployee(new People_Employee__c(First_Name__c = 'No'));
            System.assert(false, 'should throw');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void completingStampsAndMovesStatus() {
        Id emp = PeopleController.createEmployee(hire('Processor', 'In-Office', Date.today().addDays(30)));
        People_Task__c bg = [SELECT Id FROM People_Task__c WHERE Name = 'Collect background info'];
        PeopleController.setTaskStatus(bg.Id, 'Done');
        bg = [SELECT Status__c, Completed_By__c, Completed_At__c FROM People_Task__c WHERE Id = :bg.Id];
        System.assertEquals('Done', bg.Status__c);
        System.assertEquals(UserInfo.getUserId(), bg.Completed_By__c);
        System.assertNotEquals(null, bg.Completed_At__c);
        System.assertEquals('Pre-Start', [SELECT Status__c FROM People_Employee__c WHERE Id = :emp].Status__c);

        PeopleController.setTaskStatus(bg.Id, 'Open');
        bg = [SELECT Status__c, Completed_By__c FROM People_Task__c WHERE Id = :bg.Id];
        System.assertEquals('Open', bg.Status__c);
        System.assertEquals(null, bg.Completed_By__c);

        PeopleController.updateTask(bg.Id, UserInfo.getUserId(), Date.today(), 'note');
        System.assertEquals('note', [SELECT Notes__c FROM People_Task__c WHERE Id = :bg.Id].Notes__c);
    }

    @IsTest
    static void startDateMoveRecalculatesOpenTasks() {
        Date start = Date.newInstance(2026, 11, 30);
        Id emp = PeopleController.createEmployee(hire('Processor', 'In-Office', start));
        People_Task__c done = [SELECT Id, Due_Date__c FROM People_Task__c WHERE Name = 'Welcome call'];
        PeopleController.setTaskStatus(done.Id, 'Done');

        People_Employee__c e = PeopleController.getEmployee(emp).employee;
        e.Start_Date__c = Date.today().addDays(3);
        Integer late = PeopleController.saveEmployee(e);
        System.assertEquals(1, late, 'Background info (-13) now falls in the past');
        System.assertEquals(done.Due_Date__c, [SELECT Due_Date__c FROM People_Task__c WHERE Id = :done.Id].Due_Date__c, 'done task keeps its date');
        System.assertEquals(PeopleController.addBusinessDays(e.Start_Date__c, -13),
            [SELECT Due_Date__c FROM People_Task__c WHERE Name = 'Collect background info'].Due_Date__c);
        System.assertEquals(0, PeopleController.saveEmployee(e), 'unchanged start date');
    }

    @IsTest
    static void boardDigestAndWithdraw() {
        Id emp = PeopleController.createEmployee(hire('Processor', 'In-Office', Date.today().addDays(5)));
        PeopleController.Board b = PeopleController.getBoard();
        System.assertEquals(1, b.cards.size());
        System.assertEquals(2, b.cards[0].total);
        System.assertEquals(2, b.cards[0].overdue, 'both tasks are due 13-14 business days before a start 5 days out');
        System.assertEquals(2, b.digest.size());

        PeopleController.withdraw(emp);
        System.assertEquals(0, PeopleController.getBoard().cards.size());
        System.assertEquals(0, [SELECT COUNT() FROM People_Task__c WHERE Status__c = 'Open']);
        try {
            PeopleController.setTaskStatus([SELECT Id FROM People_Task__c LIMIT 1].Id, 'Open');
            System.assert(false, 'closed checklist');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void templatesSaveAndReorder() {
        Id newId = PeopleController.saveTemplate(new People_Template_Task__c(Name = 'New one', Checklist_Type__c = 'Onboarding', Phase__c = 'Week 1', Active__c = true));
        System.assertEquals(70, [SELECT Sort_Order__c FROM People_Template_Task__c WHERE Id = :newId].Sort_Order__c);
        List<People_Template_Task__c> all = PeopleController.getTemplates('Onboarding');
        List<Id> ids = new List<Id>{ newId };
        for (People_Template_Task__c t : all) {
            if (t.Id != newId) {
                ids.add(t.Id);
            }
        }
        PeopleController.reorderTemplates(ids);
        System.assertEquals(10, [SELECT Sort_Order__c FROM People_Template_Task__c WHERE Id = :newId].Sort_Order__c);
        try {
            PeopleController.saveTemplate(new People_Template_Task__c(Checklist_Type__c = 'Onboarding'));
            System.assert(false, 'subject required');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        System.assertNotEquals(null, PeopleController.getAssignees());
    }

    @IsTest
    static void personalFieldsNeedThePermission() {
        Id emp = PeopleController.createEmployee(hire('Processor', 'In-Office', Date.today().addDays(30)));
        Boolean allowed = [SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSet.PermissionsViewEncryptedData = true] > 0;
        try {
            PeopleController.savePersonal(new People_Employee__c(Id = emp, Date_of_Birth__c = '01/02/1990'));
            System.assertEquals('01/02/1990', PeopleController.getPersonal(emp).Date_of_Birth__c);
            System.assert(allowed, 'only with View Encrypted Data');
        } catch (AuraHandledException e) {
            System.assert(!allowed);
        }
    }

    @IsTest
    static void dailyJobActivatesAndEmails() {
        Id emp = PeopleController.createEmployee(hire('Processor', 'In-Office', Date.newInstance(2026, 10, 26)));
        Test.startTest();
        PeopleDaily.run(Date.newInstance(2026, 10, 26)); // a Monday
        PeopleDaily.run(Date.newInstance(2026, 10, 31)); // Saturday: status only
        System.schedule('People daily test', '0 0 9 * * ?', new PeopleDaily());
        Test.stopTest();
        System.assertEquals('Active', [SELECT Status__c FROM People_Employee__c WHERE Id = :emp].Status__c);
    }
}
