// People tab (2026-10-22): onboarding board, hire timeline and master template editor. Spec: onboarding/SPEC.md.
import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import USER_ID from '@salesforce/user/Id';
import getBoard from '@salesforce/apex/PeopleController.getBoard';
import getEmployee from '@salesforce/apex/PeopleController.getEmployee';
import previewChecklist from '@salesforce/apex/PeopleController.previewChecklist';
import createEmployee from '@salesforce/apex/PeopleController.createEmployee';
import saveEmployee from '@salesforce/apex/PeopleController.saveEmployee';
import withdraw from '@salesforce/apex/PeopleController.withdraw';
import setTaskStatus from '@salesforce/apex/PeopleController.setTaskStatus';
import updateTask from '@salesforce/apex/PeopleController.updateTask';
import addOptionalTask from '@salesforce/apex/PeopleController.addOptionalTask';
import addCustomTask from '@salesforce/apex/PeopleController.addCustomTask';
import getPersonal from '@salesforce/apex/PeopleController.getPersonal';
import savePersonal from '@salesforce/apex/PeopleController.savePersonal';
import getTemplates from '@salesforce/apex/PeopleController.getTemplates';
import saveTemplate from '@salesforce/apex/PeopleController.saveTemplate';
import reorderTemplates from '@salesforce/apex/PeopleController.reorderTemplates';
import getAssignees from '@salesforce/apex/PeopleController.getAssignees';
import getEmailDraft from '@salesforce/apex/PeopleController.getEmailDraft';
import sendTaskEmail from '@salesforce/apex/PeopleController.sendTaskEmail';
import signOff from '@salesforce/apex/PeopleController.signOff';
import saveExamPdf from '@salesforce/apex/PeopleController.saveExamPdf';

const ROLES = ['Loan Officer', 'Branch Manager', 'Processor', 'Closer', 'Opener', 'Operations/Admin', 'Manager'];
const ARRANGEMENTS = ['In-Office', 'Remote', 'Hybrid'];
const PHASES = ['Pre-Start', 'Day 1', 'Week 1', '30 Days', '60 Days', '90 Days'];
const STATES = 'AL AK AZ AR CA CO CT DE DC FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT NE NV NH NJ NM NY NC ND OH OK OR PA PR RI SC SD TN TX UT VT VA WA WV WI WY'.split(' ');
const EXAM = ['Regulatory', 'Systems', 'Documentation'];
const AVATARS = ['av-blue', 'av-clay', 'av-indigo', 'av-green', 'av-pink'];
const opts = (list) => list.map((v) => ({ label: v, value: v }));

function fmt(iso, weekday) {
    if (!iso) return 'No date';
    const d = new Date(iso + 'T12:00:00');
    return d.toLocaleDateString('en-US', weekday ? { weekday: 'short', month: 'short', day: 'numeric' } : { month: 'short', day: 'numeric' });
}
function initials(name) {
    return (name || '').split(' ').filter(Boolean).map((p) => p[0]).slice(0, 2).join('').toUpperCase();
}
function statusClass(s) {
    return 'pill pill-' + (s || 'candidate').toLowerCase().replace(/[^a-z]/g, '');
}
function errText(e) {
    return (e && e.body && (e.body.message || (e.body.pageErrors && e.body.pageErrors[0] && e.body.pageErrors[0].message))) || (e && e.message) || 'Something went wrong.';
}

export default class PeopleApp extends LightningElement {
    view = 'board';
    tab = 'onboarding';
    board;
    detail;
    templates = [];
    assignees = [];
    loading = true;
    taskFilter = 'all';
    editTaskId;
    taskDraft = {};
    newTask = { subject: '', phase: 'Week 1', due: null, assignedTo: USER_ID };
    personal;
    employeeModal; // 'new' | 'edit'
    form = {};
    preview;
    templateDraft;
    dragId;
    emailDraft;
    busy = false;

    roleOptions = opts(ROLES);
    arrangementOptions = opts(ARRANGEMENTS);
    phaseOptions = opts(PHASES);
    stateOptions = opts(STATES);
    examOptions = [{ label: 'None', value: '' }].concat(opts(EXAM));
    setsStatusOptions = [{ label: 'None', value: '' }, { label: 'Pre-Start', value: 'Pre-Start' }];
    unitOptions = opts(['Business Days', 'Calendar Days']);
    autoCompleteOptions = [{ label: 'Never', value: '' }, { label: 'Salesforce user linked', value: 'Salesforce user linked' }];

