({
    handleActivityChange: function (component, event) {
        var hasActivity = event.getParam('hasActivity');
        var pendingCount = event.getParam('pendingCount') || 0;
        var utilityBarAPI = component.find('utilityBarAPI');
        if (!utilityBarAPI) {
            return;
        }

        // Label carries the count so users see "Pending Review (3)" when there
        // is work to do, and just "Pending Review" when the queue is clear.
        var label = hasActivity
            ? 'Pending Review (' + pendingCount + ')'
            : 'Pending Review';

        utilityBarAPI.setUtilityLabel({ label: label })
            .catch(function () {
                // Non-fatal - label change is a UX nicety, not core behavior.
            });

        // setUtilityHighlighted is Aura-only (LWC's platformUtilityBarApi does
        // not expose it). It paints the utility with the platform highlight
        // styling (badge + prominent background), which is the native way to
        // call attention to a utility item.
        utilityBarAPI.setUtilityHighlighted({ highlighted: hasActivity })
            .catch(function () {
                // Non-fatal - if highlighting is unsupported in this context
                // the label change above still surfaces the activity.
            });
    }
})