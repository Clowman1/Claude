import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getActivityRollup from '@salesforce/apex/ExternalLoPortalController.getActivityRollup';
import { reduceApexError } from 'c/portalUtils';

export default class ExternalLoPerfectWeek extends LightningElement {
    @api setupState;
    payload;
    errorMessage;
    loading = true;
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

    // Plans stay editable after setup (decision Q14): "Edit my plan" reopens the same wizard, pre-filled.
    editingPlan = false;

    get showWizard() {
        return Boolean(this.setupState) && (this.setupState.complete === false || this.editingPlan);
    }

    get canEditPlan() {
        return Boolean(this.setupState) && this.setupState.complete === true && !this.editingPlan;
    }

    handleEditPlan() {
        this.editingPlan = true;
    }

    handleCancelEdit() {
        this.editingPlan = false;
    }

    get pageSubtitle() {
        if (this.showWizard) {
            return 'Answer these questions once. We turn your answers into daily priorities you can log in two taps.';
        }
        return this.weekSummary;
    }

    get weekPercent() {
        return this.payload?.week?.percent || 0;
    }

    get weekSummary() {
        const week = this.payload?.week;
        if (!week) {
            return 'Set the activities and volumes that build your business. Everything on your dashboard is derived from this plan.';
        }
        return `${week.totalCompleted || 0} of ${week.totalGoal || 0} weekly activities logged`;
    }

    get rows() {
        return (this.payload?.week?.rows || []).map((row) => {
            const percent = row.percent || 0;
            const pace = percent >= 100 ? 'ahead' : percent >= 70 ? 'on-track' : 'behind';
            return {
                key: row.activityKey,
                label: row.shortLabel,
                progressLabel: `${row.completed} / ${row.goal}`,
                percent,
                barStyle: `width:${percent}%`,
                fillClass: pace === 'ahead' ? 'fill fill-success' : 'fill',
                paceClass: `pace pace-${pace}`,
                paceLabel: pace === 'ahead' ? 'Goal met' : pace === 'on-track' ? 'On pace' : 'Behind pace'
            };
        });
    }

    handleOnboardingCompleted(event) {
        this.editingPlan = false;
        this.dispatchEvent(
            new CustomEvent('completed', {
                bubbles: true,
                composed: true,
                detail: event.detail
            })
        );
    }
}