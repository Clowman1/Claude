({
    handleInit : function(component, event, helper) {
        let action = component.get("c.getEmailTemplates");
        
        action.setCallback(this, function(response) {
            try {
                var state = response.getState();
                if (state === "SUCCESS") {
                    let emailTemplatesByFolder = response.getReturnValue();

                    let folders = [];
                    for (let folder of emailTemplatesByFolder) {
                        folders.push(folder.folderName);
                    }
                    
                    component.set("v.folders", folders);
                    component.set("v.emailTemplatesByFolder", emailTemplatesByFolder);
                    
                    let emailTemplates = [];
                    for (const folder of emailTemplatesByFolder) {
                        emailTemplates.concat(folder.emailTemplates);
                    }
					component.set("v.emailTemplates", emailTemplatesByFolder.find((f) => f.folderName === folders[0]).emailTemplates);
                } else if (state === "ERROR") {
                    component.set("v.htmlBody", '<center>Preview not available</center>');
                }
            } catch (e) {
                console.log(e.message);
            }
        });
        
        $A.enqueueAction(action);
    },
    
    handleRecordUpdated: function(component, event, helper) {
      	var changeType = event.getParams().changeType;
        if (changeType === "LOADED") {
			console.log("Loaded");
            
        } else if (changeType === "ERROR") {
            alert('Error fetching Title Closer Email');
        }
    },

    handleFolderChange : function(component, event, helper) {
        try {
            let folderName = component.get("v.selectedFolderName");
            let emailTemplatesByFolder = component.get("v.emailTemplatesByFolder");
            component.set("v.emailTemplates", emailTemplatesByFolder.find((f) => f.folderName === folderName).emailTemplates);
        } catch (e) {
            console.log(e.message);
        }
	},
    
    /*handleEmailSelect : function(component, event, helper) {
        
        
        let action = component.get("c.getRenderedHtmlTemplate");
        component.set("v.isLoading", true);
        
        let emailTemplateId = component.get("v.selectedEmailTemplateId");
        if (!emailTemplateId) {
            component.set("v.subject", null);
            component.set("v.htmlBody", null);
            component.set("v.isLoading", false);
            return;
        }
        
        action.setParams({
            emailTemplateId: component.get("v.selectedEmailTemplateId"),
            recordId: component.get("v.recordId"),
        });
        action.setCallback(this, function(response) {
            try {
                let state = response.getState();
                if (state === "SUCCESS") {
                    let emailTemplate = response.getReturnValue();
                    component.set("v.subject", emailTemplate.subject);
                    component.set("v.htmlBody", emailTemplate.htmlBody);
                    helper.replaceLinks(component);
                } else if (state === "ERROR") {
                    console.log(e.message);
                }
            } catch (e) {
                console.log(e.message);
            }
            component.set("v.isLoading", false);
        });
        
        $A.enqueueAction(action);

    },*/
    
    handleEmailSelect : function(component, event, helper) {
        let emailTemplateId = component.get("v.selectedEmailTemplateId");
        component.set("v.isLoading", true);
        
        if (!emailTemplateId) {
            component.set("v.subject", null);
            component.set("v.htmlBody", null);
            component.set("v.additionalEmails", null);
            component.set("v.isLoading", false);
            return;
        }
        
        // ===== NEW LOGIC START =====
        let templates = component.get("v.emailTemplates") || [];
        let selectedTemplate = templates.find(t => t.Id === emailTemplateId);
        
        let additionalEmails = [];
        
        if (selectedTemplate && selectedTemplate.Name) {
            let name = selectedTemplate.Name;
            
            if (
                name.includes('Package Delivery') ||
                name.includes('Balancing Request')
            ) {
                let record = component.get("v.record");
                
                if (record) {
                    if (record.Buying_Agent_TC_Email__c) {
                        additionalEmails.push(record.Buying_Agent_TC_Email__c);
                    }
                    if (record.Realtor_Buying_Agent_Email__c) {
                        additionalEmails.push(record.Realtor_Buying_Agent_Email__c);
                    }
                }
            }
        }
        
        component.set(
            "v.additionalEmails",
            additionalEmails.join(',')
        );
        // ===== NEW LOGIC END =====
        
        let action = component.get("c.getRenderedHtmlTemplate");
        action.setParams({
            emailTemplateId: emailTemplateId,
            recordId: component.get("v.recordId")
        });
        
        action.setCallback(this, function(response) {
            try {
                let state = response.getState();
                if (state === "SUCCESS") {
                    let emailTemplate = response.getReturnValue();
                    component.set("v.subject", emailTemplate.subject);
                    component.set("v.htmlBody", emailTemplate.htmlBody);
                    helper.replaceLinks(component);
                }
            } catch (e) {
                console.log(e.message);
            }
            component.set("v.isLoading", false);
        });
        
        $A.enqueueAction(action);
    },

    
    handleEmailSend: function(component, event, helper) {
        try {
            let action = component.get("c.sendEmail");
            component.set("v.isLoading", true);
            let sendToLead = component.get("v.sendToLead");
            
            let email = sendToLead ? component.get("v.record").Title_Closer_Email__c : null;
            console.log(email);
            
            action.setParams({
                recordId: component.get("v.recordId"),
                email: email,
                additionalEmails: component.get("v.additionalEmails"),
                subject: component.get("v.subject"),
                htmlBody: component.get("v.htmlBody")
            });
            action.setCallback(this, function(response) {
                try {
                    let state = response.getState();
                    if (state === "SUCCESS") {
                        let toastEvent = $A.get("e.force:showToast");
                        toastEvent.setParams({
                            "title": "Success!",
                            "message": 'Email has been sent',
                            "type": "success",
                        });
                        toastEvent.fire();
                        $A.get("e.force:closeQuickAction").fire();
                    } else if (state === "ERROR") {
                        let toastEvent = $A.get("e.force:showToast");
                        toastEvent.setParams({
                            "title": "Error!",
                            "message": 'Email has not been sent',
                            "type": "error",
                        });
                        toastEvent.fire();
                    }
                } catch (e) {
                    console.log(e.message);
                }
                component.set("v.isLoading", false);
            });
            
            $A.enqueueAction(action); 
        } catch (e) {
            console.log(e.message);
        }
    },
})