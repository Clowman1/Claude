/**
 * Created by c_zjabra on 12/16/2021.
 */

({
    /**
     * Description When the component loads it will try to clone the transaction.
     * @access      public
     * @yields      A toast message with a clickable link that takes the user to the cloned application.
     * @return      {void}      null.
     */
    init : function(c,e,h){
        let cloneTransaction = c.get('c.clone');
        cloneTransaction.setParams({model: 'Transaction', recordId: c.get('v.recordId')})
        cloneTransaction.setCallback(this, function(res){
            if(res.getState() == 'SUCCESS'){
				$A.get("e.force:closeQuickAction").fire();
			    h.showToast(c,e,h,res.getState(),res.getReturnValue());
            }else{
                let errors = res.getError();
                let errorMsg = errors[0].message;
				$A.get("e.force:closeQuickAction").fire();
                h.showToast(c,e,errorMsg,res.getState(),res.getReturnValue());
            }
        });
        $A.enqueueAction(cloneTransaction);
    }
});