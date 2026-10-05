({
    loadSummary : function(component) {
        var self = this;
        var action = component.get('c.getApplicationSummary');
        action.setParams({ recordId: component.get('v.recordId') });
        action.setCallback(this, function(res) {
            if (res.getState() === 'SUCCESS') {
                var view = res.getReturnValue();
                component.set('v.sections', view.sections);
                component.set('v.hasCoBorrower', view.hasCoBorrower);
                component.set('v.readOnly', view.readOnly);
                component.set('v.legacyNotes', view.legacyNotes);
                // Everything open by default: this is a summary to read, not a form to fill in.
                component.set('v.activeSections', (view.sections || []).map(function(s) { return s.name; }));
            } else {
                self.toast(component, 'error', 'Could not load the application summary.');
            }
            component.set('v.isLoading', false);
        });
        $A.enqueueAction(action);
    },

    // Flattens the sections into the shape the Apex expects, applying any edits made in the modal.
    // Co-borrower blocks are skipped when the toggle is off so an unticked box never writes back.
    collectBlocks : function(component) {
        var edits = component.get('v.edits') || {};
        var hasCoBorrower = component.get('v.hasCoBorrower');
        var collected = [];
        (component.get('v.sections') || []).forEach(function(section) {
            (section.blocks || []).forEach(function(block) {
                if (block.coBorrower && !hasCoBorrower) {
                    return;
                }
                collected.push({
                    field: block.field,
                    label: block.label,
                    sectionLabel: section.label,
                    value: edits.hasOwnProperty(block.field) ? edits[block.field] : block.value
                });
            });
        });
        return collected;
    },

    save : function(component, alsoCreateNote) {
        var self = this;
        var blocks = this.collectBlocks(component);
        component.set('v.isSaving', true);

        var action = component.get('c.saveApplicationSummary');
        action.setParams({
            recordId: component.get('v.recordId'),
            blocksJson: JSON.stringify(blocks)
        });
        action.setCallback(this, function(res) {
            if (res.getState() !== 'SUCCESS') {
                component.set('v.isSaving', false);
                self.toast(component, 'error', self.errorText(res, 'Could not save the application summary.'));
                return;
            }
            if (!alsoCreateNote) {
                component.set('v.isSaving', false);
                self.finish(component, 'Application summary saved.');
                return;
            }
            self.createNote(component, blocks);
        });
        $A.enqueueAction(action);
    },

    createNote : function(component, blocks) {
        var self = this;
        var action = component.get('c.createSummaryNote');
        action.setParams({
            recordId: component.get('v.recordId'),
            blocksJson: JSON.stringify(blocks)
        });
        action.setCallback(this, function(res) {
            component.set('v.isSaving', false);
            if (res.getState() === 'SUCCESS') {
                self.finish(component, 'Application summary saved and added to notes.');
            } else {
                // The summary itself already saved, so say so rather than implying nothing happened.
                self.toast(component, 'warning', 'Summary saved, but the note could not be created.');
            }
        });
        $A.enqueueAction(action);
    },

    finish : function(component, message) {
        this.toast(component, 'success', message);
        $A.get('e.force:refreshView').fire();
        $A.get('e.force:closeQuickAction').fire();
    },

    errorText : function(res, fallback) {
        var errors = res.getError();
        if (errors && errors[0] && errors[0].message) {
            return errors[0].message;
        }
        return fallback;
    },

    toast : function(component, type, message) {
        var toast = $A.get('e.force:showToast');
        if (!toast) {
            return;
        }
        toast.setParams({ type: type, message: message });
        toast.fire();
    }
})