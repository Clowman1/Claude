// LO Workspace guided tour (O4b): how the tour finds things inside other components.
// Every component has its own shadow root, so c-lo-ws-tour cannot querySelector into them.
// Instead the tour fires one window event per hook; the component whose template holds
// [data-tour="<hook>"] answers by writing the element's rect (or clicking it) into event.detail.
// A component opts in with one line in connectedCallback: registerTourHooks(this).

const EVENT = 'lowstourquery';
const hooked = new WeakSet();

export function registerTourHooks(cmp) {
    if (hooked.has(cmp)) {
        return;
    }
    hooked.add(cmp);
    const handler = (event) => {
        // ponytail: no disconnectedCallback needed; a removed component drops its listener on the next query.
        if (!cmp.template.host.isConnected) {
            window.removeEventListener(EVENT, handler);
            hooked.delete(cmp);
            return;
        }
        const d = event.detail;
        if (!d || d.rect || d.clicked) {
            return;
        }
        const el = cmp.template.querySelector(`[data-tour="${d.hook}"]`);
        if (!el) {
            return;
        }
        if (d.click) {
            el.click();
            d.clicked = true;
            return;
        }
        if (d.scroll && el.scrollIntoView) {
            el.scrollIntoView({ block: 'center', inline: 'nearest' });
        }
        const r = el.getBoundingClientRect();
        if (r.width > 0 || r.height > 0) {
            d.rect = { top: r.top, left: r.left, width: r.width, height: r.height };
        }
    };
    window.addEventListener(EVENT, handler);
}

/** Tour side. options: { click: true } clicks the element; { scroll: true } scrolls it into view first. */
export function queryTourHook(hook, options = {}) {
    const detail = { hook, ...options };
    window.dispatchEvent(new CustomEvent(EVENT, { detail }));
    return detail;
}