({
    doInit : function(component, event, helper) {
        helper.loadSummary(component);
    },

    // The checkbox is bound to v.hasCoBorrower, so the branches showing Borrower 2 react on their
    // own. Nothing is deleted when it is unticked; the text stays on the record until saved over.
    handleToggleCoBorrower : function(component, event, helper) {
        // no-op beyond the binding
    },

    handleToggleLegacy : function(component, event, helper) {
        component.set('v.showLegacy', !component.get('v.showLegacy'));
    },

    // aura:iteration does not reliably write back through var, so edits are captured by field name.
    handleBlockChange : function(component, event, helper) {
        var source = event.getSource();
        var edits = component.get('v.edits') || {};
        edits[source.get('v.name')] = source.get('v.value');
        component.set('v.edits', edits);
    },

    handleSave : function(component, event, helper) {
        helper.save(component, false);
    },

    handleSaveToNote : function(component, event, helper) {
        helper.save(component, true);
    },

    handleCancel : function(component, event, helper) {
        $A.get('e.force:closeQuickAction').fire();
    }
})