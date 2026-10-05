({
    sendForms : function(component) {
        var action = component.get("c.runBatch");
        
        action.setCallback(this, function(response) {
            var state = response.getState();
            if (state === "SUCCESS") {
                alert("Forms have been sent successfully.");
                component.set("v.isModalOpen", false);
            }
            else if (state === "ERROR") {
                var errors = response.getError();
                var message = "Unknown error"; // Default error message
                if (errors && Array.isArray(errors) && errors.length > 0) {
                    message = errors[0].message;
                }
                // Можна додати сповіщення про помилку
                alert("Error: " + message);
            }
        });
        
        $A.enqueueAction(action);
    }
})