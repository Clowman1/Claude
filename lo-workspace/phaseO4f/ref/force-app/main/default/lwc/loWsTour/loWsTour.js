import { LightningElement, api } from 'lwc';
import TOUR_ASSETS from '@salesforce/resourceUrl/LoWsTourAssets';
import getTourState from '@salesforce/apex/ExternalLoWorkspaceController.getTourState';
import saveTourProgress from '@salesforce/apex/ExternalLoWorkspaceController.saveTourProgress';
import skipTour from '@salesforce/apex/ExternalLoWorkspaceController.skipTour';
import saveTourResume from '@salesforce/apex/ExternalLoWorkspaceController.saveTourResume';
import { CHAPTERS, FULL_RUN_ID, SKIP_CONFIRM, stopsFor } from 'c/loWsTourSteps';
import { queryTourHook } from 'c/loWsTourHooks';

// LO Workspace guided tour with Bran the Mortgage Man (O4b). Rendered by externalLoPortalShell in LO Workspace
// only (never the Partner Workspace portal), desktop only. The shell owns the view: the tour asks it to move
// with a 'tournavigate' event and reads where it is from the view / record-id props.
// Finding targets: see c/loWsTourHooks (window event answered by the component that owns the data-tour hook).

const DESKTOP = '(min-width: 1024px)';
const POLL_MS = 200;
const WAIT_MS = 4000;
const PAD = 8;
const BRAN_H = 180;
const BRAN_W = 130;
const EDGE = 16;
const BUBBLE_W = 380;
const SHOT_W = 560;

const isDesktop = () => !window.matchMedia || window.matchMedia(DESKTOP).matches;
// eslint-disable-next-line @lwc/lwc/no-async-operation
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

export default class LoWsTour extends LightningElement {
    @api view;
    @api recordId;

    state = { chaptersSeen: [] };
    menuOpen = false;
    chapter;
    stops = [];
    index = 0;
    holes = [];
    mode = 'center'; // center | spot | shot
    target; // union rect of the holes
    confirmSkip = false;
    searching = false;
    autoRun = false;
    measureQueued = false;
    token = 0;
    focusPending = false;

    connectedCallback() {
        this.onKey = (e) => this.handleKey(e);
        this.onMove = () => this.scheduleMeasure();
        this.load();
    }

    disconnectedCallback() {
        this.stopListening();
    }

    async load() {
        try {
            this.state = await getTourState();
        } catch (e) {
            this.state = { chaptersSeen: [] };
        }
        // Decisions 4 + 17: the first run starts by itself right after the gate + setup Q&A (the shell mounts the
        // tour once setup is complete), and keeps doing so until the LO finishes or skips it.
        // O4c (Q68): a reload mid-way resumes at the stop the LO left.
        if (this.state?.autoLaunch && isDesktop() && !this.active) {
            this.start(FULL_RUN_ID, { auto: true, resumeStopId: this.state.resumeStopId });
        }
    }

    /** "Take the tour" (sidebar link and the ? on the Perfect Day banner). */
    @api
    openMenu() {
        if (!isDesktop()) {
            return;
        }
        this.end();
        this.menuOpen = true;
        this.focusPending = true;
        window.addEventListener('keydown', this.onKey);
    }

    // ------------------------------------------------------------------ menu

    get menuRows() {
        const seen = new Set(this.state?.chaptersSeen || []);
        return CHAPTERS.map((c) => {
            const count = stopsFor(c, this.state?.ringCentral).length;
            const done = seen.has(c.id);
            return {
                id: c.id,
                label: c.full ? `${c.title} (${count} stops)` : `Chapter ${c.id}: ${c.title}`,
                detail: c.full ? 'Start here' : `${count} stops`,
                done,
                rowClass: c.full ? 'menu-row menu-row-full' : 'menu-row',
                ariaLabel: `${c.title}, ${count} stops${done ? ', seen' : ''}`
            };
        });
    }

    handleMenuPick(event) {
        this.menuOpen = false;
        this.start(event.currentTarget.dataset.id);
    }