    connectedCallback() {
        getAssignees().then((a) => { this.assignees = a; }).catch(() => {});
        this.loadBoard();
    }

    toast(title, variant = 'success', message) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
    fail(e) {
        this.loading = false;
        this.toast('Could not save', 'error', errText(e));
    }

    // ---------- board ----------
    loadBoard() {
        this.loading = true;
        return getBoard().then((b) => { this.board = b; this.loading = false; }).catch((e) => this.fail(e));
    }
    get isBoard() { return this.view === 'board'; }
    get isEmployee() { return this.view === 'employee'; }
    get isTemplates() { return this.view === 'templates'; }
    get today() { return this.board ? this.board.today : new Date().toISOString().slice(0, 10); }

    get tabs() {
        const n = this.board ? this.board.employees.length : 0;
        const b = this.board ? this.board.branches.length : 0;
        return [['onboarding', `Onboarding · ${n}`], ['renewals', 'Renewals'], ['offboarding', 'Offboarding'], ['branches', `Branches · ${b}`]]
            .map(([value, label]) => ({ value, label, pressed: String(this.tab === value), cls: 'seg' + (this.tab === value ? ' seg-on' : '') }));
    }
    pickTab(e) { this.tab = e.currentTarget.dataset.value; }
    get showOnboarding() { return this.tab === 'onboarding'; }
    get showBranches() { return this.tab === 'branches'; }
    get showEmptyTab() { return this.tab === 'renewals' || this.tab === 'offboarding'; }
    get emptyTabText() {
        return this.tab === 'renewals'
            ? 'Annual renewal checklists (one task per licensed state, NMLS CE, BSA/AML refresher, handbook re-acknowledgment) arrive in Phase 3, after the current-staff load.'
            : 'Offboarding checklists arrive in Phase 3 with the Offboard button on each employee.';
    }

    get cards() {
        if (!this.board) return [];
        return this.board.employees.map((c, i) => {
            const pct = c.total ? Math.round((c.done * 100) / c.total) : 0;
            const started = c.startDate && c.startDate <= this.today;
            return {
                ...c,
                initials: initials(c.name),
                avatarCls: 'avatar ' + AVATARS[i % AVATARS.length],
                statusCls: statusClass(c.status),
                meta: [c.role, c.arrangement].filter(Boolean).join(' · '),
                startLabel: c.startDate ? (started ? 'Started ' : 'Starts ') + fmt(c.startDate, !started) : 'No start date',
                dash: `${pct} 100`,
                pctLabel: pct + '%',
                doneLabel: `${c.done} of ${c.total} tasks done`,
                nextLabel: c.nextSubject ? `${c.nextSubject} · due ${fmt(c.nextDue)}` : 'All tasks complete',
                flagLabel: c.overdue ? `${c.overdue} overdue` : 'On track',
                flagCls: c.overdue ? 'flag flag-late' : 'flag'
            };
        });
    }
    get hasCards() { return this.cards.length > 0; }

    get branchCards() {
        if (!this.board) return [];
        return this.board.branches.map((b) => ({
            ...b,
            code: b.State__c || initials(b.Name),
            statusCls: statusClass(b.Status__c),
            meta: `Branch Manager: ${b.Branch_Manager__r ? b.Branch_Manager__r.Name : 'TBD'} · Target open: ${b.Target_Open_Date__c ? fmt(b.Target_Open_Date__c, true) : 'TBD'}`,
            people: b.Employees__r && b.Employees__r.length ? b.Employees__r.map((e) => e.Name).join(', ') : 'No employees linked yet'
        }));
    }
    get hasBranches() { return this.branchCards.length > 0; }

    get digest() {
        if (!this.board) return [];
        return this.board.digest.slice(0, 10).map((d) => ({
            ...d,
            meta: `${d.employee} · ${d.overdue ? 'overdue since ' + fmt(d.due) : 'due ' + fmt(d.due, true)}`,
            metaCls: d.overdue ? 'digest-meta late' : 'digest-meta'
        }));
    }
    get digestEmpty() { return this.board && this.board.digest.length === 0; }

