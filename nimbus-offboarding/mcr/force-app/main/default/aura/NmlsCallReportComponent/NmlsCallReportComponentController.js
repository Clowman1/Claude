/**
 * Created by Zeyad Jabra on 8/16/2019.
 */
({
    doInit : function(component,event,helper){
        let action = component.get('c.retrievePastReports');
        action.setCallback(this, function(response){
            if(response.getState() == 'SUCCESS'){
                component.set('v.pastFiles', response.getReturnValue());
            }
        })
        $A.enqueueAction(action);
    },

    downloadDocument : function(component, event, helper){
        var profUrl = $A.get('$Resource.NMLSCallReportGuide');
        window.open(profUrl,'_blank' );
    }
})