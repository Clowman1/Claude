({
    loadQuestions: function (component) {
        const questionAction = component.get("c.getChecklistItems");
        const answersAction = component.get("c.getExistingChecklist");
        
        questionAction.setCallback(this, function (response) {
            if (response.getState() === "SUCCESS") {
                component.set("v.questions", response.getReturnValue());
                this.highlightSelection(component); // safe to call even if answers are empty
            }
        });
        
        answersAction.setParams({ transactionId: component.get("v.recordId") });
        answersAction.setCallback(this, function (response) {
            if (response.getState() === "SUCCESS") {
                const answers = response.getReturnValue();
                component.set("v.answers", answers);
                this.highlightSelection(component);
                this.calculateCounts(component);
            }
        });
        
        $A.enqueueAction(questionAction);
        $A.enqueueAction(answersAction);
    },

    calculateCounts: function (component) {
        const answers = component.get("v.answers");
        let yes = 0, no = 0;
        for (let key in answers) {
            if (answers[key] === 'Yes') yes++;
            else if (answers[key] === 'No') no++;
        }
        component.set("v.yesCount", yes);
        component.set("v.noCount", no);
    },

    highlightSelection: function (component) {
        // Reset classes
        let clickableEls = document.querySelectorAll('.clickable');
        let answers = component.get("v.answers") || {};

        clickableEls.forEach(el => {
            const field = el.dataset.field;
            const value = el.dataset.value;
            el.classList.remove("selected", "yes", "no", "na");

            if (answers[field] === value) {
                el.classList.add("selected");
                el.classList.add(value.toLowerCase());
            }
        });
    },

    saveChecklist: function (component) {
        const action = component.get("c.saveChecklistAnswers");
        action.setParams({
            transactionId: component.get("v.recordId"),
            answersMap: component.get("v.answers")
        });

        action.setCallback(this, function (response) {
            if (response.getState() === "SUCCESS") {
                $A.get('e.force:refreshView').fire();
                alert("Checklist saved successfully.");
            } else {
                console.error(response.getError());
                alert("Save failed.");
            }
        });

        $A.enqueueAction(action);
    }
});