    openCard(e) { this.openEmployee(e.currentTarget.dataset.id); }

    // ---------- employee ----------
    openEmployee(id) {
        this.loading = true;
        this.personal = undefined;
        this.editTaskId = undefined;
        this.taskFilter = 'all';
        return getEmployee({ employeeId: id }).then((d) => {
            this.detail = d;
            this.view = 'employee';
            this.loading = false;
        }).catch((e) => this.fail(e));
    }
    reloadEmployee() {
        return getEmployee({ employeeId: this.detail.employee.Id }).then((d) => { this.detail = d; }).catch((e) => this.fail(e));
    }
    backToBoard() {
        this.view = 'board';
        this.detail = undefined;
        this.loadBoard();
    }

    get emp() { return this.detail ? this.detail.employee : {}; }
    get locked() { return !this.detail || !this.detail.checklist || this.detail.checklist.Status__c !== 'Open'; }
    get unlocked() { return !this.locked; }
    get empInitials() { return initials(this.emp.Name); }
    get empStatusCls() { return statusClass(this.emp.Status__c); }
    get empMeta() {
        const e = this.emp;
        const started = e.Start_Date__c && e.Start_Date__c <= this.today;
        return [e.Role__c, e.Work_Arrangement__c, e.Start_Date__c ? (started ? 'Started ' : 'Starts ') + fmt(e.Start_Date__c, true) : null].filter(Boolean).join(' · ');
    }
    get facts() {
        const e = this.emp;
        return [
            ['Manager', e.Manager__r ? e.Manager__r.Name : '—'],
            ['Branch', e.Branch__r ? e.Branch__r.Name : '—'],
            ['NMLS ID', e.NMLS_ID__c || '—'],
            ['Licensed states', e.Licensed_States__c ? e.Licensed_States__c.split(';').join(', ') : '—'],
            ['Work email', e.Work_Email__c || '—'],
            ['Personal email', e.Personal_Email__c || '—'],
            ['Salesforce user', e.User__r ? e.User__r.Name : 'Not linked yet']
        ].map(([label, value]) => ({ label, value }));
    }
    get progress() {
        const t = this.detail ? this.detail.tasks : [];
        const done = t.filter((x) => x.Status__c !== 'Open').length;
        const over = t.filter((x) => x.Status__c === 'Open' && x.Due_Date__c && x.Due_Date__c < this.today).length;
        const pct = t.length ? Math.round((done * 100) / t.length) : 0;
        return { label: `${done} of ${t.length} tasks done`, flag: over ? `${over} overdue` : 'On track', bar: `width:${pct}%` };
    }

    get taskFilters() {
        return [['all', 'All'], ['mine', 'Mine'], ['open', 'Open']].map(([value, label]) => ({
            value, label, pressed: String(this.taskFilter === value), cls: 'seg' + (this.taskFilter === value ? ' seg-on' : '')
        }));
    }
    pickTaskFilter(e) { this.taskFilter = e.currentTarget.dataset.value; }

