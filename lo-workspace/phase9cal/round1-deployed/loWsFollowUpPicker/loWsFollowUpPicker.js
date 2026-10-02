import { LightningElement, api } from 'lwc';
import { isExperienceCloudContext } from 'c/portalUtils';

const GENERAL_PRESETS = [
    { id: 'tomorrow', label: 'Tomorrow' },
    { id: '3-days', label: 'In 3 days' },
    { id: 'next-week', label: 'Next week' },
    { id: 'date', label: 'Pick a date' }
];

function pad(n) {
    return String(n).padStart(2, '0');
}

function localDate(d) {
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

/**
 * "Follow-up" block for Log communication and Log an activity. Fires `change` with
 * { value, error }: value is the server's followUpOption (none | tomorrow | 3-days | next-week |
 * date:YYYY-MM-DD | exact:<ISO>), error is set while a required date/time is missing.
 * General = a Task with an 8 AM reminder (Up Next on Perfect Day). Exact = a calendar Event.
 * Exact time is hidden in the Partner Workspace portal (it has no calendar).
 */
export default class LoWsFollowUpPicker extends LightningElement {
    @api defaultMode = 'none'; // none | general
    mode;
    preset = 'tomorrow';
    dateValue = '';
    datetimeValue = '';
    allowExact = !isExperienceCloudContext();

    connectedCallback() {
        this.mode = this.defaultMode === 'general' ? 'general' : 'none';
        this.emit();
    }

    get modes() {
        const list = [
            { id: 'none', label: 'No follow-up' },
            { id: 'general', label: 'General follow-up' }
        ];
        if (this.allowExact) list.push({ id: 'exact', label: 'Exact time' });
        return list.map((m) => ({ ...m, pressed: String(m.id === this.mode), className: m.id === this.mode ? 'chip chip-active' : 'chip' }));
    }

    get presets() {
        return GENERAL_PRESETS.map((p) => ({ ...p, pressed: String(p.id === this.preset), className: p.id === this.preset ? 'chip chip-active' : 'chip' }));
    }

    get isGeneral() { return this.mode === 'general'; }
    get isExact() { return this.mode === 'exact'; }
    get isOnDate() { return this.isGeneral && this.preset === 'date'; }
    get minDate() { return localDate(new Date()); }
    get minDatetime() {
        const d = new Date();
        return `${localDate(d)}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
    }

    handleMode(event) { this.mode = event.currentTarget.dataset.id; this.emit(); }
    handlePreset(event) { this.preset = event.currentTarget.dataset.id; this.emit(); }
    handleDate(event) { this.dateValue = event.target.value; this.emit(); }
    handleDatetime(event) { this.datetimeValue = event.target.value; this.emit(); }

    emit() {
        let value = 'none';
        let error;
        if (this.mode === 'general') {
            value = this.preset;
            if (this.preset === 'date') {
                value = `date:${this.dateValue}`;
                if (!this.dateValue) error = 'Pick the follow-up date.';
            }
        } else if (this.mode === 'exact') {
            // datetime-local is the browser's local time; toISOString sends it to Apex as UTC.
            const at = this.datetimeValue ? new Date(this.datetimeValue) : null;
            value = at ? `exact:${at.toISOString()}` : 'exact:';
            if (!at) error = 'Pick the date and time for the follow-up.';
            else if (at.getTime() < Date.now()) error = 'Pick a follow-up time in the future.';
        }
        this.dispatchEvent(new CustomEvent('change', { detail: { value, error } }));
    }
}
