({
    doInit: function(cmp) {
        //console.log(cmp.get("v.recordId"));
        //var flow = cmp.find("flowData");
        //var inputVariables = [
        //    { name : "recordId", type : "String", value: cmp.get("v.recordId") },
        //];
        //flow.startFlow("Title_Confirmation_File_Upload", inputVariables);
    },
    handleFilesChange: function (component, event, helper) {
        component.set("v.isLoading", true);
        var uploadedFiles = event.getSource().get("v.files");
        
        try {
            helper.handleFileUpload(component, uploadedFiles, 0);
        } catch (e) {
            console.log(e.message);
        }
    }
})