    get phases() {
        if (!this.detail) return [];
        const shown = this.detail.tasks.filter((t) => this.taskFilter === 'all'
            || (this.taskFilter === 'mine' && t.Assigned_To__c === USER_ID)
            || (this.taskFilter === 'open' && t.Status__c === 'Open'));
        const names = PHASES.concat(this.detail.tasks.map((t) => t.Phase__c || 'Other').filter((p) => !PHASES.includes(p)));
        return [...new Set(names)].map((name) => {
            const all = this.detail.tasks.filter((t) => (t.Phase__c || 'Other') === name);
            const vis = shown.filter((t) => (t.Phase__c || 'Other') === name);
            return {
                name,
                count: `${all.filter((t) => t.Status__c !== 'Open').length} of ${all.length} done`,
                tasks: vis.map((t) => this.taskView(t))
            };
        }).filter((p) => p.tasks.length > 0);
    }
    taskView(t) {
        const done = t.Status__c !== 'Open';
        const overdue = !done && t.Due_Date__c && t.Due_Date__c < this.today;
        const stampWhen = t.Completed_At__c ? new Date(t.Completed_At__c).toLocaleString('en-US', { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }) : '';
        return {
            ...t,
            done,
            isNa: t.Status__c === 'N/A',
            subjectCls: 'subject' + (done ? ' subject-done' : ''),
            stamp: done && t.Completed_By__r ? `${t.Status__c === 'N/A' ? 'Marked N/A' : 'Completed'} by ${t.Completed_By__r.Name} · ${stampWhen}` : '',
            dueLabel: overdue ? 'Overdue · ' + fmt(t.Due_Date__c) : fmt(t.Due_Date__c, true),
            dueCls: overdue ? 'chip chip-late' : 'chip chip-plain',
            whoName: t.Assigned_To__r ? t.Assigned_To__r.Name : 'Unassigned',
            whoInitials: t.Assigned_To__r ? initials(t.Assigned_To__r.Name) : '?',
            templateChip: t.Email_Template__c ? (t.Via_DocuSign__c ? 'DocuSign · ' : 'Email · ') + t.Email_Template__c : (t.Via_DocuSign__c ? 'DocuSign' : ''),
            editing: this.editTaskId === t.Id,
            canSend: !done && !this.locked && !!t.Email_Template__c && !t.Via_DocuSign__c,
            sendLabel: 'Send ' + t.Email_Template__c,
            checkLabel: (done ? 'Reopen ' : 'Complete ') + t.Name
        };
    }

    toggleTask(e) {
        const id = e.target.dataset.id;
        this.runAndReload(setTaskStatus({ taskId: id, status: e.target.checked ? 'Done' : 'Open' }));
    }
    markNa() {
        this.runAndReload(setTaskStatus({ taskId: this.editTaskId, status: 'N/A' }), true);
    }
    startEditTask(e) {
        const t = this.detail.tasks.find((x) => x.Id === e.currentTarget.dataset.id);
        this.editTaskId = t.Id;
        this.taskDraft = { assignedTo: t.Assigned_To__c, due: t.Due_Date__c, notes: t.Notes__c || '' };
    }
    cancelEditTask() { this.editTaskId = undefined; }
    draftTask(e) { this.taskDraft = { ...this.taskDraft, [e.target.dataset.field]: e.detail.value }; }
    saveTask() {
        const d = this.taskDraft;
        this.runAndReload(updateTask({ taskId: this.editTaskId, assignedTo: d.assignedTo || null, dueDate: d.due || null, notes: d.notes }), true);
    }
    runAndReload(p, closeEdit) {
        return p.then(() => {
            if (closeEdit) this.editTaskId = undefined;
            return this.reloadEmployee();
        }).catch((e) => { this.fail(e); this.reloadEmployee(); });
    }

    get optional() { return this.detail ? this.detail.optional : []; }
    get hasOptional() { return !this.locked && this.optional.length > 0; }
    addOptional(e) {
        this.runAndReload(addOptionalTask({ employeeId: this.emp.Id, templateId: e.currentTarget.dataset.id }));
    }
    draftNewTask(e) { this.newTask = { ...this.newTask, [e.target.dataset.field]: e.detail.value }; }
    addTask() {
        const t = this.newTask;
        this.runAndReload(addCustomTask({ employeeId: this.emp.Id, subject: t.subject, phase: t.phase, dueDate: t.due || null, assignedTo: t.assignedTo || null }))
            .then(() => { this.newTask = { subject: '', phase: t.phase, due: null, assignedTo: t.assignedTo }; });
    }

    // ---------- email ----------
    openSend(e) {
        const taskId = e.currentTarget.dataset.id;
        getEmailDraft({ taskId }).then((d) => { this.emailDraft = { taskId, ...d }; }).catch((er) => this.fail(er));
    }
    get showEmailModal() { return !!this.emailDraft; }
    closeEmail() { this.emailDraft = undefined; }
    draftEmail(e) {
        const v = e.detail && e.detail.value !== undefined ? e.detail.value : e.target.value; // rich text reports on target
        this.emailDraft = { ...this.emailDraft, [e.target.dataset.field]: v };
    }
    sendEmail() {
        const d = this.emailDraft;
        this.busy = true;
        sendTaskEmail({ taskId: d.taskId, toAddress: d.to, subject: d.subject, body: d.body }).then(() => {
            this.busy = false;
            this.emailDraft = undefined;
            this.toast('Email sent', 'success', 'Sent to ' + d.to + '. The task is marked done.');
            return this.reloadEmployee();
        }).catch((er) => { this.busy = false; this.fail(er); });
    }

