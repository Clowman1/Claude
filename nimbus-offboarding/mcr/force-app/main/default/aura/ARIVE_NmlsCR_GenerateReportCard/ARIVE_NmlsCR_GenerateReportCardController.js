/**
 * Created by Zeyad Jabra on 8/17/2019.
 */
({
    doInit : function(c, e, h){
        debugger;
        let action = c.get('c.getStateLicenses');
        action.setCallback(this,(res)=>{
            if(res.getState()==='SUCCESS'){
                let report = c.get('v.report');
                report.states = res.getReturnValue();
                c.set('v.report', report);
            }else{
                h.throwError('Not Able To Load State Licenses for Brokerage. Please Contact Support');
            }
        });
        $A.enqueueAction(action);
    },
    generateReportData : function(c,e,h){
        debugger;
        c.set('v.isLoading', true);
        let report = c.get('v.report'), action = c.get('c.generateReport');
        action.setParams({ quarter : report.quarter, year : report.year, states : h.getSelectedStates(report.states)});
        action.setCallback(this,(res)=>{
            if(res.getState()==='SUCCESS'){
                h.setReportModel(res.getReturnValue(), c);
            }else{
                h.throwError('Not able to generate report. Please Contact Support');
            }
        });
        $A.enqueueAction(action);
    }
})