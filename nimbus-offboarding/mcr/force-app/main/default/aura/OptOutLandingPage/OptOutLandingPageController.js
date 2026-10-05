({
    doInit : function(component, event, helper) {
		const sPageURL = window.location.search.substring(1);
		const params = decodeURIComponent(sPageURL);
		const splittedEmail = params.split('=');
		if (splittedEmail[1]) {
			component.set('v.isError', true);
		}

		let action = component.get('c.handleOptOut');
		action.setParams({email: splittedEmail[1]});
		action.setCallback(this, function(response){
			try {
				const state = response.getState();
				let resultIndicatorClass;
			
				if (state === "SUCCESS") {
					component.set('v.resultMessage', 'Thank you for notifying us of your preferences.');
					resultIndicatorClass = 'slds-theme_info';
					component.set('v.isError', false);
				} else if (state === "ERROR") {
					resultIndicatorClass = 'slds-theme_error';
					component.set('v.resultMessage', 'There was an issue updating your opt out. Please contact the company directly.');
					component.set('v.isError', true);

					const errors = response.getError();
					if (errors) {
						if (errors.length && errors[0].message) {
							console.log("Error message: " + errors[0].message);
							console.log("Error message: ", errors[0]);
						}
					} else {
						console.log("Unknown error");
					}
				}

				const alertDiv = component.find('alertDiv');
				$A.util.addClass(alertDiv, resultIndicatorClass);
			} catch(e) {
				console.log('exception on opt out callback');
				console.log(e);
				console.log(e.message);
				console.log(e.stack);
			}
		});
		$A.enqueueAction(action);
    }
})