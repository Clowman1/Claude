({
    MAX_FILE_SIZE: 4500000, //Max file size 4.5 MB 
    handleFileUpload : function(component, files, index) {
        let file = files[index];
        
        if (file.size > this.MAX_FILE_SIZE) {
            alert('Alert : File size cannot exceed ' + this.MAX_FILE_SIZE + ' bytes.\n' + ' Selected file ' + file.name + ' size: ' + file.size);
            component.set("v.isLoading", false);
            return;
        }
        
        let objFileReader = new FileReader();
        objFileReader.onload = $A.getCallback(() => {
            try {
                let fileContents = objFileReader.result;
                let base64 = 'base64,';
                let dataStart = fileContents.indexOf(base64) + base64.length;
                
                fileContents = fileContents.substring(dataStart);
                
                let action = component.get("c.uploadFile");
                action.setParams({ 
                    recordId: component.get("v.recordId"), 
                    filename: file.name, 
                    filetype: file.type, 
                    base64Data: fileContents 
                });
    
                action.setCallback(this, function(response) {
                    let state = response.getState();
                    console.log(state, files.length, index);
                    if (state === "SUCCESS") {
                        if (index === files.length - 1) {
                            let fileNames = component.get("v.fileNames");
                            fileNames.push(file.name);
                            component.set("v.fileNames", fileNames);
                            
                            component.set("v.isLoading", false);
                            component.set("v.successStatus", "Files were successfully uploaded");
                            this.notifyViaEmail(component);
                        } else {
                            this.handleFileUpload(component, files, index + 1);
                        }
                    } else {
                        let errors = response.getError();
                        if (errors) {
                            if (errors[0] && errors[0].message) {
                                alert("Error message: " + errors[0].message);  
                            }
                        } else {
                            alert("Unknown error");
                        }
                    }
                });
                $A.enqueueAction(action);
            } catch (e) {
                console.log(e.message)
            }
            
        });
        
        objFileReader.readAsDataURL(file); 
	},
    
    notifyViaEmail : function(component) {
        var action = component.get("c.sendEmail"); //postclosing@reachhomeloans.com
        action.setParams({ recordId: component.get("v.recordId"), fileNames: component.get("v.fileNames"), targetEmail: 'postclosing@reachhomeloans.com' });

        action.setCallback(this, function(response) {
            var state = response.getState();
            if (state === "SUCCESS") {
                console.log("SUCCESS");
            }
            else if (state === "ERROR") {
                var errors = response.getError();
                if (errors) {
                    if (errors[0] && errors[0].message) {
                        console.log("Error message: " + 
                                 errors[0].message);
                    }
                } else {
                    console.log("Unknown error");
                }
            }
        });

        $A.enqueueAction(action);
    }
})