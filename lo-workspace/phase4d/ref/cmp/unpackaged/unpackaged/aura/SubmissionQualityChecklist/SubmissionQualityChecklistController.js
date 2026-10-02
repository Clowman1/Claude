({
    doInit: function (component, event, helper) {
        component.set("v.answers", {}); // ensure it's an object

        helper.loadQuestions(component);
    },
    
    onUserLoaded: function (component, event, helper) {
        const user = component.get("v.userRecord");
		let profileId = user.fields.ProfileId.value;
        if (!profileId) {
            alert("ProfileId not loaded", user);
            return;
        }
        //alert(profileId);
        // Replace this with the actual ProfileId of your Loan Officer profile
        const LOAN_OFFICER_PROFILE_ID_1 = '00ef2000001wwBCAAY';
        const LOAN_OFFICER_PROFILE_ID_2 = '00ef200000253bwAAA';
        
        if (profileId === LOAN_OFFICER_PROFILE_ID_1 || profileId === LOAN_OFFICER_PROFILE_ID_2) {
            component.set("v.isReadOnly", true);
        }
    },

    handleAnswerClick: function (component, event, helper) {
        const field = event.currentTarget.dataset.field;
        const value = event.currentTarget.dataset.value;

        let answers = component.get("v.answers");
        try {
            answers[field] = value;
        } catch (e) {
            alert(e);
        }
        
        component.set("v.answers", answers);

        helper.highlightSelection(component);
        helper.calculateCounts(component);
    },

    saveChecklist: function (component, event, helper) {
        helper.saveChecklist(component);
    }
});