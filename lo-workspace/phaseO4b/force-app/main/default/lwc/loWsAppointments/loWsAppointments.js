import { LightningElement, api } from 'lwc';
import { registerTourHooks } from 'c/loWsTourHooks';
import { NavigationMixin } from 'lightning/navigation';
import getMyEvents from '@salesforce/apex/LoWsCalendarService.getMyEvents';
import { PORTAL_VIEWS, dispatchPortalNavigate, reduceApexError, isExperienceCloudContext } from 'c/portalUtils';

const DAY_MS = 86400000;
const CARD_ROWS = 8;
const HOUR_PX = 48;
const DEFAULT_START_HOUR = 7;
const DEFAULT_END_HOUR = 21;
const MAX_CHIPS = 3;
const VIEWS = [
    { id: 'month', label: 'Month' },
    { id: 'week', label: 'Week' },
    { id: 'day', label: 'Day' }
];
// Colour by what the event is about (lead / loan / partner or client / other); all-day gets its own.
const TONE_BY_TYPE = { Lead: 'tone-lead', Transaction__c: 'tone-loan', Account: 'tone-account', Contact: 'tone-account' };

// ponytail: dates/times use the browser's time zone (the LO's own); no separate Salesforce user TZ handling.
function startOfDay(d) {
    const x = new Date(d);
    x.setHours(0, 0, 0, 0);
    return x;
}
function addDays(d, n) {
    const x = new Date(d);
    x.setDate(x.getDate() + n);
    return x;
}
function dayKey(d) {
    return `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
}
function timeLabel(d) {
    return d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
}
function minutesOfDay(d) {
    return d.getHours() * 60 + d.getMinutes();
}

/**
 * LO Workspace "Upcoming appointments" card (the LO's own Events, next 7 days) plus the Calendar modal:
 * Month (default; agenda list on phones), Week and Day views. Data: LoWsCalendarService.getMyEvents
 * (OwnerId = me, system mode), fetched per visible range (a month grid is 42 days, under the 62-day cap).
 * Parents call openCalendar() from their own button; hide-card shows only the modal.
 * Never runs in the Partner Workspace portal.
 */
export default class LoWsAppointments extends NavigationMixin(LightningElement) {
    @api hideCard = false;
    inPortal = isExperienceCloudContext();
    upcoming;
    error;

    calendarOpen = false;
    view = 'month';
    anchor = startOfDay(new Date());
    events = [];
    loading = false;
    calError;
    selected;
    popoverStyle = '';
    isPhone = false;

    connectedCallback() {
        registerTourHooks(this); // O4b guided tour (c/loWsTourHooks)
        if (!this.inPortal && !this.hideCard) this.loadUpcoming();
    }

    @api
    refresh() {
        if (!this.inPortal && !this.hideCard) this.loadUpcoming();
        if (this.calendarOpen) this.loadRange();
    }

    async loadUpcoming() {
        try {
            const now = new Date();
            const rows = await getMyEvents({ startAt: now.toISOString(), endAt: new Date(now.getTime() + 7 * DAY_MS).toISOString() });
            this.upcoming = rows.map((r) => this.shape(r));
            this.error = undefined;
        } catch (e) {
            this.upcoming = [];
            this.error = reduceApexError(e);
        }
    }

    shape(r) {
        const start = r.allDay && r.allDayDate ? new Date(`${r.allDayDate}T00:00:00`) : new Date(r.startAt);
        const end = r.allDay && r.allDayDate ? addDays(start, 1) : new Date(r.endAt);
        const time = r.allDay ? 'All day' : `${timeLabel(start)} – ${timeLabel(end)}`;
        return {
            ...r,
            key: r.id,
            start,
            end,
            dow: start.toLocaleDateString([], { weekday: 'short' }),
            day: start.getDate(),
            time,
            short: r.allDay ? '' : timeLabel(start).replace(':00', '').replace(' ', '').toLowerCase(),
            hasRelated: !!r.relatedId && !!r.relatedName,
            chipCls: `chip ${r.allDay ? 'tone-allday' : TONE_BY_TYPE[r.relatedType] || 'tone-other'}`
        };
    }

    // ------------------------------------------------ card

    get showCard() { return !this.inPortal && !this.hideCard; }
    get cardRows() { return (this.upcoming || []).slice(0, CARD_ROWS); }
    get hasCardRows() { return this.cardRows.length > 0; }
    get moreCount() { return Math.max(0, (this.upcoming || []).length - CARD_ROWS); }

    // ------------------------------------------------ calendar: navigation

    @api
    openCalendar() {
        if (this.inPortal) return;
        this.isPhone = typeof window !== 'undefined' && window.matchMedia && window.matchMedia('(max-width: 640px)').matches;
        this.view = 'month';
        this.anchor = startOfDay(new Date());
        this.calendarOpen = true;
        this.loadRange();
    }

    closeCalendar() {
        this.calendarOpen = false;
        this.selected = undefined;
    }

    get viewChips() {
        return VIEWS.map((v) => ({ ...v, pressed: String(v.id === this.view), cls: v.id === this.view ? 'pill pill-active' : 'pill' }));
    }

    handleView(event) {
        this.view = event.currentTarget.dataset.id;
        this.loadRange();
    }

    goToday() {
        this.anchor = startOfDay(new Date());
        this.loadRange();
    }

    goPrev() { this.step(-1); }
    goNext() { this.step(1); }

    step(direction) {
        const a = new Date(this.anchor);
        if (this.view === 'month') a.setMonth(a.getMonth() + direction, 1);
        else a.setDate(a.getDate() + direction * (this.view === 'week' ? 7 : 1));
        this.anchor = startOfDay(a);
        this.loadRange();
    }

    get range() {
        const a = this.anchor;
        if (this.view === 'month') {
            const first = new Date(a.getFullYear(), a.getMonth(), 1);
            const start = addDays(first, -first.getDay());
            return { start, end: addDays(start, 42) };
        }
        if (this.view === 'week') {
            const start = addDays(a, -a.getDay());
            return { start, end: addDays(start, 7) };
        }
        return { start: a, end: addDays(a, 1) };
    }

    get title() {
        const a = this.anchor;
        if (this.view === 'month') return a.toLocaleDateString([], { month: 'long', year: 'numeric' });
        if (this.view === 'day') return a.toLocaleDateString([], { weekday: 'short', month: 'short', day: 'numeric', year: 'numeric' });
        const { start } = this.range;
        const end = addDays(start, 6);
        const left = start.toLocaleDateString([], { month: 'short', day: 'numeric' });
        const right = end.toLocaleDateString([], start.getMonth() === end.getMonth() ? { day: 'numeric', year: 'numeric' } : { month: 'short', day: 'numeric', year: 'numeric' });
        return `${left} – ${right}`;
    }

    async loadRange() {
        const { start, end } = this.range;
        this.loading = true;
        this.selected = undefined;
        try {
            const rows = await getMyEvents({ startAt: start.toISOString(), endAt: end.toISOString() });
            this.events = rows.map((r) => this.shape(r));
            this.calError = undefined;
        } catch (e) {
            this.events = [];
            this.calError = reduceApexError(e);
        } finally {
            this.loading = false;
        }
    }

    eventsOn(day) {
        const dayStart = day.getTime();
        const dayEnd = addDays(day, 1).getTime();
        return this.events.filter((e) => e.start.getTime() < dayEnd && e.end.getTime() > dayStart);
    }

    // ------------------------------------------------ month view

    get isMonth() { return this.view === 'month'; }
    get isMonthGrid() { return this.isMonth && !this.isPhone; }
    get isMonthAgenda() { return this.isMonth && this.isPhone; }
    get weekdayLabels() {
        const sunday = addDays(new Date(2026, 0, 4), 0); // a Sunday
        return [0, 1, 2, 3, 4, 5, 6].map((i) => ({ key: i, label: addDays(sunday, i).toLocaleDateString([], { weekday: 'short' }) }));
    }

    get monthCells() {
        const { start } = this.range;
        const month = this.anchor.getMonth();
        const today = dayKey(new Date());
        const cells = [];
        for (let i = 0; i < 42; i++) {
            const d = addDays(start, i);
            const list = this.eventsOn(d);
            const outside = d.getMonth() !== month;
            const isToday = dayKey(d) === today;
            cells.push({
                key: dayKey(d),
                iso: d.toISOString(),
                num: d.getDate(),
                cls: `cell${outside ? ' cell-out' : ''}${isToday ? ' cell-today' : ''}`,
                numCls: isToday ? 'num num-today' : 'num',
                chips: list.slice(0, MAX_CHIPS),
                more: list.length > MAX_CHIPS ? list.length - MAX_CHIPS : 0
            });
        }
        return cells;
    }

    get monthAgenda() {
        const { start } = this.range;
        const month = this.anchor.getMonth();
        const days = [];
        for (let i = 0; i < 42; i++) {
            const d = addDays(start, i);
            if (d.getMonth() !== month) continue;
            const list = this.eventsOn(d);
            if (list.length) {
                days.push({ key: dayKey(d), iso: d.toISOString(), label: d.toLocaleDateString([], { weekday: 'long', month: 'short', day: 'numeric' }), events: list });
            }
        }
        return days;
    }
    get monthAgendaEmpty() { return this.monthAgenda.length === 0; }

    openDay(event) {
        event.stopPropagation();
        this.anchor = startOfDay(new Date(event.currentTarget.dataset.iso));
        this.view = 'day';
        this.loadRange();
    }

    // ------------------------------------------------ week / day time grid

    get isGrid() { return this.view === 'week' || this.view === 'day'; }

    get hourBounds() {
        let startHour = DEFAULT_START_HOUR;
        let endHour = DEFAULT_END_HOUR;
        for (const e of this.events) {
            if (e.allDay) continue;
            startHour = Math.min(startHour, e.start.getHours());
            const endH = e.end.getHours() + (e.end.getMinutes() > 0 ? 1 : 0);
            if (dayKey(e.end) === dayKey(e.start)) endHour = Math.max(endHour, endH);
            else endHour = 24;
        }
        return { startHour, endHour: Math.max(endHour, startHour + 1) };
    }

    get hours() {
        const { startHour, endHour } = this.hourBounds;
        const rows = [];
        for (let h = startHour; h < endHour; h++) {
            rows.push({ key: h, label: new Date(2026, 0, 1, h).toLocaleTimeString([], { hour: 'numeric' }) });
        }
        return rows;
    }

    get gridHeightStyle() {
        const { startHour, endHour } = this.hourBounds;
        return `height:${(endHour - startHour) * HOUR_PX}px`;
    }

    get gridColsStyle() {
        return `grid-template-columns: 56px repeat(${this.gridDays.length}, minmax(0, 1fr))`;
    }

    get gridDays() {
        const { start } = this.range;
        const count = this.view === 'week' ? 7 : 1;
        const today = dayKey(new Date());
        const { startHour, endHour } = this.hourBounds;
        const days = [];
        for (let i = 0; i < count; i++) {
            const d = addDays(start, i);
            const list = this.eventsOn(d);
            const timed = list.filter((e) => !e.allDay).sort((x, y) => x.start - y.start);
            // ponytail: lanes are per day (widest overlap sets every event's width); per-cluster lanes if it looks cramped.
            const laneEnds = [];
            const placed = timed.map((e) => {
                const s = Math.max(e.start.getTime(), d.getTime());
                const en = Math.min(e.end.getTime(), addDays(d, 1).getTime());
                let lane = laneEnds.findIndex((t) => t <= s);
                if (lane === -1) {
                    lane = laneEnds.length;
                    laneEnds.push(en);
                } else {
                    laneEnds[lane] = en;
                }
                return { e, s, en, lane };
            });
            const lanes = Math.max(1, laneEnds.length);
            const blocks = placed.map(({ e, s, en, lane }) => {
                const startMin = Math.max(minutesOfDay(new Date(s)), startHour * 60);
                const endMin = en >= addDays(d, 1).getTime() ? endHour * 60 : Math.min(minutesOfDay(new Date(en)), endHour * 60);
                const top = ((startMin - startHour * 60) / 60) * HOUR_PX;
                const height = Math.max(((endMin - startMin) / 60) * HOUR_PX, 22);
                return {
                    ...e,
                    blockCls: `block ${e.chipCls.replace('chip ', '')}`,
                    blockStyle: `top:${top}px;height:${height}px;left:calc(${(100 / lanes) * lane}% + 2px);width:calc(${100 / lanes}% - 4px)`
                };
            });
            days.push({
                key: dayKey(d),
                iso: d.toISOString(),
                label: d.toLocaleDateString([], this.view === 'week' ? { weekday: 'short', day: 'numeric' } : { weekday: 'long', month: 'short', day: 'numeric' }),
                headCls: dayKey(d) === today ? 'col-head col-head-today' : 'col-head',
                allDay: list.filter((e) => e.allDay),
                blocks
            });
        }
        return days;
    }

    get hasAllDay() {
        return this.gridDays.some((d) => d.allDay.length);
    }

    // ------------------------------------------------ popover + navigation

    openEventDetail(event) {
        event.stopPropagation();
        const id = event.currentTarget.dataset.id;
        this.selected = this.events.find((e) => e.id === id);
        const x = Math.min(Math.max(event.clientX, 16), window.innerWidth - 300);
        const y = Math.min(Math.max(event.clientY + 8, 16), window.innerHeight - 220);
        this.popoverStyle = `left:${x}px;top:${y}px`;
    }

    closeDetail() { this.selected = undefined; }
    stop(event) { event.stopPropagation(); }

    openSelectedRelated() {
        const e = this.selected;
        this.openRelatedRecord(e.relatedId, e.relatedType);
    }

    openSelectedEvent() {
        if (this.selected.relatedType === 'Campaign') {
            this.openRelatedRecord(this.selected.relatedId, 'Campaign');
            return;
        }
        const id = this.selected.id;
        this.closeCalendar();
        this.openRecord(id);
    }

    openRelated(event) {
        this.openRelatedRecord(event.currentTarget.dataset.id, event.currentTarget.dataset.type);
    }

    openEvent(event) {
        this.closeCalendar();
        this.openRecord(event.currentTarget.dataset.id);
    }

    // In-person events (Campaigns) open in the same RSVP tracker as Upcoming In-person Events; their record
    // page needs a BD-only controller. Leads and loans open inside the workspace; anything else on its record page.
    trackerId;

    closeTracker() {
        this.trackerId = null;
    }

    openRelatedRecord(id, type) {
        this.closeCalendar();
        if (type === 'Campaign') {
            this.trackerId = id;
            return;
        }
        if (type === 'Lead' || type === 'Transaction__c') {
            dispatchPortalNavigate(this, { view: type === 'Lead' ? PORTAL_VIEWS.LEADS : PORTAL_VIEWS.LOANS, recordId: id });
            return;
        }
        if (type === 'Account') {
            // The shell opens my past clients and realtors in the workspace; any other Account on its record page.
            dispatchPortalNavigate(this, { view: PORTAL_VIEWS.REALTORS, recordId: id, accountFallback: 'record' });
            return;
        }
        this.openRecord(id);
    }

    openRecord(recordId) {
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId, actionName: 'view' } });
    }
}