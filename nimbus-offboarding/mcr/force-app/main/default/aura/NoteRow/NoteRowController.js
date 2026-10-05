/**
 * Created by toma on 9/14/2021.
 */

({
    showNoteBody : function(c,e,h){
        c.set('v.isExpanded',!c.get('v.isExpanded'));
    },
    editNote: function(component, evt, helper) {
        let record = component.get('v.filteredNotes');  
       
        window.open('/apex/AddNewNote?noteId='+record.Id,'Enhanced Notes','resizable,height=575,width=445');
       
    }
});