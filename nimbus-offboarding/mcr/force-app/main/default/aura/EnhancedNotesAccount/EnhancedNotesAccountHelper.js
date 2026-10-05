/**
 * Created by toma on 10/14/2021.
 */

({
    initHelper: function(c,e,h){
        debugger;
        let recordId = c.get('v.recordId');
        let action = c.get('c.getNotesRelatedToLoan');
        let users = [];
        action.setParams({loanId:recordId});
        action.setCallback(this, function(res){
            if(res.getState() == 'SUCCESS'){
                let notes = res.getReturnValue();
                c.set('v.listOfNotes', notes);
                c.set('v.filteredNotes', notes);
                for(let note of notes){
                    if(!(users.includes(note.CreatedBy.Name))){
                        users.push(note.CreatedBy.Name);
                    }
                }
                c.set('v.listOfUsers', users);
                h.filter(c, e, h);
            }
        })
        $A.enqueueAction(action); 
    },

    filter : function(c,e,h){
        let filterCategory = c.get('v.filterCategory');
        let notes = c.get('v.listOfNotes');
        let searchText = c.get('v.searchText');
        let selectedUser = c.find('selectedUser').get('v.value');
        let filteredNotes = JSON.parse(JSON.stringify(notes));
        let selectedType = c.get('v.selectedTypeTab');
        //let showInbound = c.get('v.showInbound');
        //let showOutbound = c.get('v.showOutbound');

        if(searchText != null && searchText != ''){
            filteredNotes = filteredNotes.filter(x => (x.Body__c && x.Body__c.toLowerCase().includes(searchText.toLowerCase())) || false);
        }
        if(filterCategory.length){
            filteredNotes = filteredNotes.filter(x => filterCategory.includes(x.Enhanced_Note_Role__c) || false); 
        }
        if(selectedUser != null){
            filteredNotes = filteredNotes.filter(x => x.CreatedBy.Name.includes(selectedUser) || false);
        }
        if(selectedType != null){
            filteredNotes = filteredNotes.filter(x => (x.Type__c === selectedType || (!x.Type__c && selectedType === 'Note')));

            if (selectedType === 'Call' || selectedType === 'Text') {
                //filteredNotes = filteredNotes.filter(x => (showInbound && x.Direction__c === 'Inbound') || (showOutbound && x.Direction__c === 'Outbound'));
            }
        }
        c.set('v.filteredNotes', filteredNotes);
    },

    getApplicationNotes: function(notes) {
        return notes.filter(note => {
            if (note.Subject__c) {
                return note.Subject__c.toLowerCase().includes('application');
            }
            return false;
        });
    }
});