    // ---------- sign-off + exam PDF ----------
    get openCount() { return this.detail ? this.detail.tasks.filter((t) => t.Status__c === 'Open').length : 0; }
    get signed() { return this.detail && this.detail.checklist && this.detail.checklist.Status__c === 'Signed Off'; }
    get canSign() { return this.detail && this.detail.canSignOff && !this.signed && !this.locked && this.openCount === 0 && this.detail.tasks.length > 0; }
    get signDisabled() { return !this.canSign || this.busy; }
    get showSignButton() { return !this.signed && this.detail && this.detail.canSignOff; }
    get needsPdf() { return this.signed && !this.detail.checklist.Exam_PDF_Id__c && this.detail.canSignOff; }
    get hasPdf() { return this.signed && !!this.detail.checklist.Exam_PDF_Id__c; }
    get signText() {
        const c = this.detail && this.detail.checklist;
        if (!c) return '';
        if (this.signed) {
            const at = new Date(c.Signed_Off_At__c).toLocaleString('en-US', { month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit' });
            return `Signed off by ${c.Signed_Off_By__r ? c.Signed_Off_By__r.Name : ''} · ${at}. ${this.detail.attestation} The checklist is locked.`;
        }
        if (!this.detail.canSignOff) return 'Bianca Rodrigues (or Christopher Lowman as backup) signs off once every task is done.';
        return this.openCount > 0
            ? `Available once every task is done (${this.openCount} left). Signing off locks the checklist and files the exam PDF on this employee.`
            : 'Every task is done. ' + this.detail.attestation;
    }
    doSignOff() {
        // eslint-disable-next-line no-alert
        if (!window.confirm(this.detail.attestation + ' Sign off and lock this checklist?')) return;
        this.busy = true;
        signOff({ checklistId: this.detail.checklist.Id }).then(() => this.filePdf()).catch((er) => { this.busy = false; this.fail(er); });
    }
    filePdf() {
        this.busy = true;
        return saveExamPdf({ checklistId: this.detail.checklist.Id }).then(() => {
            this.busy = false;
            this.toast('Signed off', 'success', 'The exam PDF is filed on this employee.');
            return this.reloadEmployee();
        }).catch((er) => { this.busy = false; this.fail(er); this.reloadEmployee(); });
    }
    previewPdf() { window.open('/apex/PeopleExamPdf?id=' + this.detail.checklist.Id, '_blank'); }
    openPdf() { window.open('/lightning/r/ContentDocument/' + this.detail.checklist.Exam_PDF_Id__c + '/view', '_blank'); }

    // ---------- personal (encrypted) ----------
    get canViewPersonal() { return this.detail && this.detail.canViewPersonal; }
    get personalShown() { return !!this.personal; }
    revealPersonal() {
        getPersonal({ employeeId: this.emp.Id }).then((p) => { this.personal = { ...p }; }).catch((e) => this.fail(e));
    }
    hidePersonal() { this.personal = undefined; }
    draftPersonal(e) { this.personal = { ...this.personal, [e.target.dataset.field]: e.detail.value }; }
    savePersonal() {
        savePersonal({ personal: this.personal }).then(() => this.toast('Personal details saved')).catch((e) => this.fail(e));
    }

    confirmWithdraw() {
        // eslint-disable-next-line no-alert
        if (!window.confirm(`Withdraw ${this.emp.Name}? Their open tasks are marked N/A and the checklist closes.`)) return;
        withdraw({ employeeId: this.emp.Id }).then(() => { this.toast(`${this.emp.Name} withdrawn`); this.backToBoard(); }).catch((e) => this.fail(e));
    }

    // ---------- new / edit employee ----------
    get branchOptions() {
        return [{ label: 'None', value: '' }].concat((this.board ? this.board.branches : []).map((b) => ({ label: b.Name, value: b.Id })));
    }
    get modalTitle() { return this.employeeModal === 'new' ? 'New Employee' : 'Edit ' + this.emp.Name; }
    get isNewModal() { return this.employeeModal === 'new'; }
    get showEmployeeModal() { return !!this.employeeModal; }
    get saveLabel() { return this.isNewModal ? 'Create and generate tasks' : 'Save'; }
    get statesValue() { return this.form.Licensed_States__c ? this.form.Licensed_States__c.split(';') : []; }

    openNew() {
        this.form = { Role__c: 'Loan Officer', Work_Arrangement__c: 'In-Office', Branch__c: '' };
        this.preview = undefined;
        this.employeeModal = 'new';
    }
    openEdit() {
        const e = this.emp;
        this.form = {
            Id: e.Id, First_Name__c: e.First_Name__c, Last_Name__c: e.Last_Name__c, Role__c: e.Role__c, Work_Arrangement__c: e.Work_Arrangement__c,
            Status__c: e.Status__c, Start_Date__c: e.Start_Date__c, Manager__c: e.Manager__c, Branch__c: e.Branch__c || '', Work_Email__c: e.Work_Email__c,
            Personal_Email__c: e.Personal_Email__c, NMLS_ID__c: e.NMLS_ID__c, Licensed_States__c: e.Licensed_States__c
        };
        this.employeeModal = 'edit';
    }
    closeEmployeeModal() { this.employeeModal = undefined; }
    draftForm(e) {
        const f = e.target.dataset.field;
        let v = e.detail.value;
        if (f === 'Licensed_States__c') v = (v || []).join(';');
        this.form = { ...this.form, [f]: v };
        if (this.isNewModal && ['Role__c', 'Work_Arrangement__c', 'Start_Date__c'].includes(f)) this.refreshPreview();
    }
    pickManager(e) { this.form = { ...this.form, Manager__c: e.detail.recordId || null }; }
    refreshPreview() {
        const f = this.form;
        if (!f.Start_Date__c) { this.preview = undefined; return; }
        previewChecklist({ role: f.Role__c, arrangement: f.Work_Arrangement__c, startDate: f.Start_Date__c }).then((p) => {
            this.preview = `${p.count} tasks will be generated for a ${f.Role__c} (${f.Work_Arrangement__c})`
                + (p.optional ? `, plus ${p.optional} optional to add` : '') + '. '
                + (p.firstDue ? `First task due ${fmt(p.firstDue, true)}; ` : '') + `first day ${fmt(f.Start_Date__c, true)}.`;
        }).catch(() => { this.preview = undefined; });
    }
    saveEmployeeForm() {
        const rec = { ...this.form, Branch__c: this.form.Branch__c || null };
        Object.keys(rec).forEach((k) => { if (rec[k] === '') rec[k] = null; });
        if (this.isNewModal) {
            createEmployee({ employee: rec }).then((id) => {
                this.employeeModal = undefined;
                this.toast('Employee created', 'success', 'Checklist generated.');
                this.openEmployee(id);
            }).catch((e) => this.fail(e));
        } else {
            saveEmployee({ employee: rec }).then((late) => {
                this.employeeModal = undefined;
                if (late > 0) this.toast('Start date moved', 'warning', `${late} open task${late === 1 ? ' is' : 's are'} now due in the past.`);
                else this.toast('Saved');
                this.reloadEmployee();
            }).catch((e) => this.fail(e));
        }
    }

    // ---------- template editor ----------
    openTemplates() {
        this.view = 'templates';
        this.loadTemplates();
    }
    loadTemplates() {
        this.loading = true;
        return getTemplates({ checklistType: 'Onboarding' }).then((t) => { this.templates = t; this.loading = false; }).catch((e) => this.fail(e));
    }
    get templateRows() {
        return this.templates.map((t, i) => ({
            ...t,
            num: i + 1,
            rowCls: 'tpl-row' + (t.Active__c ? '' : ' tpl-inactive') + (this.dragId === t.Id ? ' tpl-drag' : ''),
            offsetLabel: t.Offset_Days__c == null ? 'No due date' : t.Offset_Days__c === 0 ? 'Start day'
                : (t.Offset_Days__c > 0 ? '+' : '') + t.Offset_Days__c + (t.Offset_Unit__c === 'Calendar Days' ? ' days' : ' bd'),
            roles: t.Roles__c ? t.Roles__c.split(';').join(', ') : 'All roles',
            arrangements: t.Work_Arrangements__c ? t.Work_Arrangements__c.split(';').join(', ') : 'All arrangements',
            who: t.Default_Assignee__r ? t.Default_Assignee__r.Name : 'Unassigned',
            tags: [t.Optional__c ? 'Optional' : null, t.Active__c ? null : 'Inactive', t.Email_Template__c, t.Via_DocuSign__c ? 'DocuSign' : null, t.Sets_Status__c ? '→ ' + t.Sets_Status__c : null,
                t.Remind__c ? 'Email reminder' : null, t.Auto_Complete__c ? 'Auto: ' + t.Auto_Complete__c : null]
                .filter(Boolean).join(' · ')
        }));
    }
    get templateCount() { return `${this.templates.filter((t) => t.Active__c).length} active tasks`; }

    dragStart(e) {
        this.dragId = e.currentTarget.dataset.id;
        e.dataTransfer.effectAllowed = 'move';
    }
    dragOver(e) {
        e.preventDefault();
        const over = e.currentTarget.dataset.id;
        if (!this.dragId || over === this.dragId) return;
        const list = [...this.templates];
        const from = list.findIndex((t) => t.Id === this.dragId);
        const to = list.findIndex((t) => t.Id === over);
        list.splice(to, 0, list.splice(from, 1)[0]);
        this.templates = list;
    }
    drop(e) { e.preventDefault(); }
    dragEnd() {
        if (!this.dragId) return;
        this.dragId = undefined;
        reorderTemplates({ orderedIds: this.templates.map((t) => t.Id) }).then(() => this.loadTemplates()).catch((e) => this.fail(e));
    }
    moveTemplate(e) {
        const i = this.templates.findIndex((t) => t.Id === e.currentTarget.dataset.id);
        const j = i + Number(e.currentTarget.dataset.dir);
        if (j < 0 || j >= this.templates.length) return;
        const list = [...this.templates];
        list.splice(j, 0, list.splice(i, 1)[0]);
        this.templates = list;
        reorderTemplates({ orderedIds: list.map((t) => t.Id) }).then(() => this.loadTemplates()).catch((er) => this.fail(er));
    }

    get showTemplateModal() { return !!this.templateDraft; }
    get templateModalTitle() { return this.templateDraft && this.templateDraft.Id ? 'Edit template task' : 'New template task'; }
    get draftRoles() { return this.templateDraft.Roles__c ? this.templateDraft.Roles__c.split(';') : []; }
    get draftArrangements() { return this.templateDraft.Work_Arrangements__c ? this.templateDraft.Work_Arrangements__c.split(';') : []; }
    get assigneeOptions() { return [{ label: 'Unassigned', value: '' }].concat(this.assignees); }
    newTemplate() {
        this.templateDraft = { Checklist_Type__c: 'Onboarding', Phase__c: 'Pre-Start', Active__c: true, Optional__c: false, Via_DocuSign__c: false,
            Remind__c: false, Offset_Unit__c: 'Business Days', Default_Assignee__c: USER_ID };
    }
    editTemplate(e) {
        const t = this.templates.find((x) => x.Id === e.currentTarget.dataset.id);
        const draft = { ...t };
        delete draft.Default_Assignee__r;
        this.templateDraft = draft;
    }
    closeTemplateModal() { this.templateDraft = undefined; }
    draftTemplate(e) {
        const f = e.target.dataset.field;
        let v = e.target.type === 'checkbox' || e.target.type === 'toggle' ? e.target.checked : e.detail.value;
        if (f === 'Roles__c' || f === 'Work_Arrangements__c') v = (v || []).join(';');
        if (f === 'Offset_Days__c') v = v === '' || v == null ? null : Number(v);
        this.templateDraft = { ...this.templateDraft, [f]: v };
    }
    saveTemplateDraft() {
        const rec = { ...this.templateDraft };
        Object.keys(rec).forEach((k) => { if (rec[k] === '') rec[k] = null; });
        saveTemplate({ template: rec }).then(() => {
            this.templateDraft = undefined;
            this.toast('Template saved', 'success', 'Applies to checklists created from now on.');
            this.loadTemplates();
        }).catch((e) => this.fail(e));
    }
}
