import { LightningElement, api } from 'lwc';
import saveOnboardingV2 from '@salesforce/apex/ExternalLoWorkspaceController.saveOnboardingV2';
import { reduceApexError } from 'c/portalUtils';
import EXTLO_ONBOARDING_TITLE from '@salesforce/label/c.ExtLO_Onboarding_Title';
import EXTLO_ONBOARDING_INTRO from '@salesforce/label/c.ExtLO_Onboarding_Intro';
import EXTLO_ONBOARDING_FOCUS_TITLE from '@salesforce/label/c.ExtLO_Onboarding_Focus_Title';
import EXTLO_ONBOARDING_FOCUS_COPY from '@salesforce/label/c.ExtLO_Onboarding_Focus_Copy';
import EXTLO_ONBOARDING_ACTIVITIES_TITLE from '@salesforce/label/c.ExtLO_Onboarding_Activities_Title';
import EXTLO_ONBOARDING_ACTIVITIES_COPY from '@salesforce/label/c.ExtLO_Onboarding_Activities_Copy';
import EXTLO_ONBOARDING_RHYTHM_TITLE from '@salesforce/label/c.ExtLO_Onboarding_Rhythm_Title';
import EXTLO_ONBOARDING_RHYTHM_COPY from '@salesforce/label/c.ExtLO_Onboarding_Rhythm_Copy';
import EXTLO_ONBOARDING_TARGETS_TITLE from '@salesforce/label/c.ExtLO_Onboarding_Targets_Title';
import EXTLO_ONBOARDING_TARGETS_COPY from '@salesforce/label/c.ExtLO_Onboarding_Targets_Copy';
import EXTLO_ONBOARDING_IMPORT_TITLE from '@salesforce/label/c.ExtLO_Onboarding_Import_Title';
import EXTLO_ONBOARDING_IMPORT_COPY from '@salesforce/label/c.ExtLO_Onboarding_Import_Copy';
import EXTLO_ONBOARDING_REVIEW_TITLE from '@salesforce/label/c.ExtLO_Onboarding_Review_Title';
import EXTLO_ONBOARDING_COMPLETE_CTA from '@salesforce/label/c.ExtLO_Onboarding_Complete_Cta';
import EXTLO_ONBOARDING_SKIP_IMPORT from '@salesforce/label/c.ExtLO_Onboarding_Skip_Import';
import EXTLO_ONBOARDING_DAILY_HINT from '@salesforce/label/c.ExtLO_Onboarding_Daily_Hint';

const STEPS = [
    { id: 'focus', label: 'Focus' },
    { id: 'activities', label: 'Activities' },
    { id: 'targets', label: 'Targets' },
    { id: 'rhythm', label: 'Rhythm' },
    { id: 'review', label: 'Review' },
    { id: 'import', label: 'Import' }
];

const WORKDAYS = [3, 4, 5, 6];

function dailyTarget(weekly, workdays) {
    const days = Math.min(7, Math.max(1, Number(workdays) || 5));
    const week = Number(weekly) || 0;
    if (week <= 0) {
        return 0;
    }
    return Math.ceil(week / days);
}

export default class ExternalLoOnboarding extends LightningElement {
    @api state;
    @api embedded = false;
    stepIndex = 0;
    selectedFocus;
    workdaysPerWeek = 5;
    // Monthly production goals (LO Workspace, 2026-10-01). Optional; blank keeps the saved value.
    monthlyUnitGoal;
    monthlyVolumeGoal;
    targetRealtorCount;
    planRows = [];
    saving = false;
    errorMessage;
    initialized = false;

    labels = {
        title: EXTLO_ONBOARDING_TITLE,
        intro: EXTLO_ONBOARDING_INTRO,
        focusTitle: EXTLO_ONBOARDING_FOCUS_TITLE,
        focusCopy: EXTLO_ONBOARDING_FOCUS_COPY,
        activitiesTitle: EXTLO_ONBOARDING_ACTIVITIES_TITLE,
        activitiesCopy: EXTLO_ONBOARDING_ACTIVITIES_COPY,
        rhythmTitle: EXTLO_ONBOARDING_RHYTHM_TITLE,
        rhythmCopy: EXTLO_ONBOARDING_RHYTHM_COPY,
        targetsTitle: EXTLO_ONBOARDING_TARGETS_TITLE,
        targetsCopy: EXTLO_ONBOARDING_TARGETS_COPY,
        importTitle: EXTLO_ONBOARDING_IMPORT_TITLE,
        importCopy: EXTLO_ONBOARDING_IMPORT_COPY,
        reviewTitle: EXTLO_ONBOARDING_REVIEW_TITLE,
        completeCta: EXTLO_ONBOARDING_COMPLETE_CTA,
        skipImport: EXTLO_ONBOARDING_SKIP_IMPORT,
        dailyHint: EXTLO_ONBOARDING_DAILY_HINT
    };

