import { LightningElement, api } from 'lwc';

const TONES = ['brand', 'teal', 'navy', 'warn', 'success', 'danger'];

/** Falls back to brand so an unknown catalog tone still renders a tile. */
function toneOf(row) {
    const tone = (row.tone || '').toLowerCase();
    return TONES.includes(tone) ? tone : 'brand';
}

export default class ExternalLoTodayPlan extends LightningElement {
    @api rows = [];

    get items() {
        return (this.rows || []).map((row) => {
            const tone = toneOf(row);
            // A weekly category is never split across working days, so it reads
            // against the whole week the way the plan defines it.
            const period = (row.cadence || '').toLowerCase() === 'weekly' ? 'this week' : 'today';
            const done = row.isWinning === true;
            return {
                ...row,
                iconClass: `plan-icon tone-${tone}`,
                fillClass: `fill tone-fill-${done ? 'success' : tone}`,
                paceClass: `pace ${done ? 'pace-done' : row.isCoaching ? 'pace-behind' : 'pace-on'}`,
                paceLabel: done ? 'Goal met' : row.isCoaching ? 'Behind pace' : 'On pace',
                countLabel: `${row.completed || 0} of ${row.goal || 0} ${row.unitNoun || ''} ${period}`.replace(/\s+/g, ' ').trim(),
                barStyle: `width:${row.percent || 0}%`
            };
        });
    }

    get isEmpty() {
        return !this.items.length;
    }

    handleLog(event) {
        this.dispatchEvent(
            new CustomEvent('logactivity', {
                detail: { activityKey: event.currentTarget.dataset.key }
            })
        );
    }
}