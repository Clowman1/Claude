({
    showMessage : function(component, event, helper) {
        var overlayLib = component.find("overlayLib");
        overlayLib.showCustomModal({
            header: "Action Not Allowed",
            body: "Change of Circumstance cannot be created directly. Use COC Request button on Transaction to properly create Change of Circumstance and Case related to it.",
            footer: "",
            showCloseButton: true
        });
    }
})