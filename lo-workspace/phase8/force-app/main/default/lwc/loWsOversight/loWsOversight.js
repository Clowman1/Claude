import { LightningElement } from 'lwc';
import getOverview from '@salesforce/apex/LoWsOversightController.getOverview';

const money = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 });
const when = new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });

const fmtMoney = (v) => (v === null || v === undefined ? '—' : money.format(v));
const vsGoal = (actual, goal) => (goal === null || goal === undefined ? `${actual} / not set` : `${actual} / ${goal}`);
const pct = (score) => (score ? `${score.totalCompleted} / ${score.totalGoal} (${score.percent || 0}%)` : '—');
const tone = (score) => {
    const p = score?.percent || 0;
    if (p >= 100) return 'slds-badge slds-theme_success';
    if (p >= 70) return 'slds-badge slds-theme_warning';
    return 'slds-badge slds-theme_error';
};

export default class LoWsOversight extends LightningElement {
    data;
    error;
    loading = true;
    includeInternal = false;
    selectedLo = '';

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        this.error = undefined;
        try {
            this.data = await getOverview({ includeInternal: this.includeInternal });
        } catch (e) {
            this.error = e?.body?.message || 'Could not load the oversight view.';
            this.data = undefined;
        } finally {
            this.loading = false;
        }
    }

    handleToggle(event) {
        this.includeInternal = event.target.checked;
        this.selectedLo = '';
        this.load();
    }

    handleLoChange(event) {
        this.selectedLo = event.detail.value;
    }

    handleRowClick(event) {
        const id = event.currentTarget.dataset.id;
        this.selectedLo = this.selectedLo === id ? '' : id;
    }

    get loOptions() {
        const opts = [{ label: 'All loan officers', value: '' }];
        (this.data?.los || []).forEach((lo) => opts.push({ label: lo.name, value: lo.userId }));
        return opts;
    }

    get hasLos() {
        return this.data?.los?.length > 0;
    }

    get rows() {
        return (this.data?.los || [])
            .filter((lo) => !this.selectedLo || lo.userId === this.selectedLo)
            .map((lo) => ({
                ...lo,
                label: lo.isOutside ? lo.name : `${lo.name} (internal)`,
                setupLabel: lo.onboardingComplete ? 'Complete' : 'Not finished',
                weekLabel: pct(lo.week),
                weekClass: tone(lo.week),
                monthLabel: pct(lo.month),
                monthClass: tone(lo.month),
                unitsLabel: vsGoal(lo.unitsClosedThisMonth, lo.monthlyUnitGoal),
                volumeLabel: `${fmtMoney(lo.volumeClosedThisMonth)} / ${lo.monthlyVolumeGoal == null ? 'not set' : fmtMoney(lo.monthlyVolumeGoal)}`,
                partnersLabel: vsGoal(lo.activePartners, lo.targetRealtorCount),
                activeVolumeLabel: fmtMoney(lo.activeLoanVolume),
                leadCells: lo.leadStages.map((c, i) => ({ key: `${lo.userId}-l${i}`, value: c.value })),
                tagCells: lo.tagStages.map((c, i) => ({ key: `${lo.userId}-t${i}`, value: c.value })),
                statusChips: lo.loanStatuses.map((c) => ({ key: `${lo.userId}-${c.label}`, label: `${c.label}: ${c.value}` })),
                weekCategories: (lo.week?.rows || []).map((r) => ({
                    key: `${lo.userId}-${r.activityKey}`,
                    label: r.shortLabel,
                    value: `${r.completed} / ${r.goal}`,
                    cls: tone(r)
                })),
                rowClass: lo.userId === this.selectedLo ? 'slds-is-selected oversight-row' : 'oversight-row'
            }));
    }

    get selectedRow() {
        return this.selectedLo ? this.rows[0] : null;
    }

    get landingLeads() {
        return (this.data?.landingLeads || [])
            .filter((l) => !this.selectedLo || l.userId === this.selectedLo)
            .map((l) => ({
                ...l,
                url: `/lightning/r/Lead/${l.id}/view`,
                arrivedLabel: l.arrivedAt ? when.format(new Date(l.arrivedAt)) : '',
                howLabel: l.takenOver ? 'Taken over' : 'Landing page'
            }));
    }

    get planChanges() {
        return (this.data?.planChanges || [])
            .filter((p) => !this.selectedLo || p.userId === this.selectedLo)
            .map((p) => ({ ...p, whenLabel: when.format(new Date(p.createdDate)) }));
    }

    get hasLandingLeads() {
        return this.landingLeads.length > 0;
    }

    get hasPlanChanges() {
        return this.planChanges.length > 0;
    }
}
