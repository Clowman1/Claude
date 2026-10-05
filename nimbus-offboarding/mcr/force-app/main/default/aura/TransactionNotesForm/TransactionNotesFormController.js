({
    doInit : function(component, event, helper) {
        helper.loadSnapshot(component);
    },

    handleClose : function(component, event, helper) {
        $A.get('e.force:closeQuickAction').fire();
    }
})