    closeMenu() {
        this.menuOpen = false;
        this.stopListening();
    }

    // ------------------------------------------------------------------ run

    get active() {
        return !!this.chapter;
    }

    get isFull() {
        return this.chapter?.full === true;
    }

    get stop() {
        return this.stops[this.index];
    }

    /** Menu replays always start at the first stop; only the first-login run (auto) resumes and saves its place. */
    start(chapterId, { auto = false, resumeStopId = null } = {}) {
        const chapter = CHAPTERS.find((c) => c.id === chapterId);
        if (!chapter) {
            return;
        }
        this.chapter = chapter;
        this.stops = stopsFor(chapter, this.state?.ringCentral);
        this.autoRun = auto;
        this.index = Math.max(0, resumeStopId ? this.stops.findIndex((st) => st.id === resumeStopId) : 0);
        this.confirmSkip = false;
        window.addEventListener('keydown', this.onKey);
        window.addEventListener('resize', this.onMove);
        window.addEventListener('scroll', this.onMove, true);
        this.show();
    }

    async show() {
        const token = ++this.token;
        const stop = this.stop;
        this.holes = [];
        this.target = null;
        this.mode = 'center';
        this.searching = !stop.shotAlways && (stop.hooks.length > 0 || !!stop.record);
        this.focusPending = true;

        const reached = await this.reach(stop, token);
        if (token !== this.token) {
            return;
        }
        let rects = null;
        if (reached && !stop.shotAlways && stop.hooks.length) {
            const hasData = !stop.need || (await this.poll(() => queryTourHook(stop.need).rect, token));
            if (hasData) {
                // First hit scrolls the first hook into view; then everything is measured in place.
                rects = await this.poll(() => this.measure(true), token);
                await sleep(60);
                rects = token === this.token ? this.measure(false) || rects : null;
            }
        }
        if (token !== this.token) {
            return;
        }
        this.searching = false;
        if (rects) {
            this.setHoles(rects);
            this.mode = 'spot';
        } else {
            this.mode = stop.shot ? 'shot' : 'center';
        }
    }

    /** Navigate the shell to the stop's page, open a record when the stop needs one, then click what it asks. */
    async reach(stop, token) {
        if (stop.view && (this.view !== stop.view || (!stop.record && this.recordId))) {
            this.dispatchEvent(new CustomEvent('tournavigate', { detail: { view: stop.view } }));
            await this.poll(() => this.view === stop.view && (stop.record || !this.recordId), token, 1500);
        }
        if (stop.record && !this.recordId) {
            const opened = await this.poll(() => queryTourHook('open-first', { click: true }).clicked, token);
            if (!opened || !(await this.poll(() => !!this.recordId, token, 2000))) {
                return false;
            }
        }
        for (const hook of stop.clicks || []) {
            // eslint-disable-next-line no-await-in-loop
            await this.poll(() => queryTourHook(hook, { click: true }).clicked, token, 2500);
        }
        return token === this.token;
    }

    measure(scroll) {
        const rects = [];
        this.stop.hooks.forEach((hook, i) => {
            const r = queryTourHook(hook, { scroll: scroll && i === 0 }).rect;
            if (r) {
                rects.push(r);
            }
        });
        return rects.length ? rects : null;
    }

    async poll(fn, token, ms = WAIT_MS) {
        const until = Date.now() + ms;
        for (;;) {
            if (token !== this.token) {
                return null;
            }
            const result = fn();
            if (result) {
                return result;
            }
            if (Date.now() > until) {
                return null;
            }
            // eslint-disable-next-line no-await-in-loop
            await sleep(POLL_MS);
        }
    }

    scheduleMeasure() {
        if (this.mode !== 'spot' || this.measureQueued) {
            return;
        }
        this.measureQueued = true;
        requestAnimationFrame(() => {
            this.measureQueued = false;
            const rects = this.mode === 'spot' ? this.measure(false) : null;
            if (rects) {
                this.setHoles(rects);
            }
        });
    }

