/**
 * Created by zeyad on 6/26/2020.
 */

({
    handleRecordLoad : function(component, event, helper) {
        const record = event.getParam('recordUi').record;
        const bankFunded = record.fields.Bank_Funded__c.value;
        const creditReportFee = record.fields.Credit_Report_Fee__c.value;
        
        if (!creditReportFee) {
            component.set("v.creditReportFee", 250);
        }
        
        console.log(creditReportFee);
        //record.fields.Credit_Report_Fee__c = 245;
		//component.set("v.creditReportFee", );        
        component.set("v.manualBankFunded", !!bankFunded); // true if populated, false if empty
    },
    onRecordSubmit: function(component, event, helper) {
        event.preventDefault();
        const fields = event.getParam("fields");
        fields.EOMONTH__c = helper.calculateEndOfMonth(fields).toISOString().substring(0,10);
        fields.Per_Diem__c = helper.calculatePer_Diem__c (fields);
        fields.Disbursement_Day__c = helper.calculateDisbursement_Day__c(fields);
        fields.PPD_Interest_Days__c = helper.calculatePPD_Interest_Days__c(fields);
        if(!component.get('v.isPPDManual')){
            fields.PPD_Interest__c  =  helper.calculatePPD_Interest__c (fields).toFixed(2);
        }
        fields.Amount_To_Be_Funded__c = (helper.calculateAmount_To_Be_Funded__c(fields)).toFixed(2);
        fields.Amount_Bank_Funded__c = helper.calculateAmount_Bank_Funded__c(fields).toFixed(2);
        
        if (!component.get("v.manualBankFunded")) {
        	fields.Bank_Funded__c = helper.calculateBank_Funded__c(fields).toFixed(2);
        } 

        fields.Haircut__c = helper.calculateHaircut__c(fields).toFixed(2);
        component.find('recordLoader').submit(fields);
        event.stopPropagation();
    },
    onSuccess : function(c,e,h){
        c.set('v.isGenerateEnabled', true);
        e.stopPropagation();
    },
    generateForm : function(c,e,h){
        let SUBMIT_WIRE_ACTION = c.get('c.generateWireCalculator');
        SUBMIT_WIRE_ACTION.setParams({
            recordId : c.get('v.recordId')
        });
        SUBMIT_WIRE_ACTION.setCallback(this, function(res){
            if(res.getState() === 'SUCCESS'){
                $A.get("e.force:closeQuickAction").fire();
            }
        });
        $A.enqueueAction(SUBMIT_WIRE_ACTION);
        var urlEvent = $A.get("e.force:navigateToURL");
        urlEvent.setParams({
            "url": "/apex/Wire_Calculator_PDF?id=" + c.get('v.recordId')
        });
        urlEvent.fire();
        //Close the action panel
        let dismissActionPanel = $A.get("e.force:closeQuickAction");
        dismissActionPanel.fire();
    },
    onError : function(c,e,h){
        var errorDetails = e.getParam('detail');
        var output = e.getParam('output');
        
        console.log('Error detail: ', errorDetails);
        console.log('Output: ', output);

        var toastEvent = $A.get("e.force:showToast");
        toastEvent.setParams({
            title: "Error",
            message: errorDetails || 'An error occurred while saving the record.',
            type: "error"
        });
        toastEvent.fire();

        debugger;
    },
    changePPDInterest: function(c,e,h) {
        c.set('v.isGenerateEnabled', false);
        c.set('v.isPPDManual', true);
    },
    handleBankFundedChange: function(c,e,h) {
        c.set('v.manualBankFunded', true);
    }
})