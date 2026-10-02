/**
 * Created by andrk on 11.11.2022.
 */

({
    OBJECT_FIELDS:
        [
            {fieldName: 'Loan_Number__c', customLabel: true, label: 'Investor Loan Number', isRequired: true},
            {fieldName: 'Lender_lookup__c', customLabel: true, label: 'Investor' },
            {fieldName: 'Borrower_First_Name__c', isRequired: true},
            {fieldName: 'Borrower_Last_Name__c', isRequired: true},
            {fieldName: 'Borr_Email__c', isRequired: true},
            {fieldName: 'Borrower_Home_Phone__c', customLabel: true, label: 'Borrower Cell Phone', isRequired: true},
            {fieldName: 'AriveId__c', isRequired: true},
            {fieldName: 'Loan_Officer__c', isRequired: true},
            {fieldName: 'Transaction_Owner__c', isRequired: true},
        ],
    LE_CONTEXT: 'lightning.force',
    EB_OBJECT_URL_NAME: 'transaction',
    timerId: '',
    setFields: function (component) {
        try {
            component.set("v.fields", this.OBJECT_FIELDS);
        } catch (e) {
            console.log('error in setting fields', e);
        }
    },
    setRecordType: function (component) {
        try {
            const recordTypeId = component.get("v.pageReference").state['recordTypeId'];
    		console.log(recordTypeId);
            //console.log('page reference', recordTypeId);
            component.set("v.selectedRecordTypeId", recordTypeId);
        } catch (e) {
            console.log('error in setting record type', e);
        }
    },
    setObjectURLName: function (component) {
        try {
            component.set("v.objectURLName", this.EB_OBJECT_URL_NAME);
        } catch (e) {
            console.log('error in setting object URL name', e);
        }
    },
    successHelper: function (component, event) {
        try {
            const objectURLName = component.get("v.objectURLName");
            const isEB = component.get("v.isEB");
            const record = event.getParam("response");
            const recordId = record.id;
            component.set("v.loading", false);
            if (recordId) {
                if (isEB) {
                    this.navigateToInternalPage(`/${objectURLName}/${recordId}`);
                } else {
                    this.navigateToInternalPage(`/${recordId}`);
                }
            }
            //console.log('record id', recordId)
        } catch (e) {
            console.log('error in success helper', e);
        }
    },
    errorHelper: function (component, event) {
        try {
            component.set("v.loading", false);
        } catch (e) {
            console.log('error in error helper', e);
        }
    },
    submitHelper: function (component, event) {
        try {
            event.preventDefault();
            component.set("v.loading", true);
            this.debounce(() => {
                const fields = event.getParam('fields');
                component.find('recordEditForm').submit(fields);
            }, 2000);
        } catch (e) {
            console.log('error in submit helper', e);
        }
    },
    navigateToInternalPage: function(url) {
        const urlEvent = $A.get("e.force:navigateToURL");
        urlEvent.setParams({
            url
        });
        urlEvent.fire();
    },
    getBaseUrl: function() {
        try {
            return window.location.hostname;
        } catch (e) {
            console.log('error in getting base url', e);
        }
        return null;
    },
    getComponentContext: function (component, event) {
        try {
            const baseUrl = this.getBaseUrl(component);
            if (baseUrl) {
                if (!baseUrl.includes(this.LE_CONTEXT)) {
                    component.set("v.isEB", true);
                }
            }
        } catch (e) {
            console.log('error in getting component context', e);
        }
    },
    closeModalHelper: function(component) {
        try {
            component.set("v.showModal", false);
        } catch(e) {
            console.log('error in close modal', e);
        }
    },
    debounce: function(fn, wait) {
        clearTimeout(this.timerId);
        this.timerId = setTimeout(fn, wait);
    },
});