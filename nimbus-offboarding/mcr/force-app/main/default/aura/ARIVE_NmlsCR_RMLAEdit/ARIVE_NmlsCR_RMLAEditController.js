/**
 * Created by Zeyad Jabra on 8/18/2019.
 */
({
    selectState : function(c,e,h){
        let state = e.currentTarget.dataset.state;
        let report = c.get('v.report');
        for(let s of report.stateData){
            if(s.stateCode == state){
                c.set('v.currentState', s);
                c.set('v.isOpen',true);
                return;
            }
        }
        alert('Error processing. Please contact support.');
    },
    toggleLock : function(c,e,h){
        c.set('v.isLocked', !c.get('v.isLocked'));
    },
    calculateAverage : function(c,e,h){
        debugger;
        let datapoint = e.getSource().getLocalId();
        if(datapoint != null){
            let currentState = c.get('v.currentState');
            let datapointProperties = datapoint.split('.');
            let baseProperty = datapointProperties[0];
            let numerator = datapointProperties[1] + '_1';
            let denominator = datapointProperties[1] + '_2';
            let average = datapointProperties[1] + '_SUM_1_2';
            if(currentState[baseProperty][denominator] > 0){
                currentState[baseProperty][average] = currentState[baseProperty][numerator]/currentState[baseProperty][denominator];
            }else if(currentState[baseProperty][numerator] > 0){
                currentState[baseProperty][average] = 'ERR';
            }
            else{
                currentState[baseProperty][average] = 0;
            }
            c.set('v.currentState', h.calculateSummaryRow(currentState, datapoint));
        }
    },
    calculateCorrAverage : function(c,e,h){
        debugger;
        let datapoint = e.getSource().getLocalId();
        if(datapoint != null){
            let currentState = c.get('v.currentState');
            let datapointProperties = datapoint.split('.');
            let baseProperty = datapointProperties[0];
            let corrNumerator = datapointProperties[1] + '_3';
            let corrDenominator = datapointProperties[1] + '_4';
            let corrAverage = datapointProperties[1] + '_SUM_3_4';
            if(currentState[baseProperty][corrDenominator] > 0){
                currentState[baseProperty][corrAverage] = currentState[baseProperty][corrNumerator]/currentState[baseProperty][corrDenominator];
            }else if(currentState[baseProperty][corrNumerator] > 0){
                currentState[baseProperty][corrAverage] = 'ERR';
            }
            else{
                currentState[baseProperty][corrAverage] = 0;
            }
            c.set('v.currentState', h.calculateSummaryRow(currentState, datapoint));
        }
    },
    getReportDetailTable : function(c,e,h){
        let report = c.get('v.report');
        let state = c.get('v.currentState');
        let action = c.get('c.viewDatapointDetails');
        let startDateProperties = report.startDate.split('-');
        let endDateProperties = report.endDate.split('-');
        action.setParams({'datapointName' : e.currentTarget.dataset.datapoint,
            'startDate' : startDateProperties[1] + '/' + startDateProperties[2] + '/' + startDateProperties[0],
            'endDate' : endDateProperties[1] + '/' + endDateProperties[2] + '/' + endDateProperties[0],
            'state' : state.stateCode});
        action.setCallback(this, (res)=>{
            if(res.getState() == 'SUCCESS'){
                debugger;
                console.log(res.getReturnValue());
                c.set('v.reportDetailTable', res.getReturnValue());
            }else{
                h.throwError('Could not get detail table, please contact support.');
            }
        });
        $A.enqueueAction(action);
    },
    downloadDetailCsv : function(c,e,h){
        h.downloadDetailCsv(c);
    },
    clearReportDetailTable : function(c,e,h){
        c.set('v.reportDetailTable', null);
    },
    closeStateReview : function(c,e,h){
        c.set('v.reportDetailTable', null);
        c.set('v.isOpen', false);
    },
    markStateComplete : function(c,e,h){
        let report = c.get('v.report');
        let currentState = c.get('v.currentState');
        let isComplete = true;
        for(let state of report.stateOptions){
            if(currentState.stateCode == state.stateCode){
                state.isComplete = true;
                c.set('v.report', report);
                c.set('v.isOpen', false);
            }
            if(!state.isComplete){
                isComplete = false;
            }
        }
        if(isComplete){
            c.set('v.step', 2);
        }
    },
    generateXml : function(c,e,h){
        debugger;
        c.set('v.step', 3);
        c.set('v.isGeneratingXml', true);
        let report = c.get('v.report');
        let action = c.get('c.generateXmlFile');
        action.setParams({
            jsonReport: JSON.stringify(report, (key, value) => {
            if (typeof value === 'number') {
            	return parseFloat(value.toFixed(6));
            } else if (typeof value === 'string' && key.includes('_')) {
            	return parseFloat(parseFloat(value).toFixed(6));
        	} else { 
                return value;
            }
        
    	 })
        });
                         
                         /*, (key, value) => {
                if (typeof value === 'number') {
                	return parseFloat(value.toFixed(6));
            	} else if (typeof value === 'string') {
            		return parseFloat(parseFloat(value).toFixed(6));
        		} else {
                         console.log(value);
                         console.log(typeof value);
                    return value;     
                } 
           })
        }*/
                         
        console.log(JSON.stringify(report));
        
        console.log(JSON.stringify(report, (key, value) => {
            if (typeof value === 'number') {
            	return parseFloat(value.toFixed(6));
            } else if (typeof value === 'string' && key.includes('_')) {
            	return parseFloat(parseFloat(value).toFixed(6));
        	} else { 
                return value;
            }
        
    	}));

        action.setCallback(this, (res)=>{
            if(res.getState()=='SUCCESS'){
                let response = res.getReturnValue();
                var link = document.createElement("a");
                link.href = "data:text/xml;base64,"+ response.file;
                link.download = 'RMLA Q'+c.get('v.report').quarter+' '+c.get('v.report').year+".xml";
                link.click();

                c.set('v.isGeneratingXml', false);
            }
        });
        $A.enqueueAction(action);
    },
    restartReport : function(c,e,h){
        c.set('v.showResetConfirmation', true);
    },
    confirmRestart : function(c,e,h){
        c.set('v.step', 0);
        c.set('v.showResetConfirmation', false);
    },
    cancelRestart : function(c,e,h){
        c.set('v.showResetConfirmation', false);
    },
   	navigateToLoan : function(c,e,h) {
    	let loanId = e.currentTarget.dataset.id
        console.log(loanId);
        window.open('/' + loanId,'_blank'); 
   	},
    generateResidentialFirstMortgagesReportData : function(c,e,h){
        debugger;
        c.set('v.spinner', true);
        let report = c.get('v.report');
        let ACTION = c.get('c.finishGenerateReport');
        ACTION.setParams({report: JSON.stringify(report)});
        ACTION.setCallback(this, function(response) {
            let state = response.getState();
            if (state === "SUCCESS") {
                c.set('v.report', response.getReturnValue());
                h.showToast('Success', 'Residential mortgages report generated successfully.', 'success')
                c.set('v.spinner', false);
            }
            else if (state === "INCOMPLETE") {
                console.log('incomplete');
            }
            else if (state === "ERROR") {
                let errors = response.getError();
                if (errors) {
                    c.set('v.spinner', false);
                    if (errors[0] && errors[0].message) {
                        console.log('error occurred: ' + errors[0].message);
                        h.showToast('Error', 'Error Generating Residential Mortgages Data. Please try again later.', 'error')
                    }
                }
            }
        });
        $A.enqueueAction(ACTION);
    }
})