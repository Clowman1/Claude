/**
 * Created by andrk on 11.11.2022.
 */

({
    doInit: function(component, event, helper) {
        helper.setFields(component);
        helper.setRecordType(component);
        helper.setObjectURLName(component);
        helper.getComponentContext(component);
    },
    successHandler: function(component, event, helper) {
        helper.successHelper(component, event);
    },
    errorHandler: function(component, event, helper) {
        helper.errorHelper(component, event);
    },
    submitHandler: function(component, event, helper) {
        helper.submitHelper(component, event);
    },
    closeModalHandler: function(component, event, helper) {
        helper.closeModalHelper(component);
    },
});