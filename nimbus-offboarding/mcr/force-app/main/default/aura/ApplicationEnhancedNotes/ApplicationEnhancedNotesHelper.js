({
    initHelper: function(c,e,h){
        let recordId = c.get('v.recordId');
        let action = c.get('c.getNotesRelatedToLoan');
        action.setParams({loanId:recordId});
        action.setCallback(this, function(res){
            if(res.getState() == 'SUCCESS'){
                let notes = res.getReturnValue();
                c.set('v.applicationNotes', h.getApplicationNotes(notes));
            }
        })
        $A.enqueueAction(action);
    },

    getApplicationNotes: function(notes) {
        return notes.filter(note => {
            if (note.Subject__c) {
                return note.Subject__c.toLowerCase().includes('application');
            }
            return false;
        });
    }
})