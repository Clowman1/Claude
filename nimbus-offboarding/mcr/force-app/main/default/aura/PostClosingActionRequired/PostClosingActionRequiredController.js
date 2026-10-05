/**
 * Created by MSI Laptop on 7/25/2022.
 */

({
    loadData : function(c,e,h){
        let reasons = c.get('v.transactionRecord.Post_Closing_Action_Reason__c');
        if(reasons != null){
            let splitReasons = reasons.split(';');
            c.set('v.reasons',splitReasons);
        }
    }
});