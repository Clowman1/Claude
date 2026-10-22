// People tab (2026-10-22): onboarding board, hire timeline and master template editor. Spec: onboarding/SPEC.md.
import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import USER_ID from '@salesforce/user/Id';
import getBoard from '@salesforce/apex/PeopleController.getBoard';
import getDetail from '@salesforce/apex/PeopleController.getDetail';
import offboard from '@salesforce/apex/PeopleController.offboard';
import generateRenewals from '@salesforce/apex/PeopleController.generateRenewals';
import saveBranch from '@salesforce/apex/PeopleController.saveBranch';
import getHr from '@salesforce/apex/PeopleHrController.getHr';
import saveComp from '@salesforce/apex/PeopleHrController.saveComp';
import deleteComp from '@salesforce/apex/PeopleHrController.deleteComp';
import saveLicense from '@salesforce/apex/PeopleHrController.saveLicense';
import addExistingEmployee from '@salesforce/apex/PeopleHrController.addExistingEmployee';
import getCompliance from '@salesforce/apex/PeopleHrController.getCompliance';
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
const PHASES_BY_TYPE = {
    Onboarding: ['Pre-Start', 'Day 1', 'Week 1', '30 Days', '60 Days', '90 Days'],
    Offboarding: ['Before Last Day', 'Last Day', 'After Last Day'],
    Renewal: ['Renewal'],
    Branch: ['Approval', 'Licensing', 'Setup', 'Launch']
};
const TYPES = ['Onboarding', 'Renewal', 'Offboarding', 'Branch'];
const TYPE_LABEL = { Onboarding: 'Onboarding', Renewal: 'Annual Compliance', Offboarding: 'Offboarding', Branch: 'Branch' };
const DEPARTMENTS = ['Leadership', 'Sales', 'Processing', 'Closing & Funding', 'Operations', 'Marketing', 'Business Development'];
const money = (n) => (n == null ? '' : '$' + Number(n).toLocaleString('en-US', { maximumFractionDigits: 2 }));
const PHASES = [].concat(...Object.values(PHASES_BY_TYPE));
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
    tab = 'Onboarding';
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
    templateType = 'Onboarding';
    offboardForm;
    branchForm;
    hr;
    compForm;
    licenseForm;
    compliance;

    roleOptions = opts(ROLES);
    arrangementOptions = opts(ARRANGEMENTS);
    phaseOptions = opts(PHASES);
    stateOptions = opts(STATES);
    reasonOptions = opts(['Resigned', 'Terminated', 'Other']);
    departmentOptions = opts(DEPARTMENTS);
    employmentOptions = opts(['W-2 Employee', '1099 Contractor']);
    scheduleOptions = opts(['Full-time', 'Part-time']);
    payTypeOptions = opts(['Salary', 'Hourly', 'Commission only', 'Salary + Commission', 'Per-file']);
    perOptions = opts(['Year', 'Hour']);
    licenseStatusOptions = opts(['Active', 'Pending', 'Inactive', 'Expired']);
    sponsorshipOptions = opts(['Sponsored', 'Pending', 'Removed']);
    branchStatusOptions = opts(['Planning', 'Licensing', 'Open', 'Closed']);
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
    get isBranchView() { return this.isEmployee && this.detail && !!this.detail.branch; }
    get isPersonView() { return this.isEmployee && this.detail && !!this.detail.employee; }
    get isTemplates() { return this.view === 'templates'; }
    get today() { return this.board ? this.board.today : new Date().toISOString().slice(0, 10); }

    countOf(type) { return this.board ? this.board.cards.filter((c) => c.type === type).length : 0; }
    get tabs() {
        const b = this.board ? this.board.branches.length : 0;
        const s = this.board ? this.board.staff.length : 0;
        return [['Onboarding', `Onboarding · ${this.countOf('Onboarding')}`], ['Renewal', `Annual Compliance · ${this.countOf('Renewal')}`],
            ['Offboarding', `Offboarding · ${this.countOf('Offboarding')}`], ['Branch', `Branches · ${b}`], ['Staff', `Staff · ${s}`], ['Compliance', 'Compliance']]
            .map(([value, label]) => ({ value, label, pressed: String(this.tab === value), cls: 'seg' + (this.tab === value ? ' seg-on' : '') }));
    }
    pickTab(e) {
        this.tab = e.currentTarget.dataset.value;
        if (this.tab === 'Compliance') this.loadCompliance();
    }
    get showCompliance() { return this.tab === 'Compliance'; }
    get missingMap() { return (this.board && this.board.missing) || {}; }
    get missingCount() { return Object.keys(this.missingMap).length; }
    get missingBanner() {
        const n = this.missingCount;
        return n ? `${n} employee${n === 1 ? ' needs' : 's need'} information filled in` : null;
    }
    reviewMissing() { this.tab = 'Compliance'; this.loadCompliance(); }
    get showCards() { return ['Onboarding', 'Renewal', 'Offboarding'].includes(this.tab); }
    get showBranches() { return this.tab === 'Branch'; }
    get showStaff() { return this.tab === 'Staff'; }
    get isRenewalTab() { return this.tab === 'Renewal'; }
    get isOnboardingTab() { return this.tab === 'Onboarding'; }
    get canGenerateRenewals() { return this.isRenewalTab && this.board && this.board.renewalEligible > 0; }
    get renewalButtonLabel() { return this.board ? `Open ${this.board.renewalYear} Annual Compliance (${this.board.renewalEligible})` : ''; }
    get emptyCardsText() {
        if (this.tab === 'Renewal') {
            return 'No open Annual Compliance checklists. They open every October 15 for Active employees (license renewals per state, NMLS CE, BSA/AML, Fair Lending, GLBA privacy, IT security, handbook).';
        }
        if (this.tab === 'Offboarding') return 'No one is offboarding. Open an employee from Staff and use Offboard.';
        return 'No one is onboarding. Use New Employee to start a checklist.';
    }
    openRenewals() {
        this.busy = true;
        generateRenewals({ year: this.board.renewalYear }).then((n) => {
            this.busy = false;
            this.toast(`${n} Annual Compliance checklist${n === 1 ? '' : 's'} opened`);
            return this.loadBoard();
        }).catch((e) => { this.busy = false; this.fail(e); });
    }

    get staffRows() {
        if (!this.board) return [];
        return this.board.staff.map((e) => ({
            ...e,
            statusCls: statusClass(e.Status__c),
            start: e.Start_Date__c ? fmt(e.Start_Date__c) + ', ' + e.Start_Date__c.slice(0, 4) : '—',
            states: e.Licensed_States__c ? e.Licensed_States__c.split(';').join(', ') : '—',
            manager: e.Manager__r ? e.Manager__r.Name : '—',
            needs: this.missingMap[e.Id] ? 'Needs info' : null,
            rowCls: 'staff-row' + (this.missingMap[e.Id] ? ' staff-needs' : '')
        }));
    }

    get cards() {
        if (!this.board) return [];
        return this.board.cards.filter((c) => c.type === this.tab).map((c, i) => {
            const pct = c.total ? Math.round((c.done * 100) / c.total) : 0;
            const started = c.startDate && c.startDate <= this.today;
            return {
                ...c,
                initials: initials(c.name),
                avatarCls: 'avatar ' + AVATARS[i % AVATARS.length],
                statusCls: statusClass(c.status),
                meta: [c.role, c.arrangement].filter(Boolean).join(' · '),
                startLabel: c.type === 'Renewal' ? `Annual Compliance ${c.year} · due by ${fmt(c.anchorDate, true)}`
                    : c.type === 'Offboarding' ? 'Last day ' + fmt(c.anchorDate, true)
                    : c.startDate ? (started ? 'Started ' : 'Starts ') + fmt(c.startDate, !started) : 'No start date',
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
        const progress = {};
        this.board.cards.filter((c) => c.type === 'Branch').forEach((c) => { progress[c.id] = c; });
        return this.board.branches.map((b) => ({
            ...b,
            progress: progress[b.Id] ? `${progress[b.Id].done} of ${progress[b.Id].total} branch tasks done` + (progress[b.Id].overdue ? ` · ${progress[b.Id].overdue} overdue` : '')
                : 'Add a target open date to start the branch checklist',
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

    openCard(e) { this.openRecord(e.currentTarget.dataset.id, e.currentTarget.dataset.checklist); }

    // ---------- employee ----------
    openEmployee(id) { return this.openRecord(id); }
    openRecord(id, checklistId) {
        this.loading = true;
        this.personal = undefined;
        this.editTaskId = undefined;
        this.taskFilter = 'all';
        this.hr = undefined;
        if (String(id).length) {
            getHr({ employeeId: id }).then((x) => { this.hr = x; }).catch(() => { this.hr = undefined; });
        }
        return getDetail({ recordId: id, checklistId: checklistId || null }).then((d) => {
            this.detail = d;
            this.view = 'employee';
            this.loading = false;
        }).catch((e) => this.fail(e));
    }
    reloadHr() {
        return getHr({ employeeId: this.emp.Id }).then((x) => { this.hr = x; }).catch((e) => this.fail(e));
    }
    reloadEmployee() {
        const id = this.detail.employee ? this.detail.employee.Id : this.detail.branch.Id;
        return getDetail({ recordId: id, checklistId: this.detail.checklist ? this.detail.checklist.Id : null })
            .then((d) => { this.detail = d; }).catch((e) => this.fail(e));
    }
    backToBoard() {
        this.view = 'board';
        this.detail = undefined;
        this.loadBoard();
    }

    get emp() { return (this.detail && (this.detail.employee || this.detail.branch)) || {}; }
    get checklistTabs() {
        if (!this.detail || this.detail.checklists.length < 2) return [];
        return this.detail.checklists.map((c) => {
            const on = this.detail.checklist && this.detail.checklist.Id === c.Id;
            const label = TYPE_LABEL[c.Type__c] + (c.Renewal_Year__c ? ' ' + c.Renewal_Year__c : '') + (c.Status__c === 'Open' ? '' : ' · ' + c.Status__c);
            return { value: c.Id, label, pressed: String(on), cls: 'seg' + (on ? ' seg-on' : '') };
        });
    }
    get hasChecklistTabs() { return this.checklistTabs.length > 0; }
    pickChecklist(e) { this.openRecord(this.emp.Id, e.currentTarget.dataset.value); }
    get checklistType() { return this.detail && this.detail.checklist ? this.detail.checklist.Type__c : 'Onboarding'; }
    get noChecklist() { return !this.hasChecklist; }
    get hasChecklist() { return !!(this.detail && this.detail.checklist); }
    get isOffboarding() { return this.checklistType === 'Offboarding'; }
    get handover() {
        const d = this.detail;
        if (!d || !this.isOffboarding || d.openLeads == null) return null;
        return `To hand over: ${d.openLeads} open Lead${d.openLeads === 1 ? '' : 's'} owned and ${d.openTransactions} active Transaction${d.openTransactions === 1 ? '' : 's'} as Loan Officer.`;
    }
    get canOffboard() {
        const d = this.detail;
        return d && d.employee && !['Terminated', 'Withdrawn', 'Offboarding'].includes(d.employee.Status__c);
    }
    get canWithdraw() { return this.unlocked && this.checklistType === 'Onboarding'; }
    get locked() { return !this.detail || !this.detail.checklist || this.detail.checklist.Status__c !== 'Open'; }
    get unlocked() { return !this.locked; }
    get empInitials() { return initials(this.emp.Name); }
    get empStatusCls() { return statusClass(this.emp.Status__c); }
    get empMeta() {
        const e = this.emp;
        if (this.detail && this.detail.branch) {
            return [e.State__c, e.Target_Open_Date__c ? 'Target open ' + fmt(e.Target_Open_Date__c, true) : 'No target open date'].filter(Boolean).join(' · ');
        }
        const started = e.Start_Date__c && e.Start_Date__c <= this.today;
        return [e.Role__c, e.Work_Arrangement__c, e.Start_Date__c ? (started ? 'Started ' : 'Starts ') + fmt(e.Start_Date__c, true) : null].filter(Boolean).join(' · ');
    }
    get facts() {
        const e = this.emp;
        if (this.detail && this.detail.branch) {
            return [
                ['Branch manager', e.Branch_Manager__r ? e.Branch_Manager__r.Name : '—'],
                ['Branch NMLS ID', e.Branch_NMLS_ID__c || '—'],
                ['Address', e.Address__c || '—'],
                ['Employees', e.Employees__r && e.Employees__r.length ? e.Employees__r.map((x) => x.Name).join(', ') : 'None linked yet']
            ].map(([label, value]) => ({ label, value }));
        }
        const anniv = e.Hire_Date__c ? fmt(e.Hire_Date__c) + ' (hired ' + e.Hire_Date__c.slice(0, 4) + ')' : '—';
        return [
            ['Title', e.Title__c || '—'],
            ['Department', e.Department__c || '—'],
            ['Employment', [e.Employment_Type__c, e.Schedule__c].filter(Boolean).join(' · ') || '—'],
            ['Work anniversary', anniv],
            ['Manager', e.Manager__r ? e.Manager__r.Name : '—'],
            ['Branch', e.Branch__r ? e.Branch__r.Name : '—'],
            ['NMLS ID', e.NMLS_ID__c || '—'],
            ['Licensed states', e.Licensed_States__c ? e.Licensed_States__c.split(';').join(', ') : '—'],
            ['Work email', e.Work_Email__c || '—'],
            ['Personal email', e.Personal_Email__c || '—'],
            ['Salesforce user', e.User__r ? e.User__r.Name : 'Not linked yet'],
            ['Last day', e.Termination_Date__c ? fmt(e.Termination_Date__c, true) + (e.Termination_Reason__c ? ' · ' + e.Termination_Reason__c : '') : '—']
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
        const order = PHASES_BY_TYPE[this.checklistType] || PHASES;
        const names = order.concat(this.detail.tasks.map((t) => t.Phase__c || 'Other').filter((p) => !order.includes(p)));
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
        this.runAndReload(addOptionalTask({ checklistId: this.detail.checklist.Id, templateId: e.currentTarget.dataset.id }));
    }
    draftNewTask(e) { this.newTask = { ...this.newTask, [e.target.dataset.field]: e.detail.value }; }
    addTask() {
        const t = this.newTask;
        this.runAndReload(addCustomTask({ checklistId: this.detail.checklist.Id, subject: t.subject, phase: t.phase, dueDate: t.due || null, assignedTo: t.assignedTo || null }))
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
    get checklistPhaseOptions() { return opts(PHASES_BY_TYPE[this.checklistType] || PHASES); }

    // ---------- HR: missing data, licenses, compensation (P4) ----------
    get hrMissing() { return this.hr && this.hr.missing && this.hr.missing.length ? 'Needs: ' + this.hr.missing.join(', ') : null; }
    get licenseRows() {
        return (this.hr ? this.hr.licenses : []).map((l) => ({
            ...l,
            statusCls: statusClass(l.Status__c),
            number: l.License_Number__c || 'No number',
            numberCls: l.License_Number__c ? '' : 'needs-text',
            expires: l.Expiration_Date__c ? fmt(l.Expiration_Date__c) + ', ' + l.Expiration_Date__c.slice(0, 4) : 'No expiration',
            expiresCls: l.Expiration_Date__c ? '' : 'needs-text',
            renewed: l.Last_Renewed__c ? 'Renewed ' + fmt(l.Last_Renewed__c) + ', ' + l.Last_Renewed__c.slice(0, 4) : ''
        }));
    }
    get hasLicenses() { return this.licenseRows.length > 0; }
    get compRows() {
        return (this.hr ? this.hr.compensation : []).map((c, i) => ({
            ...c,
            current: i === 0,
            when: c.Effective_Date__c ? fmt(c.Effective_Date__c) + ', ' + c.Effective_Date__c.slice(0, 4) : '—',
            base: c.Base_Amount__c != null ? money(c.Base_Amount__c) + (c.Base_Per__c ? ' / ' + c.Base_Per__c.toLowerCase() : '') : '',
            extra: [c.LO_Comp_Bps__c != null ? c.LO_Comp_Bps__c + ' bps' : null, c.Per_Loan_Flat__c != null ? money(c.Per_Loan_Flat__c) + ' per loan' : null, c.Bonus_Plan__c]
                .filter(Boolean).join(' · ')
        }));
    }
    get hasComp() { return this.compRows.length > 0; }

    openLicense(e) {
        const id = e.currentTarget.dataset.id;
        const l = id ? this.hr.licenses.find((x) => x.Id === id) : null;
        this.licenseForm = l
            ? { Id: l.Id, State__c: l.State__c, License_Number__c: l.License_Number__c, Status__c: l.Status__c, Issue_Date__c: l.Issue_Date__c,
                Expiration_Date__c: l.Expiration_Date__c, Sponsorship__c: l.Sponsorship__c, Last_Renewed__c: l.Last_Renewed__c }
            : { Employee__c: this.emp.Id, Status__c: 'Active', Sponsorship__c: 'Sponsored' };
    }
    closeLicense() { this.licenseForm = undefined; }
    get showLicenseModal() { return !!this.licenseForm; }
    get licenseTitle() { return this.licenseForm && this.licenseForm.Id ? 'Edit ' + this.licenseForm.State__c + ' license' : 'Add license'; }
    draftLicense(e) { this.licenseForm = { ...this.licenseForm, [e.target.dataset.field]: e.detail.value }; }
    saveLicenseForm() {
        const rec = { ...this.licenseForm };
        Object.keys(rec).forEach((k) => { if (rec[k] === '') rec[k] = null; });
        saveLicense({ rec }).then(() => {
            this.licenseForm = undefined;
            this.toast('License saved', 'success', 'Licensed states updated.');
            this.reloadHr();
            this.reloadEmployee();
        }).catch((er) => this.fail(er));
    }

    openComp(e) {
        const id = e.currentTarget.dataset.id;
        const c = id ? this.hr.compensation.find((x) => x.Id === id) : null;
        this.compForm = c ? { ...c } : { Employee__c: this.emp.Id, Effective_Date__c: this.today, Pay_Type__c: 'Salary', Base_Per__c: 'Year' };
        delete this.compForm.Name;
    }
    closeComp() { this.compForm = undefined; }
    get showCompModal() { return !!this.compForm; }
    get compTitle() { return this.compForm && this.compForm.Id ? 'Edit comp entry' : 'Add comp entry'; }
    get compIsSaved() { return this.compForm && !!this.compForm.Id; }
    draftComp(e) {
        const f = e.target.dataset.field;
        let v = e.detail.value;
        if (['Base_Amount__c', 'LO_Comp_Bps__c', 'Per_Loan_Flat__c'].includes(f)) v = v === '' || v == null ? null : Number(v);
        this.compForm = { ...this.compForm, [f]: v };
    }
    saveCompForm() {
        const rec = { ...this.compForm };
        Object.keys(rec).forEach((k) => { if (rec[k] === '') rec[k] = null; });
        saveComp({ rec }).then(() => { this.compForm = undefined; this.toast('Comp entry saved'); this.reloadHr(); }).catch((er) => this.fail(er));
    }
    removeComp() {
        // eslint-disable-next-line no-alert
        if (!window.confirm('Delete this comp entry? History is kept by adding new entries, so delete only mistakes.')) return;
        deleteComp({ compId: this.compForm.Id }).then(() => { this.compForm = undefined; this.reloadHr(); }).catch((er) => this.fail(er));
    }

    // ---------- Compliance tab ----------
    loadCompliance() {
        getCompliance().then((c) => { this.compliance = c; }).catch((e) => this.fail(e));
    }
    get complianceTitle() { return this.compliance ? 'Annual Compliance ' + this.compliance.year : 'Annual Compliance'; }
    get complianceColumns() { return this.compliance ? this.compliance.columns.map((name, i) => ({ key: 'c' + i, name })) : []; }
    get complianceRows() {
        if (!this.compliance) return [];
        const label = { done: 'Done', open: 'Open', overdue: 'Overdue', na: '—' };
        return this.compliance.rows.map((r) => ({
            ...r,
            cells: r.cells.map((c, i) => ({ key: r.employeeId + i, cls: 'cell cell-' + c.status, text: c.detail || label[c.status] }))
        }));
    }
    get hasComplianceRows() { return this.complianceRows.length > 0; }
    get expiringRows() {
        return (this.compliance ? this.compliance.expiring : []).map((l) => ({
            ...l,
            name: l.Employee__r ? l.Employee__r.Name : '',
            when: fmt(l.Expiration_Date__c) + ', ' + l.Expiration_Date__c.slice(0, 4),
            late: l.Expiration_Date__c < this.today
        }));
    }
    get hasExpiring() { return this.expiringRows.length > 0; }
    get missingRows() {
        if (!this.compliance) return [];
        return Object.keys(this.compliance.missing).map((id) => ({ id, name: this.compliance.names[id], items: this.compliance.missing[id].join(', ') }))
            .sort((a, b) => (a.name > b.name ? 1 : -1));
    }
    get hasMissingRows() { return this.missingRows.length > 0; }
    exportCompliance() {
        const c = this.compliance;
        const q = (v) => '"' + String(v == null ? '' : v).replace(/"/g, '""') + '"';
        const lines = [['Employee', 'Role'].concat(c.columns).map(q).join(',')]
            .concat(this.complianceRows.map((r) => [r.name, r.role].concat(r.cells.map((x) => x.text)).map(q).join(',')));
        const a = document.createElement('a');
        a.href = 'data:text/csv;charset=utf-8,' + encodeURIComponent('\ufeff' + lines.join('\r\n'));
        a.download = `annual-compliance-${c.year}.csv`;
        a.click();
    }

    // ---------- offboarding ----------
    openOffboard() { this.offboardForm = { lastDay: null, reason: 'Resigned' }; }
    closeOffboard() { this.offboardForm = undefined; }
    get showOffboardModal() { return !!this.offboardForm; }
    draftOffboard(e) { this.offboardForm = { ...this.offboardForm, [e.target.dataset.field]: e.detail.value }; }
    startOffboarding() {
        const f = this.offboardForm;
        this.busy = true;
        offboard({ employeeId: this.emp.Id, lastDay: f.lastDay || null, reason: f.reason }).then((checklistId) => {
            this.busy = false;
            this.offboardForm = undefined;
            this.toast('Offboarding started', 'success', 'Tasks are dated from the last day.');
            return this.openRecord(this.emp.Id, checklistId);
        }).catch((er) => { this.busy = false; this.fail(er); });
    }

    // ---------- branches ----------
    openNewBranch() { this.branchForm = { Status__c: 'Planning' }; }
    openEditBranch() {
        const b = this.detail.branch;
        this.branchForm = { Id: b.Id, Name: b.Name, State__c: b.State__c, Address__c: b.Address__c, Branch_NMLS_ID__c: b.Branch_NMLS_ID__c,
            Branch_Manager__c: b.Branch_Manager__c, Target_Open_Date__c: b.Target_Open_Date__c, Status__c: b.Status__c };
    }
    closeBranch() { this.branchForm = undefined; }
    get showBranchModal() { return !!this.branchForm; }
    get branchModalTitle() { return this.branchForm && this.branchForm.Id ? 'Edit ' + this.branchForm.Name : 'New Branch'; }
    draftBranch(e) { this.branchForm = { ...this.branchForm, [e.target.dataset.field]: e.detail.value }; }
    pickBranchManager(e) { this.branchForm = { ...this.branchForm, Branch_Manager__c: e.detail.recordId || null }; }
    saveBranchForm() {
        const rec = { ...this.branchForm };
        Object.keys(rec).forEach((k) => { if (rec[k] === '') rec[k] = null; });
        this.busy = true;
        saveBranch({ rec }).then((id) => {
            this.busy = false;
            this.branchForm = undefined;
            this.toast('Branch saved', 'success', rec.Target_Open_Date__c ? 'Branch checklist dated from the target open date.' : 'Add a target open date to start its checklist.');
            return this.openRecord(id);
        }).catch((er) => { this.busy = false; this.fail(er); });
    }
    editDetails() { if (this.detail.branch) this.openEditBranch(); else this.openEdit(); }
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
    get modalTitle() {
        return this.employeeModal === 'new' ? 'New Employee (onboarding)' : this.employeeModal === 'existing' ? 'Add existing employee' : 'Edit ' + this.emp.Name;
    }
    get isNewModal() { return this.employeeModal === 'new'; }
    get isExistingModal() { return this.employeeModal === 'existing'; }
    get showStatesPicker() { return this.employeeModal !== 'edit'; }
    get showStartDate() { return this.employeeModal !== 'existing'; }
    openExisting() {
        this.form = { Role__c: 'Loan Officer', Branch__c: '', Employment_Type__c: 'W-2 Employee', Schedule__c: 'Full-time' };
        this.employeeModal = 'existing';
    }
    pickUser(e) { this.form = { ...this.form, User__c: e.detail.recordId || null }; }
    get showEmployeeModal() { return !!this.employeeModal; }
    get saveLabel() { return this.isNewModal ? 'Create and generate tasks' : this.isExistingModal ? 'Add employee' : 'Save'; }
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
            Personal_Email__c: e.Personal_Email__c, NMLS_ID__c: e.NMLS_ID__c, Licensed_States__c: e.Licensed_States__c,
            Termination_Date__c: e.Termination_Date__c, Termination_Reason__c: e.Termination_Reason__c, Title__c: e.Title__c,
            Department__c: e.Department__c, Employment_Type__c: e.Employment_Type__c, Schedule__c: e.Schedule__c, Hire_Date__c: e.Hire_Date__c
        };
        delete this.form.Licensed_States__c; // licenses own the states now (P4-15)
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
        if (this.isExistingModal) {
            addExistingEmployee({ employee: rec }).then((id) => {
                this.employeeModal = undefined;
                this.toast('Employee added', 'success', 'No onboarding checklist; licenses created for the states entered.');
                this.openRecord(id);
            }).catch((e) => this.fail(e));
        } else if (this.isNewModal) {
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
                this.reloadHr();
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
        return getTemplates({ checklistType: this.templateType }).then((t) => { this.templates = t; this.loading = false; }).catch((e) => this.fail(e));
    }
    get templateRows() {
        return this.templates.map((t, i) => ({
            ...t,
            num: i + 1,
            rowCls: 'tpl-row' + (t.Active__c ? '' : ' tpl-inactive') + (this.dragId === t.Id ? ' tpl-drag' : ''),
            offsetLabel: t.Offset_Days__c == null ? 'No due date' : t.Offset_Days__c === 0 ? 'Same day as ' + this.anchorHelp
                : (t.Offset_Days__c > 0 ? '+' : '') + t.Offset_Days__c + (t.Offset_Unit__c === 'Calendar Days' ? ' days' : ' bd'),
            roles: t.Roles__c ? t.Roles__c.split(';').join(', ') : 'All roles',
            arrangements: t.Work_Arrangements__c ? t.Work_Arrangements__c.split(';').join(', ') : 'All arrangements',
            who: t.Default_Assignee__r ? t.Default_Assignee__r.Name : 'Unassigned',
            tags: [t.Optional__c ? 'Optional' : null, t.Active__c ? null : 'Inactive', t.Email_Template__c, t.Via_DocuSign__c ? 'DocuSign' : null, t.Sets_Status__c ? '→ ' + t.Sets_Status__c : null,
                t.Remind__c ? 'Email reminder' : null, t.Auto_Complete__c ? 'Auto: ' + t.Auto_Complete__c : null]
                .filter(Boolean).join(' · ')
        }));
    }
    get templateTypes() {
        return TYPES.map((value) => ({ value, label: TYPE_LABEL[value], pressed: String(this.templateType === value), cls: 'seg' + (this.templateType === value ? ' seg-on' : '') }));
    }
    pickTemplateType(e) { this.templateType = e.currentTarget.dataset.value; this.loadTemplates(); }
    get templatePhaseOptions() { return opts(PHASES_BY_TYPE[this.templateDraft ? this.templateDraft.Checklist_Type__c : this.templateType]); }
    get isRenewalTemplate() { return this.templateDraft && this.templateDraft.Checklist_Type__c === 'Renewal'; }
    get isPerStateDraft() { return this.isRenewalTemplate && this.templateDraft.Per_State__c; }
    get anchorHelp() {
        return { Onboarding: 'start date', Offboarding: 'last day', Renewal: 'Dec 31 of the compliance year', Branch: 'target open date' }[this.templateType];
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
        this.templateDraft = { Checklist_Type__c: this.templateType, Phase__c: PHASES_BY_TYPE[this.templateType][0], Active__c: true, Optional__c: false,
            Via_DocuSign__c: false, Remind__c: false, Per_State__c: false, Default_Assignee__c: USER_ID,
            Offset_Unit__c: this.templateType === 'Renewal' ? 'Calendar Days' : 'Business Days' };
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
