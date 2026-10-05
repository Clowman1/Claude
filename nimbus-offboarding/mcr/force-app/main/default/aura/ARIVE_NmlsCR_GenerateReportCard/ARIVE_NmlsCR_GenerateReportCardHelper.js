/**
 * Created by Zeyad Jabra on 8/17/2019.
 */
({
    setReportModel : function(report, component){
        console.log(report);
        component.set('v.report', report);
        component.set('v.step', 1);
        component.set('v.isLoading', false);
    },
    getSelectedStates : function(stateCheckboxes){
        let activeStates = stateCheckboxes.filter(state => state.value);
        let states = [];
        for(let state of activeStates){
            states.push(state.name);
        }
        return states;
    },
    throwError : function(errorMessage){
        alert(errorMessage);
    }
})