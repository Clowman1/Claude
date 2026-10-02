const INDUSTRY_CLASS = { Realtor: 're', CPA: 'cpa', 'Title Agent': 'ti', 'Insurance Agent': 'ins' };

export function industryClass(industry) {
    return 'chip ' + (INDUSTRY_CLASS[industry] || 'oth');
}

export function errorMessage(error) {
    if (!error) return 'Something went wrong.';
    if (error.body && error.body.message) return error.body.message;
    if (error.body && Array.isArray(error.body) && error.body.length) return error.body[0].message;
    return error.message || 'Something went wrong.';
}

export function duration(seconds) {
    if (!seconds) return '';
    return Math.floor(seconds / 60) + 'm ' + (seconds % 60) + 's';
}

export function formatPhone(digits) {
    if (!digits || digits.length !== 10) return digits || '';
    return '(' + digits.slice(0, 3) + ') ' + digits.slice(3, 6) + '-' + digits.slice(6);
}

export function whenLabel(value) {
    if (!value) return '';
    const d = new Date(value);
    const today = new Date();
    const yesterday = new Date();
    yesterday.setDate(today.getDate() - 1);
    const time = d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
    if (d.toDateString() === today.toDateString()) return 'Today ' + time;
    if (d.toDateString() === yesterday.toDateString()) return 'Yesterday ' + time;
    return d.toLocaleDateString([], { month: 'short', day: 'numeric' }) + ' ' + time;
}

// Salesforce Date fields arrive as 'YYYY-MM-DD'; parse as a local date, not UTC.
export function localDate(ymd) {
    if (!ymd) return null;
    const [y, m, d] = ymd.split('-').map(Number);
    return new Date(y, m - 1, d);
}

export function dayParts(ymd) {
    const d = localDate(ymd);
    if (!d) return { dow: '', day: '', label: '' };
    return {
        dow: d.toLocaleDateString([], { weekday: 'short' }),
        day: String(d.getDate()),
        label: d.toLocaleDateString([], { weekday: 'short', month: 'short', day: 'numeric' })
    };
}
// One event card row (Upcoming / Events / To confirm): day box, "time · venue", RSVP counts.
export function eventRow(e) {
    const d = dayParts(e.startDate);
    return {
        ...e, dow: d.dow, day: d.day,
        when: (e.timeLabel || '') + (e.location ? ' · ' + e.location : ''),
        who: e.partnerNames.join(', ') + (e.invited > e.partnerNames.length ? ' +' + (e.invited - e.partnerNames.length) : ''),
        rsvp: e.attending + ' attending · ' + e.awaiting + ' awaiting' + (e.declined ? ' · ' + e.declined + ' declined' : ''),
        boxCls: 'ev ' + (e.awaiting === 0 && e.attending > 0 ? 'ev-ok' : 'ev-wait')
    };
}
