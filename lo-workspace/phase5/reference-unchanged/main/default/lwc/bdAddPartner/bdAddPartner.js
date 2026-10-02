import { LightningElement, api } from 'lwc';
import searchAccounts from '@salesforce/apex/BdCommandCenterController.searchAccounts';
import findDuplicates from '@salesforce/apex/BdCommandCenterController.findDuplicates';
import addExisting from '@salesforce/apex/BdCommandCenterController.addExisting';
import createPartner from '@salesforce/apex/BdCommandCenterController.createPartner';
import previewImport from '@salesforce/apex/BdCommandCenterController.previewImport';
import commitImport from '@salesforce/apex/BdCommandCenterController.commitImport';
import { industryClass, errorMessage } from 'c/bdUtils';

const TYPE_TO_INDUSTRY = { Realtor: 'Realtor', 'Title Agent': 'Title Agent' };
const CHUNK = 40;
const HEADER_ALIASES = {
    firstName: ['first name', 'first', 'firstname', 'given name'],
    lastName: ['last name', 'last', 'lastname', 'surname', 'family name'],
    fullName: ['name', 'full name', 'contact', 'contact name'],
    phone: ['phone', 'mobile', 'mobile phone', 'cell', 'cell phone', 'phone number', 'work phone'],
    email: ['email', 'email address', 'e-mail'],
    company: ['company', 'brokerage', 'firm', 'organization', 'office', 'business'],
    industry: ['industry', 'type', 'category', 'partner type']
};

// Minimal RFC 4180 parser: quoted fields, escaped quotes, commas and newlines inside quotes.
function parseCsv(text) {
    const rows = [];
    let row = [], field = '', quoted = false;
    for (let i = 0; i < text.length; i++) {
        const ch = text[i];
        if (quoted) {
            if (ch === '"' && text[i + 1] === '"') { field += '"'; i++; }
            else if (ch === '"') quoted = false;
            else field += ch;
        } else if (ch === '"') quoted = true;
        else if (ch === ',') { row.push(field); field = ''; }
        else if (ch === '\n' || ch === '\r') {
            if (ch === '\r' && text[i + 1] === '\n') i++;
            row.push(field); rows.push(row); row = []; field = '';
        } else field += ch;
    }
    if (field || row.length) { row.push(field); rows.push(row); }
    return rows.filter((r) => r.some((c) => c.trim()));
}

export default class BdAddPartner extends LightningElement {
    @api industries = [];
    @api prefillPhone;

    tab = 'find';
    busy = false;
    error;

    // find
    term = '';
    hits = [];
    pickIndustryFor;
    findIndustry;

    // create
    firstName = '';
    lastName = '';
    phone = '';
    email = '';
    company = '';
    industry;
    duplicates = [];

    // import
    importRows = [];
    importDefaultIndustry;
    importDone = false;
    fileName;

    connectedCallback() {
        if (this.prefillPhone) {
            this.tab = 'create';
            this.phone = this.prefillPhone;
            this.checkDuplicates();
        }
    }

    get isFind() { return this.tab === 'find'; }
    get isCreate() { return this.tab === 'create'; }
    get isImport() { return this.tab === 'import'; }
    get findClass() { return 'sg' + (this.isFind ? ' sg-on' : ''); }
    get createClass() { return 'sg' + (this.isCreate ? ' sg-on' : ''); }
    get importClass() { return 'sg' + (this.isImport ? ' sg-on' : ''); }
    showFind() { this.tab = 'find'; this.error = null; }
    showCreate() { this.tab = 'create'; this.error = null; }
    showImport() { this.tab = 'import'; this.error = null; }

    get industryOptions() {
        return (this.industries || []).map((v) => ({ label: v, value: v }));
    }

    industryPills(selected) {
        return (this.industries || []).map((v) => ({ value: v, cls: 'pill' + (v === selected ? ' pill-on' : '') }));
    }

    // ------------------------------------------------ find existing

