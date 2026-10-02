/**
 * Created by Akram on 10/8/2020.
 */

({
    init : function(component, event, helper) {
        helper.getChecklistItems(component);
    },

    completeItem : function(component,event,helper){
        helper.toggleEdit(component,event.target.dataset.item);
    },
    toggleEdit : function(component,event,helper){
        //alert('Handling');
        try {
            helper.toggleEdit(component, event.target.dataset.item);
        } catch (e) {
            alert(e);
        } 
    },
    toggleEditDate : function(component,event,helper){
        helper.toggleEditDate(component, event.target.dataset.item);
    },
    updateField : function(component,event,helper){
        let fieldName = event.currentTarget && event.currentTarget.dataset
            ? event.currentTarget.dataset.item
            : event.target.dataset.item;
        if (!fieldName) {
            fieldName = helper.getEditedFieldApiName(component);
        }
        helper.submitForm(component, fieldName);
    },
    saveComplete : function(component,event,helper){
        let error = event.getParams();
        console.log("Error : " + JSON.stringify(error));
        let errorMessage = event.getParam("detail");
        let records = event.getParam("records");
        console.log("Error Message : " + errorMessage);
        if(errorMessage != null) {
            helper.showToast(errorMessage);
        }
		let checklist = component.get('v.checklist');
        for(let item of checklist.items){
            item.isEdit = false;       
        }

        component.set('v.checklist', checklist);
		component.set('v.isLoading', false);
        $A.get('e.force:refreshView').fire();

    },
    toggleAllClosed : function(component,event,helper){

        let checklist = component.get('v.checklist');
        for(let item of checklist.items){
            item.isEdit = false;
        }
        component.set('v.checklist', checklist);     
        component.set('v.spinner', false);
        if (component.get('v.pendingBpsSave')) {
            helper.handleBpsSaveSuccess(component);
            event.stopPropagation();
            return;
        }
        $A.get('e.force:refreshView').fire();
        event.stopPropagation();
    },
    handleVerificationCheckboxChange : function(component, event, helper) {
        component.set('v.isBpsVerificationChecked', event.getSource().get('v.checked'));
    },
    confirmBpsVerification : function(component, event, helper) {
        helper.persistBpsVerification(component, true);
    }

})