({
    openModal : function(component, event, helper) {
        component.set("v.isModalOpen", true);
    },
    
    closeModal : function(component, event, helper) {
        component.set("v.isModalOpen", false);
    },
    
    confirmSend : function(component, event, helper) {
        helper.sendForms(component);
    }
})