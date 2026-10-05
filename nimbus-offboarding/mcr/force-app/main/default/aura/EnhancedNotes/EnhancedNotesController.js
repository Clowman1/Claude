/**
 * Created by J9 on 8/19/2021.
 */

({
    init : function(c,e,h){
        const channel = "/event/EnhancedNoteEvent__e"
        const empApi = c.find('empApi');
        // Uncomment below line to enable debug logging (optional)
         empApi.setDebugFlag(true);
        // Register error listener and pass in the error handler function
        empApi.onError($A.getCallback(error => {
            // Error can be any type of error (subscribe, unsubscribe...)
            console.error('EMP API error: ', JSON.stringify(error));
        }));
        // Replay option to get new events
        const replayId = -1;
        // Subscribe to an event
        empApi.subscribe(channel, replayId, $A.getCallback(eventReceived => {
            // Process event (this is called each time we receive an event)
            if(c.get("v.recordId")){
                h.initHelper(c,e,h);
            }
        })).then(subscription => {
            // Subscription response received.
            // We haven't received an event yet.
            console.log('Subscription request sent to: ', subscription.channel);
            // Save subscription to unsubscribe later
            // c.set('v.subscription', subscription);
        });
        h.initHelper(c,e,h);
    }, 
    filter : function(c,e,h){
        h.filter(c, e, h);
    },
    searchKeyDown : function(c,e,h){
        if(e.which == 13){
            h.filter(c, e, h);
        }
    },
    filterCategory : function(c,e,h){
        let selectedCategory = e.currentTarget.dataset.role;
        let isItemSelectClassIncluded = e.currentTarget.classList.value.indexOf('ncs-item-selected');
        if(isItemSelectClassIncluded > -1){
            e.currentTarget.classList.remove('ncs-item-selected'); 
        }
        else{
            e.currentTarget.classList.add('ncs-item-selected'); 
        }
        let filterCategory = c.get('v.filterCategory');
        if(filterCategory.includes(selectedCategory)){
            filterCategory.splice(filterCategory.indexOf(selectedCategory),1);
        }
        else{
            filterCategory.push(selectedCategory);
        }
        h.filter(c, e, h);
    },

    handleShowModal: function(component, evt, helper) {
        let id = component.get('v.recordId');
        window.open("/apex/AddNewNote?appId="+ id, 'Enhanced Notes', 'resizable,height=575,width=445');
    }
});