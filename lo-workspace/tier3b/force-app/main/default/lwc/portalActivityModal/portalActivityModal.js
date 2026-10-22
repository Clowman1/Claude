import { LightningElement, api } from 'lwc';
import { registerTourHooks } from 'c/loWsTourHooks';
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

// Social posts: where it was posted. One list, change it here.
const SOCIAL_KEY = 'social-engagement';
const OTHER_PLATFORM = 'other';

// Call outcome for a lead: Reached moves it to Working, the other two to the next Contact Attempt.
const CALL_OUTCOMES = [
    { id: 'reached', label: 'Reached' },
    { id: 'left-voicemail', label: 'Left voicemail' },
    { id: 'no-answer', label: 'No answer' }
];
const PLATFORMS = [
    { id: 'facebook', label: 'Facebook' },
    { id: 'instagram', label: 'Instagram' },
    { id: 'tiktok', label: 'TikTok' },
    { id: 'linkedin', label: 'LinkedIn' },
    { id: 'youtube', label: 'YouTube' },
    { id: 'x', label: 'X (Twitter)' },
    { id: 'google-business', label: 'Google Business' },
    { id: OTHER_PLATFORM, label: 'Other' }
];

export default class PortalActivityModal extends LightningElement {
    connectedCallback() {
        registerTourHooks(this); // O4b guided tour (c/loWsTourHooks)
    }

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
    /** Categories the picked contact may be logged as (from the search hit); undefined = no limit. */
    allowedKeys;
    platform;
    otherPlatform = '';
    followUp = 'none';
    callOutcome;
    followUpError;
    saving = false;
    errorMessage;
    _open = false;
    _initialRecordId;
    _initialObjectApiName;
    _initialContactName;

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
        this._initialRecordId = value || undefined;
        this.recordId = this._initialRecordId;
    }

    @api
    get initialObjectApiName() {
        return this.objectApiName;
    }
    set initialObjectApiName(value) {
        this._initialObjectApiName = value || undefined;
        this.objectApiName = this._initialObjectApiName;
    }

    @api
    get initialContactName() {
        return this.contactName;
    }
    set initialContactName(value) {
        this._initialContactName = value || undefined;
        this.contactName = this._initialContactName;
    }

    get categoryOptions() {
        return (this.categories || []).map((item) => {
            const disabled = this.isBlockedForContact(item);
            return {
                ...item,
                disabled,
                disabledReason: disabled ? `${item.shortLabel} can't be logged against ${this.contactName || 'this contact'}.` : null,
                className: item.activityKey === this.activityKey ? 'channel-btn channel-btn-active' : 'channel-btn'
            };
        });
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

    // Only calls to a lead carry an outcome (it can move the lead's status).
    get showCallOutcome() {
        return !this.isSocial && this.channel === 'call' && this.objectApiName === 'Lead' && !!this.recordId;
    }

    get callOutcomeOptions() {
        return CALL_OUTCOMES.map((item) => ({
            ...item,
            className: item.id === this.callOutcome ? 'channel-btn channel-btn-active' : 'channel-btn'
        }));
    }

    handleCallOutcome(event) {
        this.callOutcome = event.currentTarget.dataset.outcome;
        this.errorMessage = undefined;
    }

    get isSocial() {
        return this.activityKey === SOCIAL_KEY;
    }

    // A social post has no contact and no channel.
    get showContactPicker() {
        return !this.isSocial;
    }

    // Follow-ups need someone to follow up with: only once a contact is picked (never Social posts).
    get showFollowUp() {
        return !this.isSocial && !!this.recordId;
    }

    handleFollowUpChange(event) {
        this.followUp = event.detail.value;
        this.followUpError = event.detail.error;
    }

    get isOtherPlatform() {
        return this.platform === OTHER_PLATFORM;
    }

    get platformOptions() {
        return PLATFORMS.map((item) => ({
            ...item,
            pressed: String(item.id === this.platform),
            className: item.id === this.platform ? 'channel-btn channel-btn-active' : 'channel-btn'
        }));
    }

    get platformLabel() {
        if (this.platform === OTHER_PLATFORM) {
            return (this.otherPlatform || '').trim();
        }
        return PLATFORMS.find((item) => item.id === this.platform)?.label;
    }

    handlePlatform(event) {
        this.platform = event.currentTarget.dataset.platform;
        this.errorMessage = undefined;
    }

    handleOtherPlatform(event) {
        this.otherPlatform = event.target.value;
    }

    // Mirrors the server rule (ExternalLoActivityLogService.requireMatchingCategory).
    isBlockedForContact(item) {
        return Array.isArray(this.allowedKeys) && item.requiresContact === true && !this.allowedKeys.includes(item.activityKey);
    }

    handleCategory(event) {
        this.activityKey = event.currentTarget.dataset.key;
        this.errorMessage = undefined;
        if (this.isSocial) {
            // Social posts are never logged against a contact.
            this.recordId = undefined;
            this.objectApiName = undefined;
            this.contactName = undefined;
            this.allowedKeys = undefined;
        }
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
        this.allowedKeys = event.detail.recordId ? event.detail.allowedKeys : undefined;
        this.errorMessage = undefined;
        // Picking a lead selects Consumer convos, a partner Realtor outreach, a past client Past clients.
        // A no-contact category the LO already chose (Social posts) is left alone.
        const suggested = event.detail.activityKey;
        const current = this.selectedCategory;
        if (suggested && (!current || current.requiresContact === true)
            && (this.categories || []).some((item) => item.activityKey === suggested)) {
            this.activityKey = suggested;
        }
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    async handleSave() {
        if (!this.activityKey) {
            this.errorMessage = 'Choose an activity category.';
            return;
        }
        if (this.isSocial && !this.platform) {
            this.errorMessage = 'Pick the platform you posted on.';
            return;
        }
        if (this.isSocial && !this.platformLabel) {
            this.errorMessage = 'Name the platform.';
            return;
        }
        if (!this.isSocial && this.requiresContact && !this.recordId) {
            this.errorMessage = 'Pick who you talked to from the search results.';
            return;
        }
        if (this.showCallOutcome && !this.callOutcome) {
            this.errorMessage = 'Pick how the call went: Reached, Left voicemail, or No answer.';
            return;
        }
        if (this.showFollowUp && this.followUpError) {
            this.errorMessage = this.followUpError;
            return;
        }
        this.saving = true;
        this.errorMessage = undefined;
        try {
            const result = await logActivity({
                activityKey: this.activityKey,
                channel: this.isSocial ? null : this.channel,
                activityCount: this.activityCount,
                recordId: this.isSocial ? null : this.recordId,
                objectApiName: this.isSocial ? null : this.objectApiName,
                notes: this.isSocial ? this.socialNotes() : this.notes,
                promptKey: this.promptKey,
                followUpOption: this.showFollowUp ? this.followUp : 'none',
                callOutcome: this.showCallOutcome ? this.callOutcome : null
            });
            this.dispatchEvent(new CustomEvent('logged', { detail: { message: result.userMessage } }));
            this.handleClose();
        } catch (error) {
            this.errorMessage = reduceApexError(error);
        } finally {
            this.saving = false;
        }
    }

    // The platform goes into the Task notes: "Platform: Instagram", then the LO's notes.
    socialNotes() {
        const extra = (this.notes || '').trim();
        return 'Platform: ' + this.platformLabel + (extra ? '\n' + extra : '');
    }

    resetForm() {
        this.channel = 'call';
        this.activityCount = 1;
        this.notes = '';
        this.errorMessage = undefined;
        this.saving = false;
        // Back to the contact the parent passed (none = empty picker), never the one picked last time.
        this.recordId = this._initialRecordId;
        this.objectApiName = this._initialObjectApiName;
        this.contactName = this._initialContactName;
        this.allowedKeys = undefined;
        this.platform = undefined;
        this.otherPlatform = '';
        this.followUp = 'none';
        this.callOutcome = undefined;
        this.followUpError = undefined;
        if (!this.activityKey && this.categories?.length) {
            this.activityKey = this.categories[0].activityKey;
        }
    }
}