import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getApplicationSummary from '@salesforce/apex/LeadNotesFormController.getApplicationSummary';
import saveApplicationSummary from '@salesforce/apex/LeadNotesFormController.saveApplicationSummary';
import createSummaryNote from '@salesforce/apex/LeadNotesFormController.createSummaryNote';

/**
 * LO Workspace "Application Summary" modal body. It is the Lead quick action Leads_Notes_Form
 * (Aura LeadNotesForm), which an LWC cannot embed: same Apex, same sections, same save rules,
 * only the markup is LWC. Change the two together. Fires `close` (Cancel, or after a save).
 */
export default class LoWsApplicationSummary extends LightningElement {
    @api recordId;
    sections = [];
    activeSections = [];
    hasCoBorrower = false;
    readOnly = false;
    legacyNotes;
    showLegacy = false;
    isLoading = true;
    isSaving = false;
    edits = {};

    connectedCallback() {
        this.load();
    }

    async load() {
        try {
            const view = await getApplicationSummary({ recordId: this.recordId });
            this.sections = view.sections || [];
            this.hasCoBorrower = view.hasCoBorrower === true;
            this.readOnly = view.readOnly === true;
            this.legacyNotes = view.legacyNotes;
            // Everything open by default: this is a summary to read, not a form to fill in.
            this.activeSections = this.sections.map((s) => s.name);
        } catch (e) {
            this.toast('error', 'Could not load the application summary.');
        } finally {
            this.isLoading = false;
        }
    }

    // Co-borrower blocks show only while the toggle is on; nothing is deleted when it is unticked.
    get visibleSections() {
        return this.sections.map((section) => ({
            ...section,
            showLabels: !section.single,
            blocks: (section.blocks || []).filter((b) => !b.coBorrower || this.hasCoBorrower)
        }));
    }

    get canSave() {
        return !this.readOnly && !this.isLoading;
    }

    get legacyToggleLabel() {
        return this.showLegacy ? 'Hide notes from the old form' : 'Show notes from the old form';
    }

    handleToggleCoBorrower(event) {
        this.hasCoBorrower = event.target.checked;
    }

    handleToggleLegacy() {
        this.showLegacy = !this.showLegacy;
    }

    handleBlockChange(event) {
        this.edits = { ...this.edits, [event.target.name]: event.target.value };
    }

    // The shape LeadNotesFormController expects; an unticked co-borrower never writes back.
    collectBlocks() {
        const out = [];
        this.sections.forEach((section) => {
            (section.blocks || []).forEach((block) => {
                if (block.coBorrower && !this.hasCoBorrower) return;
                out.push({
                    field: block.field,
                    label: block.label,
                    sectionLabel: section.label,
                    value: Object.prototype.hasOwnProperty.call(this.edits, block.field) ? this.edits[block.field] : block.value
                });
            });
        });
        return out;
    }

    handleSave() {
        this.save(false);
    }

    handleSaveToNote() {
        this.save(true);
    }

    async save(alsoCreateNote) {
        const blocksJson = JSON.stringify(this.collectBlocks());
        this.isSaving = true;
        try {
            await saveApplicationSummary({ recordId: this.recordId, blocksJson });
        } catch (e) {
            this.isSaving = false;
            this.toast('error', e?.body?.message || 'Could not save the application summary.');
            return;
        }
        if (alsoCreateNote) {
            try {
                await createSummaryNote({ recordId: this.recordId, blocksJson });
            } catch (e) {
                // The summary itself already saved, so say so rather than implying nothing happened.
                this.isSaving = false;
                this.toast('warning', 'Summary saved, but the note could not be created.');
                return;
            }
        }
        this.isSaving = false;
        this.toast('success', alsoCreateNote ? 'Application summary saved and added to notes.' : 'Application summary saved.');
        this.dispatchEvent(new CustomEvent('close', { detail: { saved: true } }));
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('close', { detail: { saved: false } }));
    }

    toast(variant, message) {
        this.dispatchEvent(new ShowToastEvent({ title: '', message, variant }));
    }
}
