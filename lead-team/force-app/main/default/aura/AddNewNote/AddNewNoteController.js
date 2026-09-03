/**
 * Created by toma on 8/23/2021.
 */

({
    doInit: function(c,e,h) {
        let action = c.get('c.getLookupField');
        let appId = c.get('v.applicationId');
        action.setParams({recordId: appId});
        action.setCallback(this,function (res){
            if(res.getState() == 'SUCCESS'){
                let lookupField = res.getReturnValue();
                c.set('v.lookupField', lookupField);
                // Drives both the @mention hint and the "Lead Update" subject default,
                // neither of which applies to Transaction or Account notes.
                c.set('v.isLeadNote', lookupField === 'Lead__c');
            }
        })
        $A.enqueueAction(action);
    },
    submit : function(c,e,h){
        // Closing is handled by onSuccess, once the save is actually confirmed.
        c.find('AddNewNoteForm').submit();
    },
    onSuccess: function(c,e,h){
        // Fires only after the note is committed, so this is the safe place to close.
        // Covers both buttons: "Create Note" (type="submit") and "Save And Close".
        // The attributes are still set first so the form degrades to a sane saved
        // state if the browser refuses to close the popup.
        var noteId = e.getParam("response").id
        c.set("v.noteId", noteId);
        var date = new Date();
        c.set("v.date", "Last Saved: " + date.toLocaleTimeString());
        window.close();
    },
    error : function (c,e,h){
        var error = e.getParam("error");
        console.log(error.message); // main error message
        let errorString = JSON.stringify(e.getParams());
        console.log(JSON.stringify(e.getParams()));
    },
    deleteNote : function (c,e,h){
        c.set('v.showConfirmDialog', true);

    },
    handleConfirmDialogYes : function(component, event, helper) {
        console.log('Yes');
        let record = component.get('v.noteId');
        let action = component.get('c.deleteTargetNote');
        action.setParams({recordId: record});
        action.setCallback(this,function (res){
            if(res.getState() == 'SUCCESS'){
                window.close()
            }
        })
        $A.enqueueAction(action); 
        component.set('v.showConfirmDialog', false);
    },
    handleConfirmDialogNo : function(component, event, helper) {
        console.log('No');
        component.set('v.showConfirmDialog', false);
    },
    closeWindow: function(c,e,h){
        window.close(); 
    }
});
