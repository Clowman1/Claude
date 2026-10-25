import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getData from '@salesforce/apex/TransactionDocuSignController.getData';
import createDraft from '@salesforce/apex/TransactionDocuSignController.createDraft';
import getSenderView from '@salesforce/apex/TransactionDocuSignController.getSenderView';
import getConsentUrl from '@salesforce/apex/TransactionDocuSignController.getConsentUrl';

const FILE_COLUMNS = [
    { label: 'File', fieldName: 'title', cellAttributes: { iconName: { fieldName: 'icon' } } },
    { label: 'Updated', fieldName: 'modified', type: 'date', initialWidth: 150,
      typeAttributes: { month: 'short', day: 'numeric', year: 'numeric' } }
];

const ICONS = { pdf: 'doctype:pdf', doc: 'doctype:word', docx: 'doctype:word', xls: 'doctype:excel', xlsx: 'doctype:excel',
    png: 'doctype:image', jpg: 'doctype:image', jpeg: 'doctype:image', tif: 'doctype:image', tiff: 'doctype:image',
    txt: 'doctype:txt', rtf: 'doctype:rtf' };

const STATUS_BADGE = { completed: 'slds-theme_success', sent: 'slds-theme_info', delivered: 'slds-theme_info',
    declined: 'slds-theme_error', voided: 'slds-theme_error', created: '' };

const fmt = (d) => (d ? new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }).format(new Date(d)) : '—');

export default class TransactionDocuSign extends LightningElement {
    @api recordId;
    fileColumns = FILE_COLUMNS;
    data;
    templates = [];
    selected = [];
    search = '';
    includeCoBorrower = true;
    includeLoanOfficer = false;
    busy = false;

    connectedCallback() {
        this.load();
    }

    async load() {
        try {
            this.data = await getData({ transactionId: this.recordId });
            this.includeCoBorrower = !!this.data.coBorrower?.email;
        } catch (e) {
            this.toast('error', 'Could not load DocuSign', e);
        }
    }

    // ---- signers
    get signers() {
        const d = this.data || {};
        const list = [];
        if (d.borrower) list.push({ key: 'b', role: 'Borrower', name: d.borrower.name, email: d.borrower.email || 'No email on file', fixed: true });
        if (d.coBorrower) list.push({ key: 'c', role: 'Co-Borrower', name: d.coBorrower.name || 'Co-borrower', email: d.coBorrower.email || 'No email on file',
            checked: this.includeCoBorrower, disabled: !d.coBorrower.email });
        if (d.loanOfficer) list.push({ key: 'l', role: 'Loan Officer', name: d.loanOfficer.name, email: d.loanOfficer.email, checked: this.includeLoanOfficer });
        return list.map((s) => ({ ...s, tileClass: 'signer slds-box slds-box_x-small' + (s.fixed || s.checked ? ' signer_on' : '') }));
    }
    handleSigner(e) {
        if (e.target.dataset.key === 'c') this.includeCoBorrower = e.target.checked;
        if (e.target.dataset.key === 'l') this.includeLoanOfficer = e.target.checked;
    }

    // ---- documents
    get templateTiles() {
        return (this.data?.templates || []).map((t) => {
            const on = this.templates.includes(t);
            return { name: t, checked: on, tileClass: 'template slds-box slds-box_x-small' + (on ? ' signer_on' : '') };
        });
    }
    get templateCountLabel() {
        return this.templates.length ? `${this.templates.length} selected` : 'Optional';
    }
    get files() {
        const q = this.search.toLowerCase();
        return (this.data?.files || [])
            .filter((f) => !q || f.title.toLowerCase().includes(q))
            .map((f) => ({ ...f, icon: ICONS[f.extension] || 'doctype:unknown' }));
    }
    get hasAnyFiles() {
        return this.data?.files?.length > 0;
    }
    get fileCountLabel() {
        const n = this.selected.length;
        return n ? `${n} selected` : `${this.data?.files?.length || 0} available`;
    }
    handleTemplate(e) {
        const name = e.currentTarget.dataset.name;
        this.templates = this.templates.includes(name) ? this.templates.filter((t) => t !== name) : [...this.templates, name];
    }
    handleTemplateKey(e) {
        if (e.key === ' ' || e.key === 'Enter') {
            e.preventDefault();
            this.handleTemplate(e);
        }
    }
    handleSearch(e) {
        this.search = e.target.value || '';
    }
    handleRows(e) {
        // Keep selections that are hidden by the current search.
        const visible = new Set(this.files.map((f) => f.versionId));
        const kept = this.selected.filter((id) => !visible.has(id));
        this.selected = [...kept, ...e.detail.selectedRows.map((r) => r.versionId)];
    }

    // ---- send
    get summary() {
        const parts = [];
        if (this.templates.length) parts.push(this.templates.join(', '));
        if (this.selected.length) parts.push(`${this.selected.length} file${this.selected.length > 1 ? 's' : ''}`);
        if (!parts.length) return 'Choose a template or files to send.';
        const who = this.signers.filter((s) => s.fixed || s.checked).map((s) => s.name).join(', ');
        return `${parts.join(' + ')} → ${who}`;
    }
    get sendDisabled() {
        return this.busy || (!this.templates.length && this.selected.length === 0);
    }

    async handleSend() {
        // Open the tab synchronously so the popup blocker allows it, then point it at DocuSign.
        const win = window.open('', '_blank');
        this.busy = true;
        try {
            const envelopeId = await createDraft({
                transactionId: this.recordId,
                templateNames: this.templates,
                versionIds: this.selected,
                includeCoBorrower: this.includeCoBorrower,
                includeLoanOfficer: this.includeLoanOfficer
            });
            const url = await getSenderView({ transactionId: this.recordId, envelopeId });
            if (win) win.location = url;
            else window.open(url, '_blank');
            const steps = [];
            if (this.templates.length) steps.push('fill in the grey pre-fill fields');
            if (this.selected.length) steps.push('give every signer a Signature with a Date Signed next to it on the added files');
            this.toast('success', 'Opened in DocuSign', `In the DocuSign tab, ${steps.join(' and ')}, then click Send.`);
            this.templates = [];
            this.selected = [];
            this.load();
        } catch (e) {
            // First send per user: DocuSign needs a one-time consent. Send them there in the tab we already opened.
            if (/consent|impersonat/i.test(e?.body?.message || e?.message || '')) {
                try {
                    const url = await getConsentUrl({ transactionId: this.recordId });
                    if (win) win.location = url;
                    else window.open(url, '_blank');
                    this.toast('warning', 'Allow DocuSign access first',
                        'In the DocuSign tab, log in and click Allow (one time only). Then come back and click Send again.');
                    return;
                } catch (consentError) {
                    e = consentError;
                }
            }
            if (win) win.close();
            this.toast('error', 'DocuSign send failed', e);
        } finally {
            this.busy = false;
        }
    }

    // ---- envelopes
    get envelopes() {
        return (this.data?.envelopes || []).map((e, i) => ({
            ...e, key: i, sentLabel: fmt(e.sent), completedLabel: fmt(e.completed),
            badgeClass: 'slds-badge ' + (STATUS_BADGE[(e.status || '').toLowerCase()] ?? '')
        }));
    }
    get hasEnvelopes() {
        return this.envelopes.length > 0;
    }

    toast(variant, title, e) {
        const message = typeof e === 'string' ? e : e?.body?.message || e?.message || 'Unknown error';
        this.dispatchEvent(new ShowToastEvent({ variant, title, message }));
    }
}