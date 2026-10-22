@IsTest
private class PeoplePhase4Test {

    static People_Employee__c existing(String states, String nmls) {
        Id id = PeopleHrController.addExistingEmployee(new People_Employee__c(
            First_Name__c = 'Kim', Last_Name__c = 'Current', Role__c = 'Loan Officer', Licensed_States__c = states, NMLS_ID__c = nmls
        ));
        return [SELECT Id, Name, Status__c, Licensed_States__c FROM People_Employee__c WHERE Id = :id];
    }

    @IsTest
    static void existingEmployeeSkipsOnboardingAndGetsLicenses() {
        People_Employee__c e = existing('NV;FL', '111');
        System.assertEquals('Active', e.Status__c);
        System.assertEquals(0, [SELECT COUNT() FROM People_Checklist__c WHERE Employee__c = :e.Id AND Type__c = 'Onboarding']);
        PeopleHrController.Hr h = PeopleHrController.getHr(e.Id);
        System.assertEquals(2, h.licenses.size());
        System.assertEquals('Active', h.licenses[0].Status__c);
        System.assert(h.missing.contains('Hire date'));
        System.assert(h.missing.contains('FL license number'), 'licensed: number required');
        try {
            PeopleHrController.addExistingEmployee(new People_Employee__c(First_Name__c = 'No'));
            System.assert(false, 'role required');
        } catch (AuraHandledException ex) {
            System.assert(true);
        }
    }

    @IsTest
    static void licensesDriveLicensedStates() {
        People_Employee__c e = existing('FL', '111');
        People_License__c fl = [SELECT Id FROM People_License__c WHERE Employee__c = :e.Id];
        PeopleHrController.saveLicense(new People_License__c(Employee__c = e.Id, State__c = 'TX', Status__c = 'Pending'));
        System.assertEquals('FL;TX', [SELECT Licensed_States__c FROM People_Employee__c WHERE Id = :e.Id].Licensed_States__c);
        PeopleHrController.saveLicense(new People_License__c(Id = fl.Id, State__c = 'FL', Status__c = 'Inactive', License_Number__c = 'LO123'));
        System.assertEquals('TX', [SELECT Licensed_States__c FROM People_Employee__c WHERE Id = :e.Id].Licensed_States__c);
        try {
            PeopleHrController.saveLicense(new People_License__c(Employee__c = e.Id, State__c = 'TX', Status__c = 'Active'));
            System.assert(false, 'one license per state');
        } catch (AuraHandledException ex) {
            System.assert(true);
        }
        try {
            PeopleHrController.saveLicense(new People_License__c(Employee__c = e.Id, Status__c = 'Active'));
            System.assert(false, 'state required');
        } catch (AuraHandledException ex) {
            System.assert(true);
        }
    }

    @IsTest
    static void compensationHistory() {
        People_Employee__c e = existing(null, null);
        PeopleHrController.saveComp(new People_Compensation__c(Employee__c = e.Id, Effective_Date__c = Date.newInstance(2025, 1, 1), Pay_Type__c = 'Salary', Base_Amount__c = 60000, Base_Per__c = 'Year'));
        PeopleHrController.saveComp(new People_Compensation__c(Employee__c = e.Id, Effective_Date__c = Date.newInstance(2026, 1, 1), Pay_Type__c = 'Salary + Commission', Base_Amount__c = 65000, LO_Comp_Bps__c = 50));
        List<People_Compensation__c> comp = PeopleHrController.getHr(e.Id).compensation;
        System.assertEquals(2, comp.size());
        System.assertEquals(65000, comp[0].Base_Amount__c, 'newest first');
        PeopleHrController.deleteComp(comp[1].Id);
        System.assertEquals(1, PeopleHrController.getHr(e.Id).compensation.size());
        try {
            PeopleHrController.saveComp(new People_Compensation__c(Employee__c = e.Id));
            System.assert(false, 'date + pay type required');
        } catch (AuraHandledException ex) {
            System.assert(true);
        }
    }

