({
    toggleSidebar : function(component, event, helper) {
        $A.util.toggleClass(component.find('sidebar'), 'ncs_small_sidebar');
        $A.util.toggleClass(component.find('leftSide'), 'ncs_width');
    }
})