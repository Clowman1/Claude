({
    loadSnapshot : function(component) {
        var action = component.get('c.getApplicationSummary');
        action.setParams({ recordId: component.get('v.recordId') });
        action.setCallback(this, function(res) {
            if (res.getState() === 'SUCCESS') {
                var view = res.getReturnValue();
                component.set('v.sections', view.sections);
                component.set('v.capturedAt', view.capturedAt);
                component.set('v.hasSnapshot', view.hasSnapshot);
                component.set('v.activeSections', (view.sections || []).map(function(s) { return s.name; }));
            } else {
                var toast = $A.get('e.force:showToast');
                if (toast) {
                    toast.setParams({ type: 'error', message: 'Could not load the application summary.' });
                    toast.fire();
                }
            }
            component.set('v.isLoading', false);
        });
        $A.enqueueAction(action);
    }
})