import { LightningElement, api } from 'lwc';
import logActivity from '@salesforce/apex/ExternalLoPortalController.logActivity';
import { reduceApexError } from 'c/portalUtils';
import EXTLO_LOG_TITLE from '@salesforce/label/c.ExtLO_Log_Title';
import EXTLO_LOG_CATEGORY from '@salesforce/label/c.ExtLO_Log_Category';
import EXTLO_LOG_CHANNEL from '@salesforce/label/c.ExtLO_Log_Channel';
import EXTLO_LOG_COUNT from '@salesforce/label/c.ExtLO_Log_Count';
import EXTLO_LOG_SAVE from '@salesforce/label/c.ExtLO_Log_Save';
import EXTLO_LOG_OPEN_HOUSE from '@salesforce/label/c.ExtLO_Log_Open_House';

const CHANNELS = [
    { id: 'call', label: 'Call' },
    { id: 'text', label: 'Text' },
    { id: 'email', label: 'Email' },
    { id: 'meeting', label: 'Meeting' },
    { id: 'open-house', label: EXTLO_LOG_OPEN_HOUSE }
];

export default class PortalActivityModal extends LightningElement {
    @api categories = [];
    @api promptKey;
    @api subjectName;
    @api subjectContext;

    activityKey;
    channel = 'call';
    activityCount = 1;
    notes = '';
    recordId;
    objectApiName;
    contactName;
    saving = false;
    errorMessage;
    _open = false;

    labels = {
        title: EXTLO_LOG_TITLE,
        category: EXTLO_LOG_CATEGORY,
        channel: EXTLO_LOG_CHANNEL,
        count: EXTLO_LOG_COUNT,
        save: EXTLO_LOG_SAVE
    };

    @api
    get open() {
        return this._open;
    }
    set open(value) {
        this._open = value;
        if (value) {
            this.resetForm();
        }
    }

    @api
    get initialActivityKey() {
        return this.activityKey;
    }
    set initialActivityKey(value) {
        if (value) {
            this.activityKey = value;
        }
    }

    @api
    get initialRecordId() {
        return this.recordId;
    }
    set initialRecordId(value) {
        this.recordId = value || undefined;
    }

    @api
    get initialObjectApiName() {
        return this.objectApiName;
    }
    set initialObjectApiName(value) {
        this.objectApiName = value || undefined;
    }

    @api
    get initialContactName() {
        return this.contactName;
    }
    set initialContactName(value) {
        this.contactName = value || undefined;
    }

    get categoryOptions() {
        return (this.categories || []).map((item) => ({
            ...item,
            className: item.activityKey === this.activityKey ? 'channel-btn channel-btn-active' : 'channel-btn'
        }));
    }

    get channels() {
        return CHANNELS.map((item) => ({
            ...item,
            className: item.id === this.channel ? 'channel-btn channel-btn-active' : 'channel-btn'
        }));
    }

    get saveButtonLabel() {
        return this.saving ? 'Saving…' : this.labels.save;
    }

    get selectedCategory() {
        return (this.categories || []).find((item) => item.activityKey === this.activityKey);
    }

    get requiresContact() {
        return this.selectedCategory?.requiresContact === true;
    }

    handleCategory(event) {
        this.activityKey = event.currentTarget.dataset.key;
        this.errorMessage = undefined;
    }

    handleChannel(event) {
        this.channel = event.currentTarget.dataset.channel;
    }

    handleCountStep(event) {
        const delta = Number(event.currentTarget.dataset.delta);
        this.activityCount = Math.max(1, Math.min(50, (this.activityCount || 1) + delta));
    }

    handleCountChange(event) {
        const value = Number(event.target.value);
        this.activityCount = Number.isFinite(value) ? Math.max(1, Math.min(50, value)) : 1;
    }

    handleNotes(event) {
        this.notes = event.target.value;
    }

    handleContactSelect(event) {
        this.recordId = event.detail.recordId;
        this.objectApiName = event.detail.objectApiName;
        this.contactName = event.detail.name;
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    async handleSave() {
        if (!this.activityKey) {
            this.errorMessage = 'Choose an activity category.';
            return;
        }
        this.saving = true;
        this.errorMessage = undefined;
        try {
            const result = await logActivity({
                activityKey: this.activityKey,
                channel: this.channel,
                activityCount: this.activityCount,
                recordId: this.recordId,
                objectApiName: this.objectApiName,
                notes: this.notes,
                promptKey: this.promptKey
            });
            this.dispatchEvent(new CustomEvent('logged', { detail: { message: result.userMessage } }));
            this.handleClose();
        } catch (error) {
            this.errorMessage = reduceApexError(error);
        } finally {
            this.saving = false;
        }
    }

    resetForm() {
        this.channel = 'call';
        this.activityCount = 1;
        this.notes = '';
        this.errorMessage = undefined;
        this.saving = false;
        if (!this.activityKey && this.categories?.length) {
            this.activityKey = this.categories[0].activityKey;
        }
    }
}