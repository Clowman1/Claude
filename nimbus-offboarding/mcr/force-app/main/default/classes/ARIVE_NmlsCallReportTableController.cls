/**
 * Created by Zeyad Jabra on 8/19/2019.
 */

public with sharing class ARIVE_NmlsCallReportTableController {
    public class Table{
        @AuraEnabled
        public String title;
        @AuraEnabled
        public TableRow[] rows;

        public Table(){
            this.rows = new List<TableRow>();
        }
    }
    public class TableRow{
        @AuraEnabled
        public List<TableField> fields;
        @AuraEnabled
        public String id;

        public TableRow(){
            this.fields = new List<TableField>();
        }
    }
    public class TableField implements Comparable{
        @AuraEnabled
        public Decimal order;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String fieldType;
        @AuraEnabled
        public String modifier;
        @AuraEnabled
        public Object value;

        public Integer compareTo(Object o){
            TableField obj = (TableField)o;
            if(this.order > obj.order){
                return 1;
            }else if(this.order < obj.order){
                return -1;
            }
            return 0;
        }
    }

    // Rows come from ARIVE_NmlsCallReportController.detailRows, which runs the same filters as the top line.
    public static Table buildTable(String title, List<Transaction__c> loans) {
        Table table = new Table();
        table.title = title;
        for (Transaction__c loan : loans) {
            TableRow row = new TableRow();
            row.id = loan.Id;
            addField(row, 'Transaction Name', loan.Name);
            addField(row, 'Loan Number', loan.Loan_Number__c);
            addField(row, 'Loan Officer', loan.Loan_Officer__r.Name);
            addField(row, 'Loan Amount', loan.Loan_Amount_1st__c);
            addField(row, 'Trid Date', loan.TRID_Date__c);
            addField(row, 'Funded Date', loan.Funding_Date__c);
            addField(row, 'Withdrawn Date', loan.Withdrawn__c);
            addField(row, 'Channel', loan.Channel__c);
            table.rows.add(row);
        }
        return table;
    }

    private static void addField(TableRow row, String label, Object value) {
        TableField field = new TableField();
        field.order = row.fields.size() + 1;
        field.label = label;
        field.value = value;
        row.fields.add(field);
    }
}
