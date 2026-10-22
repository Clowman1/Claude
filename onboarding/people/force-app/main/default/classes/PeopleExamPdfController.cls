// People app: data for the PeopleExamPdf page, the regulator-format onboarding checklist (TN DFI layout, decision 25).
// Items are grouped Regulatory / Systems / Documentation / Other, each with who completed it and when.
public with sharing class PeopleExamPdfController {

    public People_Checklist__c checklist { get; private set; }
    public People_Employee__c employee { get; private set; }
    public List<Section> sections { get; private set; }
    public String attestation { get { return PeopleController.ATTESTATION; } }
    public String signedAt { get; private set; }
    public String printedAt { get; private set; }

    public class Row {
        public String item { get; set; }
        public String status { get; set; }
        public String completedBy { get; set; }
        public String completedAt { get; set; }
    }

    public class Section {
        public String name { get; set; }
        public List<Row> rows { get; set; }
    }

    public PeopleExamPdfController() {
        Id checklistId = ApexPages.currentPage().getParameters().get('id');
        checklist = [
            SELECT Id, Name, Status__c, Employee__c, Signed_Off_By__r.Name, Signed_Off_At__c,
                (SELECT Name, Status__c, Exam_Section__c, Completed_By__r.Name, Completed_At__c FROM Tasks__r ORDER BY Sort_Order__c, Due_Date__c)
            FROM People_Checklist__c WHERE Id = :checklistId
        ];
        employee = [
            SELECT Name, Role__c, Start_Date__c, NMLS_ID__c, Manager__r.Name, Branch__r.Name, Licensed_States__c
            FROM People_Employee__c WHERE Id = :checklist.Employee__c
        ];
        signedAt = checklist.Signed_Off_At__c == null ? null : checklist.Signed_Off_At__c.format('MMMM d, yyyy h:mm a', 'America/New_York') + ' ET';
        printedAt = System.now().format('MMMM d, yyyy h:mm a', 'America/New_York') + ' ET';
        Map<String, Section> byName = new Map<String, Section>();
        for (String n : new List<String>{ 'Regulatory', 'Systems', 'Documentation', 'Other' }) {
            Section s = new Section();
            s.name = n;
            s.rows = new List<Row>();
            byName.put(n, s);
        }
        for (People_Task__c t : checklist.Tasks__r) {
            Row r = new Row();
            r.item = t.Name;
            r.status = t.Status__c == 'Open' ? 'Open' : t.Status__c == 'N/A' ? 'N/A' : 'Complete';
            r.completedBy = t.Completed_By__r?.Name;
            r.completedAt = t.Completed_At__c == null ? null : t.Completed_At__c.format('MM/dd/yyyy', 'America/New_York');
            byName.get(t.Exam_Section__c == null ? 'Other' : t.Exam_Section__c).rows.add(r);
        }
        sections = new List<Section>();
        for (Section s : byName.values()) {
            if (!s.rows.isEmpty()) {
                sections.add(s);
            }
        }
    }
}