    setHoles(rects) {
        this.holes = rects.map((r, i) => ({
            key: `h${i}`,
            x: Math.max(0, r.left - PAD),
            y: Math.max(0, r.top - PAD),
            w: r.width + PAD * 2,
            h: r.height + PAD * 2
        }));
        const left = Math.min(...this.holes.map((h) => h.x));
        const top = Math.min(...this.holes.map((h) => h.y));
        const right = Math.max(...this.holes.map((h) => h.x + h.w));
        const bottom = Math.max(...this.holes.map((h) => h.y + h.h));
        this.target = { left, top, right, bottom };
    }

    // ------------------------------------------------------------------ buttons

    runAfter() {
        for (const hook of this.stop?.after || []) {
            queryTourHook(hook, { click: true });
        }
    }

    handleNext() {
        if (this.index >= this.stops.length - 1) {
            this.handleDone();
            return;
        }
        this.runAfter();
        this.index += 1;
        this.saveResume();
        this.show();
    }

    handleBack() {
        if (this.index === 0) {
            return;
        }
        this.runAfter();
        this.index -= 1;
        this.saveResume();
        this.show();
    }

    /** Finish (full run) / Done (chapter: back to the menu). */
    handleDone() {
        const chapter = this.chapter;
        this.runAfter();
        this.save(chapter.id, chapter.full === true);
        this.end();
        if (!chapter.full) {
            this.openMenu();
        }
    }

    handleSkip() {
        if (!this.isFull) {
            // Exit chapter: back to the menu, nothing saved.
            this.runAfter();
            this.end();
            this.openMenu();
            return;
        }
        this.confirmSkip = true;
        this.focusPending = true;
    }

    keepGoing() {
        this.confirmSkip = false;
        this.focusPending = true;
    }

    confirmSkipTour() {
        // Script rule 4: skipping still counts the tour as seen for auto-launch (no tick on the full run).
        // O4c (Q67): a skip ends auto-launch but is not "tour done".
        this.runAfter();
        skipTour()
            .then((state) => {
                this.state = state;
            })
            .catch(() => {});
        this.end();
    }

    saveResume() {
        if (this.autoRun && this.stop) {
            saveTourResume({ stopId: this.stop.id }).catch(() => {}); // best effort: a lost save only means an earlier resume point
        }
    }

    async save(chapterId, finished) {
        try {
            this.state = await saveTourProgress({ chapterId, finished });
        } catch (e) {
            // Progress is a convenience: never trap the LO in the tour because a save failed.
            if (chapterId) {
                this.state = { ...this.state, chaptersSeen: [...(this.state?.chaptersSeen || []), chapterId] };
            }
        }
    }

    end() {
        this.token++;
        this.autoRun = false;
        this.chapter = null;
        this.stops = [];
        this.holes = [];
        this.confirmSkip = false;
        this.stopListening();
    }

    stopListening() {
        window.removeEventListener('keydown', this.onKey);
        window.removeEventListener('resize', this.onMove);
        window.removeEventListener('scroll', this.onMove, true);
    }

    handleKey(event) {
        if (this.menuOpen) {
            if (event.key === 'Escape') {
                this.closeMenu();
            } else if (event.key === 'Tab') {
                this.trapFocus(event, '.menu');
            }
            return;
        }
        if (!this.active) {
            return;
        }
        if (event.key === 'Escape') {
            event.preventDefault();
            if (this.confirmSkip) {
                this.keepGoing();
            } else {
                this.handleSkip();
            }
        } else if (event.key === 'Tab') {
            this.trapFocus(event, '.bubble');
        } else if (!this.confirmSkip && event.key === 'ArrowRight') {
            event.preventDefault();
            this.handleNext();
        } else if (!this.confirmSkip && event.key === 'ArrowLeft') {
            event.preventDefault();
            this.handleBack();
        }
    }