    @IsTest
    static void approvedRenewalRenewsTheLicenseAndShowsInTheGrid() {
        People_Template_Task__c approve = new People_Template_Task__c(Name = 'Confirm {STATE} renewal approved', Checklist_Type__c = 'Renewal', Phase__c = 'Renewal',
            Offset_Days__c = 0, Offset_Unit__c = 'Calendar Days', Active__c = true, Per_State__c = true, Renews_License__c = true, Sort_Order__c = 10,
            Default_Assignee__c = UserInfo.getUserId());
        People_Template_Task__c bsa = new People_Template_Task__c(Name = 'BSA/AML refresher', Checklist_Type__c = 'Renewal', Phase__c = 'Renewal',
            Offset_Days__c = -30, Offset_Unit__c = 'Calendar Days', Active__c = true, Sort_Order__c = 20, Default_Assignee__c = UserInfo.getUserId());
        insert new List<People_Template_Task__c>{ approve, bsa };
        People_Employee__c e = existing('FL;NV', '111');
        PeopleController.generateRenewals(Date.today().year());
        People_Checklist__c cl = [SELECT Name FROM People_Checklist__c WHERE Employee__c = :e.Id AND Type__c = 'Renewal'];
        System.assert(cl.Name.startsWith('Annual Compliance'), cl.Name);

        People_Task__c fl = [SELECT Id FROM People_Task__c WHERE License_State__c = 'FL'];
        PeopleController.setTaskStatus(fl.Id, 'Done');
        People_License__c lic = [SELECT Last_Renewed__c, Expiration_Date__c FROM People_License__c WHERE Employee__c = :e.Id AND State__c = 'FL'];
        System.assertEquals(Date.today(), lic.Last_Renewed__c);
        System.assertEquals(Date.newInstance(Date.today().year() + 1, 12, 31), lic.Expiration_Date__c);

        PeopleHrController.Compliance c = PeopleHrController.getCompliance();
        System.assertEquals(new List<String>{ 'Confirm renewal approved', 'BSA/AML refresher' }, c.columns);
        System.assertEquals(1, c.rows.size());
        System.assertEquals('FL ✓, NV', c.rows[0].cells[0].detail);
        System.assert(c.missing.containsKey(e.Id));
        System.assertEquals('Kim Current', c.names.get(e.Id));
        System.assertNotEquals(null, c.expiring);
        System.assertEquals(1, PeopleController.getBoard().missing.size());
    }

    @IsTest
    static void cellStatuses() {
        Date today = Date.newInstance(2026, 11, 1);
        System.assertEquals('na', PeopleHrController.cellFor(new List<People_Task__c>(), today).status);
        System.assertEquals('done', PeopleHrController.cellFor(new List<People_Task__c>{ new People_Task__c(Status__c = 'Done') }, today).status);
        System.assertEquals('open', PeopleHrController.cellFor(new List<People_Task__c>{ new People_Task__c(Status__c = 'Open', Due_Date__c = today) }, today).status);
        System.assertEquals('overdue', PeopleHrController.cellFor(new List<People_Task__c>{ new People_Task__c(Status__c = 'Open', Due_Date__c = today.addDays(-1)) }, today).status);
    }

    @IsTest
    static void newHireGetsPendingLicenses() {
        Id id = PeopleController.createEmployee(new People_Employee__c(First_Name__c = 'New', Last_Name__c = 'Hire', Role__c = 'Loan Officer',
            Work_Arrangement__c = 'Remote', Start_Date__c = Date.today().addDays(30), Licensed_States__c = 'NV'));
        People_License__c l = [SELECT Status__c, Sponsorship__c FROM People_License__c WHERE Employee__c = :id];
        System.assertEquals('Pending', l.Status__c);
        System.assertEquals('Pending', l.Sponsorship__c);
        System.assertNotEquals(null, PeopleHrController.getMissing());
    }
}
