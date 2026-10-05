/**
 * Created by toma on 8/6/2021.
 */

({
    init : function (c,e,h) {
        let recordId = c.get('v.recordId');
        let metadataId = c.get('v.metadataId');
        let action = c.get('c.getEmptyFieldsFromLoan');
        action.setParams({loanId: recordId, metadataId: metadataId});
        action.setCallback(this, function (res) {
            if(res.getState() == 'SUCCESS'){
                let response = res.getReturnValue();
                c.set('v.percentMissing', response.percentOfFieldsMissing);
                c.set('v.fields', response['emptyFields']);
                c.set('v.alert', response['alert']);
                c.set('v.isMissingFields',response['emptyFields'].length > 0);
            }
        })
        $A.enqueueAction(action);
    }
});