    handleTerm(event) {
        this.term = event.target.value;
        window.clearTimeout(this.searchTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.searchTimer = window.setTimeout(() => this.runSearch(), 300);
    }

    async runSearch() {
        if (!this.term || this.term.trim().length < 2) { this.hits = []; return; }
        try {
            const rows = await searchAccounts({ term: this.term });
            this.hits = rows.map((h) => ({
                ...h,
                sub: [h.company, h.phone, h.email].filter(Boolean).join(' · '),
                typeCls: industryClass(TYPE_TO_INDUSTRY[h.typeLabel]),
                picking: h.id === this.pickIndustryFor,
                pills: this.industryPills(this.findIndustry)
            }));
        } catch (e) {
            this.error = errorMessage(e);
        }
    }

    startPick(event) {
        const id = event.currentTarget.dataset.id;
        const h = this.hits.find((x) => x.id === id);
        this.pickIndustryFor = id;
        this.findIndustry = TYPE_TO_INDUSTRY[h.typeLabel];
        this.refreshHits();
    }

    pickFindIndustry(event) {
        this.findIndustry = event.currentTarget.dataset.value;
        this.refreshHits();
    }

    refreshHits() {
        this.hits = this.hits.map((h) => ({ ...h, picking: h.id === this.pickIndustryFor, pills: this.industryPills(this.findIndustry) }));
    }

    async confirmAddExisting(event) {
        const id = event.currentTarget.dataset.id;
        if (!this.findIndustry) { this.error = 'Pick an industry first.'; return; }
        await this.addExistingAndClose(id, this.findIndustry);
    }

    async addExistingAndClose(id, industry) {
        this.busy = true;
        this.error = null;
        try {
            await addExisting({ accountId: id, industry });
            this.dispatchEvent(new CustomEvent('saved', { detail: { accountId: id } }));
        } catch (e) {
            this.error = errorMessage(e);
        } finally {
            this.busy = false;
        }
    }

    // ------------------------------------------------ create new

    get createPills() { return this.industryPills(this.industry); }
    get hasDuplicates() { return this.duplicates.length > 0; }
    get createDisabled() {
        return this.busy || this.hasDuplicates || !this.firstName || !this.lastName || !this.industry || (!this.phone && !this.email);
    }

    handleField(event) {
        this[event.target.dataset.field] = event.target.value;
    }

    pickCreateIndustry(event) {
        this.industry = event.currentTarget.dataset.value;
    }

    async checkDuplicates() {
        if (!this.phone && !this.email) { this.duplicates = []; return; }
        try {
            const rows = await findDuplicates({ email: this.email, phone: this.phone });
            this.duplicates = rows.map((d) => ({
                ...d,
                sub: [d.company, d.phone, d.email].filter(Boolean).join(' · '),
                typeCls: industryClass(TYPE_TO_INDUSTRY[d.typeLabel]),
                matched: (d.matchedOn || '').toLowerCase()
            }));
        } catch (e) {
            this.error = errorMessage(e);
        }
    }

    async selectDuplicate(event) {
        const id = event.currentTarget.dataset.id;
        const d = this.duplicates.find((x) => x.id === id);
        await this.addExistingAndClose(id, this.industry || TYPE_TO_INDUSTRY[d.typeLabel] || null);
    }

    async create() {
        this.busy = true;
        this.error = null;
        try {
            const accountId = await createPartner({
                firstName: this.firstName, lastName: this.lastName, phone: this.phone,
                email: this.email, company: this.company, industry: this.industry
            });
            this.dispatchEvent(new CustomEvent('saved', { detail: { accountId } }));
        } catch (e) {
            this.error = errorMessage(e);
            this.checkDuplicates();
        } finally {
            this.busy = false;
        }
    }

    // ------------------------------------------------ import

    get hasImportRows() { return this.importRows.length > 0; }
    get importSummary() {
        const count = (a) => this.importRows.filter((r) => r.action === a).length;
        return this.importDone
            ? `${count('link')} linked · ${count('create')} created · ${count('skip')} skipped · ${count('error')} need fixing`
            : `${count('link')} already in Salesforce (will link) · ${count('create')} new (will create) · ${count('skip')} repeats · ${count('error')} need fixing`;
    }
    get needsDefaultIndustry() {
        return this.importRows.some((r) => r.action === 'create' && !r.industry);
    }
    get commitDisabled() {
        return this.busy || this.importDone || !this.importRows.some((r) => r.action === 'link' || r.action === 'create')
            || (this.needsDefaultIndustry && !this.importDefaultIndustry);
    }

    handleDefaultIndustry(event) {
        this.importDefaultIndustry = event.detail.value;
    }

    handleFile(event) {
        const file = event.target.files && event.target.files[0];
        if (!file) return;
        this.fileName = file.name;
        const reader = new FileReader();
        reader.onload = () => this.loadCsv(String(reader.result));
        reader.readAsText(file);
    }

    async loadCsv(text) {
        this.error = null;
        this.importDone = false;
        const rows = parseCsv(text);
        if (rows.length < 2) { this.error = 'That file has no rows under the header.'; return; }
        const header = rows[0].map((h) => h.trim().toLowerCase());
        const col = {};
        Object.keys(HEADER_ALIASES).forEach((key) => {
            col[key] = header.findIndex((h) => HEADER_ALIASES[key].includes(h));
        });
        if (col.lastName < 0 && col.fullName < 0) { this.error = 'Add a "Last Name" (or "Name") column.'; return; }
        const cell = (r, key) => (col[key] >= 0 && r[col[key]] ? r[col[key]].trim() : '');
        const industryByLower = {};
        (this.industries || []).forEach((i) => { industryByLower[i.toLowerCase()] = i; });
        const parsed = rows.slice(1).map((r, i) => {
            let first = cell(r, 'firstName'), last = cell(r, 'lastName');
            if (!last && cell(r, 'fullName')) {
                const parts = cell(r, 'fullName').split(/\s+/);
                last = parts.pop();
                first = parts.join(' ');
            }
            const rawIndustry = cell(r, 'industry');
            return {
                rowNumber: i + 2, firstName: first, lastName: last, phone: cell(r, 'phone'), email: cell(r, 'email'),
                company: cell(r, 'company'), industry: industryByLower[rawIndustry.toLowerCase()] || rawIndustry || null
            };
        });
        this.busy = true;
        try {
            this.importRows = this.decorate(await this.inChunks(previewImport, parsed));
        } catch (e) {
            this.error = errorMessage(e);
        } finally {
            this.busy = false;
        }
    }

    async inChunks(method, rows, extra = {}) {
        let out = [];
        for (let i = 0; i < rows.length; i += CHUNK) {
            // eslint-disable-next-line no-await-in-loop
            const res = await method({ rows: rows.slice(i, i + CHUNK), ...extra });
            out = out.concat(res);
        }
        return out;
    }

    decorate(rows) {
        const label = { link: 'Link existing', create: 'Create new', skip: 'Repeat', error: 'Fix' };
        const cls = { link: 'chip re', create: 'chip yes', skip: 'chip oth', error: 'chip no' };
        return rows.map((r) => ({
            ...r,
            key: 'r' + r.rowNumber,
            name: [r.firstName, r.lastName].filter(Boolean).join(' '),
            contact: [r.phone, r.email].filter(Boolean).join(' · '),
            actionLabel: label[r.action],
            actionCls: cls[r.action]
        }));
    }

    async runImport() {
        this.busy = true;
        this.error = null;
        try {
            const clean = this.importRows.map(({ rowNumber, firstName, lastName, phone, email, company, industry }) => ({
                rowNumber, firstName, lastName, phone, email, company, industry
            }));
            this.importRows = this.decorate(await this.inChunks(commitImport, clean, { defaultIndustry: this.importDefaultIndustry }));
            this.importDone = true;
            this.dispatchEvent(new CustomEvent('imported'));
        } catch (e) {
            this.error = errorMessage(e);
        } finally {
            this.busy = false;
        }
    }

    close() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}