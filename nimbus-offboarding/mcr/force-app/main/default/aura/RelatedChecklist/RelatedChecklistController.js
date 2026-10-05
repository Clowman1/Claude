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
        helper.toggleEdit(component, event.target.dataset.item);
    },
    updateField : function(component,event,helper){
        helper.submitForm(component);
    },
    saveComplete : function(component,event,helper){
        let error = event.getParams();
        console.log("Error : " + JSON.stringify(error));
        let errorMessage = event.getParam("detail");
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

    }

})