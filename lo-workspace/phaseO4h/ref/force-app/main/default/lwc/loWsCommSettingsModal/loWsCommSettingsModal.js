import { LightningElement } from 'lwc';
import getSettings from '@salesforce/apex/LoWsCommSettingsController.getSettings';
import saveSetting from '@salesforce/apex/LoWsCommSettingsController.saveSetting';
import FROM_NUMBER from '@salesforce/label/c.LoWs_Twilio_From_Number';
import { reduceApexError, showPortalToast } from 'c/portalUtils';

// comms-settings (lo-workspace/comms-settings/SPEC.md): per-LO on/off + editable automated texts.
// The shell opens it from the sidebar; it fires `close`.
const GROUPS = [
    { id: 'Agent', label: "To buyer's agents" },
    { id: 'Borrower', label: 'To borrowers' }
];
const SEGMENT = 160;
const FOOTER_LENGTH = '\nNo-reply'.length;

export default class LoWsCommSettingsModal extends LightningElement {
    rows = [];
    loading = true;
    saving = false;
    error;
    editingKey;
    draft = '';
    caret;

    connectedCallback() {
        this._onKeydown = (event) => {
            if (event.key === 'Escape') this.close();
        };
        window.addEventListener('keydown', this._onKeydown);
        this.load();
    }

    disconnectedCallback() {
        window.removeEventListener('keydown', this._onKeydown);
    }

    async load() {
        try {
            this.rows = await getSettings();
        } catch (e) {
            this.error = reduceApexError(e);
        } finally {
            this.loading = false;
        }
    }

    get fromNumber() {
        const d = String(FROM_NUMBER || '').replace(/\D/g, '').slice(-10);
        return d.length === 10 ? `(${d.slice(0, 3)}) ${d.slice(3, 6)}-${d.slice(6)}` : FROM_NUMBER;
    }

    get groups() {
        return GROUPS.map((g) => ({
            ...g,
            rows: this.rows
                .filter((r) => r.audience === g.id)
                .map((r) => ({
                    ...r,
                    isEditing: r.key === this.editingKey,
                    ariaOn: String(!!r.enabled),
                    onLabel: r.enabled ? 'On' : 'Off',
                    switchAria: `${r.label} to ${g.id === 'Agent' ? "buyer's agent" : 'borrower'}`,
                    switchClass: r.enabled ? 'switch switch-on' : 'switch'
                }))
        })).filter((g) => g.rows.length);
    }

    // ---------- On / Off (saves immediately) ----------

    async handleToggle(event) {
        const row = this.rows.find((r) => r.key === event.currentTarget.dataset.key);
        await this.save(row.key, !row.enabled, row.customized ? row.body : null, row.enabled ? 'Turned off' : 'Turned on');
    }

    // ---------- Editor ----------

    startEdit(event) {
        const row = this.rows.find((r) => r.key === event.currentTarget.dataset.key);
        this.editingKey = row.key;
        this.draft = row.body;
        this.caret = undefined;
    }

    cancelEdit() {
        this.editingKey = undefined;
    }

    handleDraft(event) {
        this.draft = event.target.value;
        this.rememberCaret(event);
    }

    rememberCaret(event) {
        this.caret = event.target.selectionStart;
    }

    handleToken(event) {
        const token = event.currentTarget.dataset.token;
        const at = this.caret ?? this.draft.length;
        this.draft = this.draft.slice(0, at) + token + this.draft.slice(at);
        this.caret = at + token.length;
        const area = this.template.querySelector('textarea');
        if (area) {
            area.value = this.draft;
            area.focus();
            area.setSelectionRange(this.caret, this.caret);
        }
    }

    get countLabel() {
        const n = this.draft.length + FOOTER_LENGTH;
        return n > SEGMENT
            ? `About ${n} characters with No-reply: over ${SEGMENT}, so it may arrive as more than one text.`
            : `About ${n} of ${SEGMENT} characters with No-reply (names fill in when sent).`;
    }

    get countClass() {
        return this.draft.length + FOOTER_LENGTH > SEGMENT ? 'count count-over' : 'count';
    }

    get saveDisabled() {
        return this.saving || !this.draft.trim();
    }

    get saveLabel() {
        return this.saving ? 'Saving…' : 'Save message';
    }

    async handleSave() {
        const row = this.rows.find((r) => r.key === this.editingKey);
        if (await this.save(row.key, row.enabled, this.draft, 'Message saved')) {
            this.editingKey = undefined;
        }
    }

    async handleReset() {
        const row = this.rows.find((r) => r.key === this.editingKey);
        if (await this.save(row.key, row.enabled, null, 'Back to the default message')) {
            this.editingKey = undefined;
        }
    }

    async save(key, enabled, body, doneMessage) {
        this.saving = true;
        try {
            this.rows = await saveSetting({ key, enabled, body });
            showPortalToast(this, doneMessage, '', 'success');
            return true;
        } catch (e) {
            showPortalToast(this, 'Not saved', reduceApexError(e), 'error');
            return false;
        } finally {
            this.saving = false;
        }
    }

    // ---------- Close ----------

    handleBackdrop(event) {
        if (event.target === event.currentTarget) this.close();
    }

    close() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}