    renderedCallback() {
        if (this.initialized || !this.state) {
            return;
        }
        this.initialized = true;
        this.selectedFocus = this.state.businessFocus;
        this.workdaysPerWeek = this.state.workdaysPerWeek || this.state.activityPlan?.workdaysPerWeek || 5;
        this.monthlyUnitGoal = this.state.monthlyUnitGoal;
        this.monthlyVolumeGoal = this.state.monthlyVolumeGoal;
        this.targetRealtorCount = this.state.targetRealtorCount;
        this.planRows = (this.state.activityPlan?.rows || []).map((row) => ({
            activityKey: row.activityKey,
            shortLabel: row.shortLabel,
            unitNoun: row.unitNoun,
            description: row.description,
            iconName: row.iconName,
            weeklyTarget: row.weeklyTarget,
            isEnabled: row.isEnabled !== false
        }));
        if (this.selectedFocus) {
            this.applyFocusPresets(this.selectedFocus, false);
        }
    }

    get pageClass() {
        return this.embedded ? 'onboarding-page onboarding-page-embedded' : 'onboarding-page';
    }

    get steps() {
        return STEPS.map((step, index) => {
            const done = index < this.stepIndex;
            const active = index === this.stepIndex;
            return {
                ...step,
                index,
                isDone: done,
                marker: String(index + 1),
                isCurrent: active ? 'step' : null,
                showConnector: index < STEPS.length - 1,
                stepClass: active ? 'step step-active' : done ? 'step step-done' : 'step'
            };
        });
    }

    get stepNumber() {
        return this.stepIndex + 1;
    }

    get stepTotal() {
        return STEPS.length;
    }

    get isFirstStep() {
        return this.stepIndex === 0;
    }

    get isFocus() {
        return this.stepIndex === 0;
    }
    get isActivities() {
        return this.stepIndex === 1;
    }
    get isTargets() {
        return this.stepIndex === 2;
    }
    get isRhythm() {
        return this.stepIndex === 3;
    }
    get isReview() {
        return this.stepIndex === 4;
    }
    get isImport() {
        return this.stepIndex === 5;
    }

    get cannotContinue() {
        if (this.isFocus) {
            return !this.selectedFocus;
        }
        if (this.isActivities) {
            return !this.planRows.some((row) => row.isEnabled);
        }
        return false;
    }

    get focusOptions() {
        const catalog = this.state?.focuses;
        if (catalog && catalog.length) {
            return catalog.map((option) => ({
                id: option.label,
                label: option.label,
                description: option.description,
                isSelected: option.label === this.selectedFocus,
                optionClass: option.label === this.selectedFocus ? 'choice choice-active' : 'choice'
            }));
        }
        return (this.state?.focusOptions || []).map((option) => ({
            id: option,
            label: option,
            description: '',
            isSelected: option === this.selectedFocus,
            optionClass: option === this.selectedFocus ? 'choice choice-active' : 'choice'
        }));
    }

    get activityChoices() {
        return this.planRows.map((row) => ({
            ...row,
            optionClass: row.isEnabled ? 'choice choice-active' : 'choice',
            checkedLabel: row.isEnabled ? 'On' : 'Off'
        }));
    }

    get workdayOptions() {
        return WORKDAYS.map((days) => ({
            id: String(days),
            label: String(days),
            isSelected: days === this.workdaysPerWeek,
            optionClass: days === this.workdaysPerWeek ? 'choice choice-active workday-choice' : 'choice workday-choice'
        }));
    }

    get targetFields() {
        return this.enabledRows.map((row) => {
            const valid = Number.isFinite(row.weeklyTarget) && row.weeklyTarget >= 0 && row.weeklyTarget <= 200;
            const daily = valid ? dailyTarget(row.weeklyTarget, this.workdaysPerWeek) : null;
            return {
                ...row,
                dailyTarget: daily,
                dailyLabel: daily == null ? '' : `${daily} ${this.labels.dailyHint.toLowerCase()}`,
                decreaseLabel: `Decrease ${row.shortLabel} target`,
                increaseLabel: `Increase ${row.shortLabel} target`
            };
        });
    }

    get enabledRows() {
        return this.planRows.filter((row) => row.isEnabled);
    }

    get reviewRows() {
        return this.enabledRows.map((row) => ({
            ...row,
            dailyTarget: dailyTarget(row.weeklyTarget, this.workdaysPerWeek)
        }));
    }

    get reviewFocus() {
        return this.selectedFocus || '';
    }

    get reviewRhythm() {
        return `${this.workdaysPerWeek} workdays`;
    }

    areTargetsValid() {
        return this.enabledRows.every(
            (row) => Number.isFinite(row.weeklyTarget) && row.weeklyTarget >= 0 && row.weeklyTarget <= 200
        );
    }

    handleSelectFocus(event) {
        this.selectedFocus = event.currentTarget.dataset.focus;
        this.applyFocusPresets(this.selectedFocus, true);
        this.errorMessage = undefined;
    }

    applyFocusPresets(label, overwrite) {
        const focus = (this.state?.focuses || []).find((item) => item.label === label);
        const presets = focus?.weeklyPresets;
        if (!presets) {
            return;
        }
        this.planRows = this.planRows.map((row) => {
            const preset = presets[row.activityKey];
            if (preset == null || (!overwrite && row.weeklyTarget != null)) {
                return row;
            }
            return { ...row, weeklyTarget: Number(preset) };
        });
    }

