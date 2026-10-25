const USD = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 });
const STAGE_CLASS = {
    Target: 'oth', Contacted: 're', 'Meeting Booked': 'ti', 'Follow Up': 'ins',
    'Marketing Agreement Signed': 'cpa', 'Landing Page Launched & Tested': 'wait', Active: 'yes', Lost: 'no'
};

export function money(v) { return v == null ? '—' : USD.format(v); }
export function num(v) { return v == null ? '' : Number(v).toLocaleString('en-US'); }
export function pct(v) { return v == null ? '—' : v + '%'; }
export function stageClass(stage) { return 'chip ' + (STAGE_CLASS[stage] || 'oth'); }
export function recordUrl(objectApiName, id) { return '/lightning/r/' + objectApiName + '/' + id + '/view'; }

// Accepts 'YYYY-MM-DD' (Date fields, parsed as local) or an ISO datetime.
export function shortDate(value) {
    if (!value) return '';
    let d;
    if (/^\d{4}-\d{2}-\d{2}$/.test(value)) {
        const [y, m, day] = value.split('-').map(Number);
        d = new Date(y, m - 1, day);
    } else {
        d = new Date(value);
    }
    return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
}
