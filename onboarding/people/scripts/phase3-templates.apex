// Phase 3 (2026-10-22): Renewal, Offboarding and Branch master templates. Drafted from the onboarding xlsx
// (offboarding section, branch sub-tabs) plus Nevada licensing; edit freely in People > Master template.
// Skips any type that already has templates, so re-running is safe.
Id bianca = '0055x00000Bf9iaAAB', chris = '005f2000009OtLnAAK';
Set<String> loaded = new Set<String>();
for (AggregateResult ar : [SELECT Checklist_Type__c t FROM People_Template_Task__c GROUP BY Checklist_Type__c]) loaded.add((String) ar.get('t'));
List<People_Template_Task__c> rows = new List<People_Template_Task__c>();
Integer n = 0;
// type, phase, subject, description, offset, unit, assignee, ledBy, roles, arrangements, exam, perState, remind, sendTo, optional
List<List<Object>> spec = new List<List<Object>>{
    new List<Object>{ 'Renewal', 'Renewal', 'Complete NMLS annual CE (8 hours)', 'Confirm the CE certificate posts in NMLS.', -46, 'Calendar Days', bianca, null, 'Loan Officer;Branch Manager', null, 'Regulatory', false, true, null, false },
    new List<Object>{ 'Renewal', 'Renewal', 'Submit {STATE} license renewal in NMLS', 'Renewal window opens Nov 1; deadline Dec 31.', -30, 'Calendar Days', bianca, null, 'Loan Officer;Branch Manager', null, 'Regulatory', true, true, null, false },
    new List<Object>{ 'Renewal', 'Renewal', 'Confirm {STATE} renewal approved in NMLS', 'Status shows Approved for the coming year.', 0, 'Calendar Days', bianca, null, 'Loan Officer;Branch Manager', null, 'Regulatory', true, false, null, false },
    new List<Object>{ 'Renewal', 'Renewal', 'Annual BSA/AML refresher training (OnCourse)', 'Collect the certificate.', -30, 'Calendar Days', bianca, null, null, null, 'Regulatory', false, true, null, false },
    new List<Object>{ 'Renewal', 'Renewal', 'Annual employee handbook re-acknowledgment', 'Signed acknowledgment filed.', -30, 'Calendar Days', bianca, null, null, null, 'Documentation', false, false, null, false },
    new List<Object>{ 'Renewal', 'Renewal', 'Update NMLS individual record (MU4) if anything changed', 'Address, disclosures, employment.', -46, 'Calendar Days', bianca, null, 'Loan Officer;Branch Manager', null, 'Regulatory', false, false, null, true },

    new List<Object>{ 'Offboarding', 'Before Last Day', 'Receive resignation letter or signed separation agreement', 'If applicable.', -5, 'Business Days', bianca, null, null, null, 'Documentation', false, false, null, false },
    new List<Object>{ 'Offboarding', 'Before Last Day', 'File notice of termination in employee folder', null, -3, 'Business Days', bianca, null, null, null, 'Documentation', false, false, null, false },
    new List<Object>{ 'Offboarding', 'Before Last Day', 'Reassign open Leads and Transactions', 'The People page shows the open counts for this employee.', -2, 'Business Days', chris, null, null, null, null, false, false, null, false },
    new List<Object>{ 'Offboarding', 'Before Last Day', 'Send FedEx return slip for the computer', 'Set up at a FedEx Office (Kinko\'s).', -2, 'Business Days', bianca, null, null, 'Remote;Hybrid', null, false, false, null, false },
    new List<Object>{ 'Offboarding', 'Last Day', 'Collect equipment and office keys', null, 0, 'Business Days', bianca, null, null, null, null, false, false, null, false },
    new List<Object>{ 'Offboarding', 'Last Day', 'Deactivate Salesforce user', 'After Leads and Transactions are reassigned.', 0, 'Business Days', chris, null, null, null, 'Systems', false, false, null, false },
    new List<Object>{ 'Offboarding', 'Last Day', 'Disable system access', 'ARIVE, Encompass, UWM/EASE, Advantage, CIC, RingCentral, GoHighLevel, Trainual, DocuSign as applicable.', 0, 'Business Days', bianca, null, null, null, 'Systems', false, false, null, false },
    new List<Object>{ 'Offboarding', 'Last Day', 'Request Outlook / Microsoft 365 shutdown from KB Technologies', 'Mailbox shutdown and forwarding per manager.', 0, 'Business Days', bianca, null, null, null, 'Systems', false, false, 'support@kb-global.com', false },
    new List<Object>{ 'Offboarding', 'Last Day', 'Process final pay in Paychex', null, 0, 'Business Days', bianca, null, null, null, 'Documentation', false, false, null, false },
    new List<Object>{ 'Offboarding', 'After Last Day', 'Remove from NMLS and document', 'Terminate sponsorship (RHL NMLS 2266637).', 1, 'Business Days', bianca, null, 'Loan Officer;Branch Manager', null, 'Regulatory', false, false, null, false },
    new List<Object>{ 'Offboarding', 'After Last Day', 'Remove from Teams channels and distribution lists', null, 1, 'Business Days', bianca, null, null, null, 'Systems', false, false, null, false },
    new List<Object>{ 'Offboarding', 'After Last Day', 'Send COBRA paperwork and document', null, 5, 'Business Days', bianca, null, null, null, 'Documentation', false, false, null, false },
    new List<Object>{ 'Offboarding', 'After Last Day', 'Confirm all equipment received', null, 10, 'Business Days', bianca, null, null, null, null, false, false, null, false },

    new List<Object>{ 'Branch', 'Approval', 'Branch Manager resume', null, -60, 'Business Days', bianca, 'RSM / SVP of Production', null, null, 'Documentation', false, false, null, false },
    new List<Object>{ 'Branch', 'Approval', 'Current payrolls and last 2 years W-2s', null, -60, 'Business Days', bianca, 'RSM / SVP of Production', null, null, 'Documentation', false, false, null, false },
    new List<Object>{ 'Branch', 'Approval', 'YTD production reports (closed and current pipeline)', null, -60, 'Business Days', bianca, 'RSM / SVP of Production', null, null, 'Documentation', false, false, null, false },
    new List<Object>{ 'Branch', 'Approval', '12-month fully executed lease', 'Or proposed lease terms for review.', -55, 'Business Days', bianca, 'Facilities / Accounting', null, null, 'Documentation', false, false, null, false },
    new List<Object>{ 'Branch', 'Approval', 'Written recommendation from Regional Manager', null, -55, 'Business Days', bianca, 'RSM', null, null, 'Documentation', false, false, null, false },
    new List<Object>{ 'Branch', 'Approval', '90-day business plan', 'Business development and growth.', -55, 'Business Days', bianca, 'Branch Manager', null, null, 'Documentation', false, false, null, false },
    new List<Object>{ 'Branch', 'Approval', 'Completed applications for the entire group', null, -55, 'Business Days', bianca, 'HR', null, null, 'Documentation', false, false, null, false },
    new List<Object>{ 'Branch', 'Approval', 'Branch Manager interview call with CFO / Partners', null, -50, 'Business Days', bianca, 'Adam', null, null, null, false, false, null, false },
    new List<Object>{ 'Branch', 'Approval', 'CEO / Partner approval', null, -50, 'Business Days', bianca, 'Adam', null, null, 'Documentation', false, false, null, false },
    new List<Object>{ 'Branch', 'Licensing', 'State branch license application', 'Nevada: Division of Mortgage Lending branch license.', -45, 'Business Days', bianca, null, null, null, 'Regulatory', false, true, null, false },
    new List<Object>{ 'Branch', 'Licensing', 'NMLS branch record and sponsorship', 'Record the Branch NMLS ID on the branch.', -40, 'Business Days', bianca, null, null, null, 'Regulatory', false, false, null, false },
    new List<Object>{ 'Branch', 'Licensing', 'Notify Licensing Store (Tonya) of the new branch', null, -40, 'Business Days', bianca, null, null, null, 'Regulatory', false, false, 'Licensing Store (Tonya)', false },
    new List<Object>{ 'Branch', 'Licensing', 'Review and approve lease and vendor agreements', null, -30, 'Business Days', bianca, 'Facilities / Accounting', null, null, 'Documentation', false, false, null, false },
    new List<Object>{ 'Branch', 'Licensing', 'Certificate of occupancy', null, -20, 'Business Days', bianca, 'Facilities / Accounting', null, null, 'Documentation', false, false, null, false },
    new List<Object>{ 'Branch', 'Setup', 'Identify branch point person and timeline for all employees', null, -30, 'Business Days', bianca, 'SVP / RSM', null, null, null, false, false, null, false },
    new List<Object>{ 'Branch', 'Setup', 'Exchange contact lists (key associates, both firms)', null, -28, 'Business Days', bianca, 'SVP / RSM', null, null, null, false, false, null, false },
    new List<Object>{ 'Branch', 'Setup', 'Department overview calls with the new group', null, -25, 'Business Days', bianca, 'SVP / RSM', null, null, null, false, false, null, false },
    new List<Object>{ 'Branch', 'Setup', 'Submit project plan and establish acquisition / start date', null, -25, 'Business Days', bianca, 'SVP / RSM', null, null, null, false, false, null, false },
    new List<Object>{ 'Branch', 'Setup', 'Positions, titles and salaries; extend offer letters', null, -20, 'Business Days', bianca, 'HR', null, null, 'Documentation', false, false, null, false },
    new List<Object>{ 'Branch', 'Setup', 'Add each branch employee in People (New Employee)', 'Their own onboarding checklists cover background checks, systems and training.', -20, 'Business Days', bianca, null, null, null, null, false, false, null, false },
    new List<Object>{ 'Branch', 'Setup', 'IT discovery meeting (phone, internet, copier)', null, -20, 'Business Days', bianca, 'IT', null, null, 'Systems', false, false, 'support@kb-global.com', false },
    new List<Object>{ 'Branch', 'Setup', 'Compensation agreements signed by all parties', null, -15, 'Business Days', bianca, 'HR', null, null, 'Documentation', false, false, null, false },
    new List<Object>{ 'Branch', 'Setup', 'Order PCs / laptops', null, -15, 'Business Days', bianca, 'IT', null, null, 'Systems', false, false, null, false },
    new List<Object>{ 'Branch', 'Setup', 'Request FHA / VA IDs by function', null, -10, 'Business Days', bianca, 'Operations Manager', null, null, 'Regulatory', false, false, null, false },
    new List<Object>{ 'Branch', 'Setup', 'Appraisal ordering (AMC) accounts', null, -10, 'Business Days', bianca, null, null, null, 'Systems', false, false, null, false },
    new List<Object>{ 'Branch', 'Setup', 'ARIVE custom branch / DBA PQ and PA templates', null, -10, 'Business Days', chris, null, null, null, 'Systems', false, false, null, false },
    new List<Object>{ 'Branch', 'Setup', 'Training dates, resources and trainers', 'Online, onsite, job shadowing, meetings.', -10, 'Business Days', bianca, null, null, null, null, false, false, null, false },
    new List<Object>{ 'Branch', 'Launch', 'Order business cards', null, -5, 'Business Days', bianca, null, null, null, null, false, false, null, false },
    new List<Object>{ 'Branch', 'Launch', 'New branch marketing flyers', null, -5, 'Business Days', bianca, 'Marketing', null, null, null, false, false, null, false },
    new List<Object>{ 'Branch', 'Launch', 'Announce new hires (cards and social media banner)', null, 0, 'Business Days', bianca, 'Marketing', null, null, null, false, false, null, false },
    new List<Object>{ 'Branch', 'Launch', 'Update MLO application page and branch website', null, 0, 'Business Days', bianca, 'Marketing', null, null, null, false, false, null, false }
};
Map<String, Integer> order = new Map<String, Integer>();
for (List<Object> r : spec) {
    String type = (String) r[0];
    if (loaded.contains(type)) continue;
    Integer o = (order.containsKey(type) ? order.get(type) : 0) + 10;
    order.put(type, o);
    rows.add(new People_Template_Task__c(
        Checklist_Type__c = type, Phase__c = (String) r[1], Name = (String) r[2], Description__c = (String) r[3], Offset_Days__c = (Integer) r[4],
        Offset_Unit__c = (String) r[5], Default_Assignee__c = (Id) r[6], Led_By__c = (String) r[7], Roles__c = (String) r[8], Work_Arrangements__c = (String) r[9],
        Exam_Section__c = (String) r[10], Per_State__c = (Boolean) r[11], Remind__c = (Boolean) r[12], Send_To__c = (String) r[13], Optional__c = (Boolean) r[14],
        Sort_Order__c = o, Active__c = true
    ));
}
insert rows;
for (AggregateResult ar : [SELECT Checklist_Type__c t, COUNT(Id) c FROM People_Template_Task__c GROUP BY Checklist_Type__c]) System.debug('TPL ' + ar.get('t') + ' ' + ar.get('c'));
