({
    getChecklistItems : function(component) {
        const dates = (a,b)=>{
            if(a.completedDate && !b.completedDate){
                return 1;
            }else if(b.completedDate && !a.completedDate){
                return -1;
            }else{
                return new Date(a.completedDate) > new Date(b.completedDate);
            }
        }
        const getChecklist_ACTION = component.get('c.getChecklist');
        getChecklist_ACTION.setParams({
            fields : component.get('v.fields'),
            recordId : component.get('v.recordId')
        });
        getChecklist_ACTION.setCallback(this, function(res){
            if(res.getState() === 'SUCCESS'){
                const checklist = res.getReturnValue();
                let canSort = component.get('v.autoSort');
                if(canSort == true){
                    checklist.items.sort(dates);
                }
                component.set('v.checklist',checklist);
                component.set('v.isLoading', false);
            }
        })
        $A.enqueueAction(getChecklist_ACTION);
    },
    updateField : function(component, apiName){
        const updateField_ACTION = component.get('c.updateRecord');
        updateField_ACTION.setParams({
            field : apiName,
            recordId : component.get('v.recordId')
        });
        updateField_ACTION.setCallback(this, function(res){
            if(res.getReturnValue().success){
                this.getChecklistItems(component);
            }else{
                this.showToastMessage(res.getReturnValue().message);
            }
        })
        $A.enqueueAction(updateField_ACTION);
    },
    showToastMessage : function (errorMsg) {
        const toastEvent = $A.get("e.force:showToast");
        toastEvent.setParams({
            mode: 'dismissible',
            type : errorMsg ? 'error': 'error',
            message: errorMsg ? errorMsg : 'We had trouble saving this field. Please notify an Admin.',
            title : errorMsg ? 'Uh oh..' : 'Saved Checklist Succesfully'
        });
        toastEvent.fire();
    },
    toggleEdit : function(component, apiName){
        let checklist = component.get('v.checklist');
        var today = new Date().toISOString();
        for(let item of checklist.items){
            item.isEdit = item.apiName === apiName ? true : false;
            if(item.isEdit && item.completedDate === undefined){
                component.set('v.spinner', true);
                item.completedDate = true;
            }
            if(item.isEdit && item.modifiedValue === undefined){
                item.modifiedValue = today;
            }
        }
        component.set('v.checklist', checklist);
        window.setTimeout(
            $A.getCallback(function() {
                component.find('recordLoader').submit();
            }), 1000
        );

    },
    submitForm : function(component){
        component.find('recordLoader').submit();
    }
})