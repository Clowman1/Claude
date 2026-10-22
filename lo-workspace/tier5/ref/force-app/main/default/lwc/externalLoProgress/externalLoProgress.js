import { LightningElement, api, wire } from 'lwc';
import { registerTourHooks } from 'c/loWsTourHooks';
import { refreshApex } from '@salesforce/apex';
import getActivityRollup from '@salesforce/apex/ExternalLoPortalController.getActivityRollup';
import { reduceApexError } from 'c/portalUtils';

const PERIODS = [
    { id: 'week', label: 'Week', heading: 'This week' },
    { id: 'month', label: 'Month', heading: 'This month' },
    { id: 'quarter', label: 'Quarter', heading: 'This quarter' }
];

export default class ExternalLoProgress extends LightningElement {
    connectedCallback() {
        registerTourHooks(this); // O4b guided tour (c/loWsTourHooks)
    }

    payload;
    errorMessage;
    loading = true;
    period = 'week';
    wiredResult;
    _refreshKey;

    @api
    get refreshKey() {
        return this._refreshKey;
    }
    set refreshKey(value) {
        this._refreshKey = value;
        if (value && this.wiredResult) {
            refreshApex(this.wiredResult);
        }
    }

    @wire(getActivityRollup, { cacheBust: '$refreshKey' })
    wiredProgress(result) {
        this.wiredResult = result;
        this.loading = !result.data && !result.error;
        if (result.data) {
            this.payload = result.data;
            this.errorMessage = undefined;
            this.loading = false;
        } else if (result.error) {
            this.errorMessage = reduceApexError(result.error);
            this.loading = false;
        }
    }

    get periodTabs() {
        return PERIODS.map((item) => ({
            ...item,
            isActive: item.id === this.period,
            tabClass: item.id === this.period ? 'period-tab period-tab-active' : 'period-tab'
        }));
    }

    get periodHeading() {
        return PERIODS.find((item) => item.id === this.period)?.heading || 'This week';
    }

    get periodName() {
        return this.periodHeading.toLowerCase();
    }

    get focusLabel() {
        return this.payload?.businessFocus
            ? `Activity against the plan you set · Focus: ${this.payload.businessFocus}`
            : 'Activity against the plan you set';
    }

    get activePeriod() {
        return this.payload?.[this.period];
    }

    get activeRows() {
        return this.rowsFor(this.activePeriod);
    }

    get aheadRows() {
        return this.activeRows.filter((row) => row.pace === 'ahead');
    }

    get behindRows() {
        return this.activeRows.filter((row) => row.pace === 'behind');
    }

    get hasAhead() {
        return this.aheadRows.length > 0;
    }

    get hasBehind() {
        return this.behindRows.length > 0;
    }

    get overallPercent() {
        return this.activePeriod?.percent || 0;
    }

    handlePeriodClick(event) {
        this.period = event.currentTarget.dataset.period;
    }

    rowsFor(period) {
        return (period?.rows || []).map((row) => {
            const percent = row.percent || 0;
            const pace = row.pace || (percent >= 100 ? 'ahead' : 'on-track'); // from Apex: one pace rule everywhere
            return {
                key: row.activityKey,
                label: row.shortLabel,
                progressLabel: `${row.completed} / ${row.goal}`,
                shortfall: row.remaining,
                percent,
                pace,
                barStyle: `width:${percent}%`,
                fillClass: pace === 'ahead' ? 'fill fill-success' : 'fill',
                paceClass: `pace pace-${pace}`,
                paceLabel: pace === 'ahead' ? 'Goal met' : pace === 'on-track' ? 'On pace' : 'Behind pace',
                showCoaching: pace === 'behind',
                coachingNote: row.coachingNote
            };
        });
    }
}