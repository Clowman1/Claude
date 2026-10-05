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
    debug : function(component,event,helper){
        helper.showToastMessage(event.getParam('detail'));
    },
    fillValues : function(c,e,eh){
        let checklist = c.get("v.checklist");
        c.set('v.checklist', checklist);
    },
    toggleAllClosed : function(component,event,helper){

        let checklist = component.get('v.checklist');
        for(let item of checklist.items){
            item.isEdit = false;
        }
        component.set('v.checklist', checklist);
        component.set('v.spinner', false);
        event.stopPropagation();

    }
})