    trapFocus(event, selector) {
        const box = this.template.querySelector(selector);
        const items = box ? [...box.querySelectorAll('button')].filter((b) => !b.disabled) : [];
        if (!items.length) {
            return;
        }
        const first = items[0];
        const last = items[items.length - 1];
        const current = this.template.activeElement;
        if (event.shiftKey && (current === first || !items.includes(current))) {
            event.preventDefault();
            last.focus();
        } else if (!event.shiftKey && (current === last || !items.includes(current))) {
            event.preventDefault();
            first.focus();
        }
    }

    renderedCallback() {
        if (!this.focusPending) {
            return;
        }
        const el = this.template.querySelector('[data-autofocus]');
        if (el) {
            this.focusPending = false;
            el.focus();
        }
    }

    // ------------------------------------------------------------------ view model

    get showOverlay() {
        return this.active;
    }

    get counterLabel() {
        return `${this.index + 1} of ${this.stops.length}`;
    }

    get isFirst() {
        return this.index === 0;
    }

    get isLast() {
        return this.index === this.stops.length - 1;
    }

    get showLetsGo() {
        return this.isFull && this.isFirst;
    }

    get showBack() {
        return !this.isFirst;
    }

    get showNext() {
        return !this.isLast && !this.showLetsGo;
    }

    get showFinish() {
        return this.isLast;
    }

    get finishLabel() {
        return this.isFull ? 'Finish' : 'Done';
    }

    get showSkip() {
        return !this.isLast;
    }

    get skipLabel() {
        return this.isFull ? 'Skip tour' : 'Exit chapter';
    }

    get showName() {
        return !this.confirmSkip;
    }

    get bubbleText() {
        return this.confirmSkip ? SKIP_CONFIRM : this.stop?.text;
    }

    get poseUrl() {
        return `${TOUR_ASSETS}/poses/bran-${this.stop?.pose || 'waving'}.png`;
    }

    get headUrl() {
        return `${TOUR_ASSETS}/poses/bran-head.png`;
    }

    get showShot() {
        return this.mode === 'shot' && !!this.stop?.shot;
    }

    get shotUrl() {
        return `${TOUR_ASSETS}/screens/${this.stop?.shot}.jpg`;
    }

    get shotAlt() {
        return `Example screen for this step (${this.stop?.shot})`;
    }

    get overlayPath() {
        // Oversized outer rect, so a window resize never uncovers an edge.
        let d = 'M0 0H20000V20000H0Z';
        for (const hole of this.holes) {
            d += `M${hole.x} ${hole.y}h${hole.w}v${hole.h}h${-hole.w}Z`;
        }
        return d;
    }

    // Bran stands in the bottom corner nearest the target, unless the target sits in that corner.
    get branOnLeft() {
        const t = this.target;
        if (!t || this.mode !== 'spot') {
            return false;
        }
        const w = window.innerWidth;
        const h = window.innerHeight;
        let left = (t.left + t.right) / 2 < w / 2;
        const lowEnough = t.bottom > h - BRAN_H - EDGE * 2;
        if (lowEnough && left && t.left < BRAN_W + BUBBLE_W) {
            left = false;
        } else if (lowEnough && !left && t.right > w - BRAN_W - BUBBLE_W) {
            left = true;
        }
        return left;
    }

    get branClass() {
        return this.branOnLeft ? 'bran bran-left' : 'bran bran-right';
    }

    get bubbleClass() {
        if (this.mode !== 'spot') {
            return this.showShot ? 'bubble bubble-center bubble-shot' : 'bubble bubble-center';
        }
        return this.branOnLeft ? 'bubble bubble-left' : 'bubble bubble-right';
    }

    get bubbleStyle() {
        if (this.mode !== 'spot') {
            return `width:${this.showShot ? SHOT_W : BUBBLE_W}px`;
        }
        // Next to Bran, raised above the target when the target is low on the screen.
        const t = this.target;
        const h = window.innerHeight;
        let bottom = EDGE + 60;
        if (t && t.bottom > h - 260 && t.top > 240) {
            bottom = Math.min(h - t.top + EDGE, h - 220);
        }
        return `width:${BUBBLE_W}px;bottom:${bottom}px`;
    }
}