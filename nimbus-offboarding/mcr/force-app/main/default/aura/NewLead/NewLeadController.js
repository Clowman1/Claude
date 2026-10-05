({
	init : function (component) {
		// Find the component whose aura:id is “flowData”
		var flow = component.find("flowData");
		// In that component, start your flow. Reference the flow’s Unique Name.
		flow.startFlow("New_Lead_Screen_Flow");
	},
	statusChange : function (cmp, event) {
        if (event.getParam('status') === "FINISHED") {
			$A.get("e.force:closeQuickAction").fire();
        }
    }
})