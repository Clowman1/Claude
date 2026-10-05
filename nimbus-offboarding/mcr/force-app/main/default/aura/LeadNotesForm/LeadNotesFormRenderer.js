({
    // Saving is explicit now. The old renderer wrote the whole form back to Lead_Notes_JSON__c on
    // close, which would overwrite the notes captured by the previous version of this form.
    unrender: function (component) {
        this.superUnrender();
    }
})