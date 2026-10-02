/**
 * Created by Akram on 10/8/2020.
 */

({
    BPS_FIELD_API_NAME : 'BPS__c',
    getChecklistItems : function(component) {
        const getChecklist_ACTION = component.get('c.getChecklist');
        getChecklist_ACTION.setParams({
            configurationId : component.get('v.configuration'),
            recordId : component.get('v.recordId'),
            fieldToTraverseOver : component.get('v.fieldToQueryFor')
        });
        getChecklist_ACTION.setCallback(this, function(res){
            if(res.getState() == 'SUCCESS'){
                const checklist = res.getReturnValue();
				if(component.get('v.fieldToQueryFor')){
					component.set('v.formRecordId',checklist.record.Id);
				}else{
					component.set('v.formRecordId',component.get('v.recordId'));
				}
                console.log(checklist);
                let currentCheckListFields = [];
                //const record= Object.keys(checklist.record);
                //const filterId = record.filter(x => x !== 'Id');
                //const filledItems = filterId.filter(x => checklist.record[x])
                /*for(let i = 0; i < checklist.items.length; i++) {
                    if(checklist.items[i].isVisible == true){
                        currentCheckListFields.push(checklist.items[i].fieldName);
                    }
                }*/
                
                const filledItems = [];
                for (const item of checklist.items) {
                    if (item.fieldName in checklist.record && item.fieldName !== 'Id' && item.isVisible === true) {
                        if (checklist.record[item.fieldName]) { // not falsy: 0, '', false
                            filledItems.push(item);
                        }
                    }
                }
                
                for(let i = 0; i < checklist.items.length; i++) {
                    if(checklist.items[i].isVisible == true){
                        currentCheckListFields.push(checklist.items[i].fieldName);
                    }
                }
                const percentage = Math.round(filledItems.length/ currentCheckListFields.length * 100);
                component.set('v.checkListCount', percentage);
                component.set('v.checklist',checklist);
                component.set('v.isLoading', false);
            }
        })
        $A.enqueueAction(getChecklist_ACTION);
    },
    toggleEdit : function(component, apiName) {
        let checklist = component.get('v.checklist');
        for (let item of checklist.items) {
            item.isEdit = item.fieldName == apiName ? true : false;
        }
        component.set('v.checklist', checklist);
    },
    toggleEditDate : function(component, apiName){
        let checklist = component.get('v.checklist');
        var today = new Date().toISOString();
        for(let item of checklist.items){
            item.isEdit = item.fieldName == apiName ? true : false;
            if(item.isEdit && item.completedDate == undefined){
                component.set('v.spinner', true);
                item.completedDate = true;
            }
            if(item.isEdit && item.modifiedValue == undefined){
                item.modifiedValue = today;
            }
        }
        component.set('v.checklist', checklist);
        component.set('v.lastSavedFieldApiName', apiName);
        component.set('v.pendingBpsSave', apiName === this.BPS_FIELD_API_NAME);
        window.setTimeout(
            $A.getCallback(function() {
                component.find('recordLoader').submit();
            }), 1000
        );
		
    },
    submitForm : function(component, fieldApiName){ 
        const resolvedFieldApiName = fieldApiName || this.getEditedFieldApiName(component);
        component.set('v.lastSavedFieldApiName', resolvedFieldApiName);
        component.set('v.pendingBpsSave', resolvedFieldApiName === this.BPS_FIELD_API_NAME);
		component.set('v.isLoading', true);
        component.find('recordLoader').submit();
    },
    getEditedFieldApiName : function(component) {
        const checklist = component.get('v.checklist');
        if (!checklist || !checklist.items) {
            return null;
        }
        for (let item of checklist.items) {
            if (item.isEdit) {
                return item.fieldName;
            }
        }
        return null;
    },
    handleBpsSaveSuccess : function(component) {
        const action = component.get('c.getBpsVerificationContext');
        action.setParams({
            transactionId: component.get('v.formRecordId')
        });
        action.setCallback(this, function(res) {
            component.set('v.isLoading', false);
            component.set('v.pendingBpsSave', false);
            if (res.getState() === 'SUCCESS') {
                const verificationContext = res.getReturnValue();
                if (verificationContext && verificationContext.shouldShowModal) {
                    this.resetBpsVerificationForPendingConfirmation(component, verificationContext);
                    return;
                }
                this.persistBpsVerification(component, false, true);
                return;
            }

            this.showToast(this.getErrorMessage(res.getError()));
            $A.get('e.force:refreshView').fire();
        });
        $A.enqueueAction(action);
    },
    resetBpsVerificationForPendingConfirmation : function(component, verificationContext) {
        const action = component.get('c.saveBpsVerification');
        action.setParams({
            transactionId: component.get('v.formRecordId'),
            isVerified: false
        });
        action.setCallback(this, function(res) {
            if (res.getState() === 'SUCCESS') {
                component.set('v.bpsVerificationBpsValue', verificationContext.bpsValue);
                component.set('v.bpsVerificationLoanNumber', verificationContext.loanNumber);
                component.set('v.bpsVerificationBorrowerName', verificationContext.borrowerName);
                component.set('v.isBpsVerificationChecked', false);
                component.set('v.showBpsVerificationModal', true);
                return;
            }

            this.showToast(this.getErrorMessage(res.getError()));
            $A.get('e.force:refreshView').fire();
        });
        $A.enqueueAction(action);
    },
    persistBpsVerification : function(component, isVerified, shouldRefreshView) {
        component.set('v.isSavingBpsVerification', true);
        const action = component.get('c.saveBpsVerification');
        action.setParams({
            transactionId: component.get('v.formRecordId'),
            isVerified: isVerified
        });
        action.setCallback(this, function(res) {
            component.set('v.isSavingBpsVerification', false);
            if (res.getState() === 'SUCCESS') {
                component.set('v.showBpsVerificationModal', false);
                component.set('v.isBpsVerificationChecked', false);
                if (shouldRefreshView !== false) {
                    $A.get('e.force:refreshView').fire();
                }
                return;
            }

            this.showToast(this.getErrorMessage(res.getError()));
        });
        $A.enqueueAction(action);
    },
    getErrorMessage : function(errors) {
        if (!errors || !errors.length) {
            return 'An unexpected error occurred.';
        }
        const firstError = errors[0];
        if (firstError.message) {
            return firstError.message;
        }
        if (firstError.pageErrors && firstError.pageErrors.length) {
            return firstError.pageErrors[0].message;
        }
        return 'An unexpected error occurred.';
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