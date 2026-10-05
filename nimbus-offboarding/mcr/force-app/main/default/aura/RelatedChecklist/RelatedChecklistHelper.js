/**
 * Created by Akram on 10/8/2020.
 */

({
    getChecklistItems : function(component) {
        const getChecklist_ACTION = component.get('c.getChecklist');
        getChecklist_ACTION.setParams({
            configurationId : component.get('v.configuration'),
            recordId : component.get('v.recordId')
        });
        getChecklist_ACTION.setCallback(this, function(res){
            if(res.getState() === 'SUCCESS'){
                const checklist = res.getReturnValue();
                let currentCheckListCount = [];
                const filledItemsCount= Object.keys(checklist.record).length - 1;
                for(let i = 0; i < checklist.items.length; i++) {
                    if(checklist.items[i].isVisible = true);
                    currentCheckListCount.push(checklist.items[i]);
                }
                let percentage = Math.round(filledItemsCount / currentCheckListCount.length * 100);
                component.set('v.checkListCount', percentage);
                component.set('v.checklist',checklist);
                component.set('v.isLoading', false);
            }
        })
        $A.enqueueAction(getChecklist_ACTION);
    },
    toggleEdit : function(component, apiName){
        let checklist = component.get('v.checklist');
        for(let item of checklist.items){
            item.isEdit = item.fieldName === apiName ? true : false;          
        }
        component.set('v.checklist', checklist);
    },
    submitForm : function(component){ 
		component.set('v.isLoading', true);
        component.find('recordLoader').submit();
    },
    showToast : function(message) {
        let toastEvent = $A.get("e.force:showToast");
        toastEvent.setParams({
            "title": "Error",
            "type": "error",
            "message": message
        });
        toastEvent.fire();
    }
})