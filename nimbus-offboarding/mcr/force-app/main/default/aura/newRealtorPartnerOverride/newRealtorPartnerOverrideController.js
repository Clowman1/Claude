({
    handleSubmit: function(component, event) {
        event.preventDefault();
        component.set('v.isSaving', true);
        component.set('v.showDuplicateModal', false);

        var fields = event.getParam('fields');
        fields.RecordTypeId = '012f20000010aScAAI';
        fields.Type__c = 'Realtor Account';
        fields.Group__pc = 'Realtor';
        fields.Is_Realtor__c = true;
        if (fields.PersonMobilePhone && !fields.Phone) {
            fields.Phone = fields.PersonMobilePhone;
        }

        // This form saves through lightning:recordEditForm, which goes to the UI API and never
        // reaches the Apex create methods, so the server-side hard stop cannot see it. The check
        // has to happen here, before submit, or this button stays the one unguarded way to
        // create a duplicate Realtor Partner.
        var check = component.get('c.findMatches');
        check.setParams({
            email: fields.PersonEmail,
            phone: fields.PersonMobilePhone,
            accountIdToSkip: null
        });
        check.setCallback(this, function(response) {
            if (response.getState() !== 'SUCCESS') {
                component.set('v.isSaving', false);
                var errToast = $A.get('e.force:showToast');
                errToast.setParams({
                    title: 'Could not check for duplicates',
                    message: 'The duplicate check did not run, so the account was not created. Try again.',
                    type: 'error'
                });
                errToast.fire();
                return;
            }
            var matches = response.getReturnValue() || [];
            if (matches.length > 0) {
                component.set('v.duplicateMatches', matches);
                component.set('v.phoneOnlyMatch', matches.every(function(m) {
                    return m.matchedOn === 'Phone';
                }));
                component.set('v.showDuplicateModal', true);
                component.set('v.isSaving', false);
                return;
            }
            component.find('realtorForm').submit(fields);
        });
        $A.enqueueAction(check);
    },

    useExistingAccount: function(component, event) {
        var recordId = event.getSource().get('v.value');
        component.set('v.showDuplicateModal', false);
        var nav = $A.get('e.force:navigateToSObject');
        nav.setParams({ recordId: recordId });
        nav.fire();
    },

    closeDuplicateModal: function(component) {
        component.set('v.showDuplicateModal', false);
        component.set('v.duplicateMatches', []);
    },

    handleSuccess: function(component, event) {
        component.set('v.isSaving', false);
        var toast = $A.get('e.force:showToast');
        toast.setParams({
            title: 'Realtor Partner created',
            message: 'The new Realtor Partner account is ready.',
            type: 'success'
        });
        toast.fire();

        var nav = $A.get('e.force:navigateToSObject');
        nav.setParams({ recordId: event.getParam('response').id });
        nav.fire();
    },

    handleError: function(component) {
        component.set('v.isSaving', false);
    },

    cancel: function() {
        var nav = $A.get('e.force:navigateToObjectHome');
        nav.setParams({ scope: 'Account' });
        nav.fire();
    }
});