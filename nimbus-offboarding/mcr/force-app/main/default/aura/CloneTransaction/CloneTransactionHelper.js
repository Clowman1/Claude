/**
 * Created by c_zjabra on 12/16/2021.
 */

({
    showToast : function(c,e,msg,state,recordId){
        var toastEvent = $A.get("e.force:showToast");
        if(state == 'SUCCESS'){
            toastEvent.setParams({
                title:"Success!",
                type:'success',
                mode: 'sticky',
                message: 'Transaction has been cloned',
                messageTemplate: 'Record {0} created! See it {1}!',
                messageTemplateData: ['Salesforce', {
                    url: '/lightning/r/Transaction__c/'+recordId+'/view',
                    label: 'here',
                }
                ]

            });
        }
        else{
            toastEvent.setParams({
                type: 'error',
                mode: 'dismissible',
                message: msg
            });
        }
        toastEvent.fire();
    }
});