    handleToggleActivity(event) {
        const activityKey = event.currentTarget.dataset.key;
        this.planRows = this.planRows.map((row) =>
            row.activityKey === activityKey ? { ...row, isEnabled: !row.isEnabled } : row
        );
        this.errorMessage = undefined;
    }

    handleWorkdays(event) {
        this.workdaysPerWeek = Number(event.currentTarget.dataset.days);
        this.errorMessage = undefined;
    }

    handleGoalChange(event) {
        const activityKey = event.currentTarget.dataset.key;
        const raw = event.target.value;
        const value = raw === '' || raw == null ? undefined : Number(raw);
        this.planRows = this.planRows.map((row) =>
            row.activityKey === activityKey
                ? { ...row, weeklyTarget: Number.isNaN(value) ? undefined : value }
                : row
        );
        this.errorMessage = undefined;
    }

    handleGoalBlur(event) {
        const activityKey = event.currentTarget.dataset.key;
        const raw = event.target.value;
        const parsed = raw === '' || raw == null ? NaN : Number(raw);
        if (!Number.isFinite(parsed)) {
            return;
        }
        const clamped = Math.max(0, Math.min(200, parsed));
        this.planRows = this.planRows.map((row) =>
            row.activityKey === activityKey ? { ...row, weeklyTarget: clamped } : row
        );
        this.errorMessage = undefined;
    }

    handleGoalStep(event) {
        const activityKey = event.currentTarget.dataset.key;
        const delta = Number(event.currentTarget.dataset.delta);
        this.planRows = this.planRows.map((row) => {
            if (row.activityKey !== activityKey) {
                return row;
            }
            const current = Number.isFinite(row.weeklyTarget) ? row.weeklyTarget : 0;
            return { ...row, weeklyTarget: Math.max(0, Math.min(200, current + delta)) };
        });
        this.errorMessage = undefined;
    }

    handleStepClick(event) {
        const index = Number(event.currentTarget.dataset.index);
        if (!Number.isFinite(index) || index === this.stepIndex) {
            return;
        }
        if (index > this.stepIndex && !this.canAdvanceTo(index)) {
            this.errorMessage = this.stepError();
            return;
        }
        this.stepIndex = index;
        this.errorMessage = undefined;
    }

    canAdvanceTo(targetIndex) {
        for (let step = this.stepIndex; step < targetIndex; step += 1) {
            if (!this.isStepComplete(step)) {
                return false;
            }
        }
        return true;
    }

    isStepComplete(index) {
        if (index === 0) {
            return !!this.selectedFocus;
        }
        if (index === 1) {
            return this.planRows.some((row) => row.isEnabled);
        }
        if (index === 2) {
            return this.areTargetsValid();
        }
        return true;
    }

    stepError() {
        if (!this.selectedFocus) {
            return 'Choose one area of business to focus on.';
        }
        if (!this.planRows.some((row) => row.isEnabled)) {
            return 'Keep at least one activity on.';
        }
        if (!this.areTargetsValid()) {
            return 'Enter a weekly target of 0 to 200 for each activity.';
        }
        return undefined;
    }

    handleNext() {
        this.errorMessage = undefined;
        if (!this.isStepComplete(this.stepIndex)) {
            this.errorMessage = this.stepError();
            return;
        }
        if (this.stepIndex < STEPS.length - 1) {
            this.stepIndex += 1;
        }
    }

    handleBack() {
        this.errorMessage = undefined;
        if (this.stepIndex > 0) {
            this.stepIndex -= 1;
        }
    }

    handleProductionGoal(event) {
        const raw = event.detail.value;
        this[event.target.dataset.field] = raw === '' || raw === null || raw === undefined ? null : Number(raw);
    }

    async handleFinish() {
        this.errorMessage = undefined;
        if (!this.selectedFocus || !this.areTargetsValid() || !this.planRows.some((row) => row.isEnabled)) {
            this.errorMessage = this.stepError();
            return;
        }
        this.saving = true;
        try {
            const state = await saveOnboardingV2({
                businessFocus: this.selectedFocus,
                workdaysPerWeek: this.workdaysPerWeek,
                completeOnboarding: true,
                monthlyUnitGoal: this.monthlyUnitGoal,
                monthlyVolumeGoal: this.monthlyVolumeGoal,
                targetRealtorCount: this.targetRealtorCount,
                goalsJson: JSON.stringify(
                    this.planRows.map((row) => ({
                        activityKey: row.activityKey,
                        weeklyTarget: row.weeklyTarget,
                        isEnabled: row.isEnabled
                    }))
                )
            });
            this.dispatchEvent(
                new CustomEvent('completed', {
                    bubbles: true,
                    composed: true,
                    detail: { state }
                })
            );
        } catch (error) {
            this.errorMessage = reduceApexError(error);
        } finally {
            this.saving = false;
        }
    }
}