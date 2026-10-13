import LightningToast from 'lightning/toast';
import { loadStyle } from 'lightning/platformResourceLoader';
import INTER_FONT from '@salesforce/resourceUrl/InterFont';

export const PORTAL_VIEWS = {
    PERFECT_DAY: 'perfectDay',
    PROGRESS: 'progress',
    PERFECT_WEEK: 'perfectWeek',
    REALTOR_PROSPECTS: 'realtorProspects',
    REALTORS: 'realtors',
    // LO Workspace only (2026-10-08): tagged partners who are not realtors.
    OTHER_CONTACTS: 'otherContacts',
    PAST_CLIENTS: 'pastClients',
    IMPORT_DATA: 'importData',
    LEADS: 'leads',
    PRE_APPROVALS: 'preApprovals',
    NURTURED: 'nurtured',
    LOANS: 'loans'
};

const VIEW_VALUES = new Set(Object.values(PORTAL_VIEWS));

export function isPortalView(view) {
    return VIEW_VALUES.has(view);
}

/**
 * True on Experience Cloud / Partner Workspace; false in internal Lightning (LO Workspace).
 * Checked by host rather than importing @salesforce/community/Id, which fails to load outside a
 * site and would break every component that imports this module.
 */
export function isExperienceCloudContext() {
    return typeof window !== 'undefined' && /\.site\.com$/i.test(window.location.hostname);
}

/** Flow screen LWCs are reused in the portal wizard; never emit flow navigation on community. */
export function shouldUseFlowNavigation(portalMode = false) {
    return !portalMode && !isExperienceCloudContext();
}

export function parsePortalState(pageRef) {
    const state = pageRef?.state || {};
    const view = isPortalView(state.c__view) ? state.c__view : PORTAL_VIEWS.PERFECT_DAY;
    return {
        view,
        filter: state.c__filter || defaultFilterForView(view),
        recordId: state.c__recordId || null
    };
}

export function portalStatesEqual(left, right) {
    return (
        (left?.view || '') === (right?.view || '') &&
        (left?.filter || '') === (right?.filter || '') &&
        (left?.recordId || '') === (right?.recordId || '')
    );
}

export function portalHomePageRef(view, filter, recordId) {
    const state = { c__view: view || PORTAL_VIEWS.PERFECT_DAY };
    if (filter) {
        state.c__filter = filter;
    }
    if (recordId) {
        state.c__recordId = recordId;
    }
    if (!isExperienceCloudContext()) {
        // LO Workspace (internal Lightning): the shell lives on the LO_Workspace app page tab.
        return { type: 'standard__navItemPage', attributes: { apiName: LO_WORKSPACE_TAB }, state };
    }
    return {
        type: 'comm__namedPage',
        attributes: { name: 'Home' },
        state
    };
}

export const LO_WORKSPACE_TAB = 'LO_Workspace';

export function showPortalToast(component, title, message, variant) {
    LightningToast.show(
        {
            label: title,
            message: message || '',
            variant: variant || 'info',
            mode: 'dismissible'
        },
        component
    );
}

export function dispatchPortalNavigate(component, detail) {
    component.dispatchEvent(
        new CustomEvent('portalnavigate', {
            bubbles: true,
            composed: true,
            detail
        })
    );
}

export function reduceApexError(error) {
    if (!error) {
        return 'Something went wrong. Screenshot this and send it to an admin.';
    }
    const body = error.body;
    const parts = [];
    if (typeof body === 'string' && body.trim()) {
        parts.push(body);
    }
    if (Array.isArray(body)) {
        body.forEach((item) => {
            if (item?.message) {
                parts.push(item.message);
            }
        });
    }
    const message = body?.message;
    if (
        typeof message === 'string' &&
        message.trim() &&
        message !== 'Script-thrown exception' &&
        !message.toLowerCase().includes('internal server error')
    ) {
        parts.push(message);
    }
    (body?.pageErrors || []).forEach((item) => {
        if (item?.message) {
            parts.push(item.message);
        }
    });
    Object.values(body?.fieldErrors || {}).forEach((fieldErrors) => {
        (fieldErrors || []).forEach((item) => {
            if (item?.message) {
                parts.push(item.message);
            }
        });
    });
    (body?.output?.errors || []).forEach((item) => {
        if (item?.message) {
            parts.push(item.message);
        }
    });
    const combined = [...new Set(parts.filter(Boolean))].join(' ');
    if (combined) {
        return combined;
    }
    if (typeof error.message === 'string' && error.message && error.message !== 'Script-thrown exception') {
        return error.message;
    }
    return 'The record could not be saved. Screenshot this message and send it to an admin.';
}

export function readFormFields(root) {
    const values = {};
    if (!root) {
        return values;
    }
    root.querySelectorAll('[data-field]').forEach((input) => {
        values[input.dataset.field] = input.value;
    });
    return values;
}

export function defaultFilterForView(view) {
    switch (view) {
        case PORTAL_VIEWS.LEADS:
            return 'all';
        case PORTAL_VIEWS.OTHER_CONTACTS:
        case PORTAL_VIEWS.REALTORS:
            // Everything on my list; a touch-window default hid newly added and imported partners.
            return 'all';
        case PORTAL_VIEWS.REALTOR_PROSPECTS:
            return 'prospects';
        case PORTAL_VIEWS.PRE_APPROVALS:
            return 'all';
        case PORTAL_VIEWS.NURTURED:
            return 'nurture';
        case PORTAL_VIEWS.LOANS:
            return 'all';
        default:
            return null;
    }
}

const BADGE_TONES = {
    new: 'badge status-new',
    working: 'badge status-working',
    'pre-approval': 'badge status-working',
    nurture: 'badge status-nurture',
    'past-client': 'badge status-nurture',
    closed: 'badge badge-neutral'
};

export function toGenericListRow(row) {
    return {
        id: row.id,
        title: row.title,
        badges: (row.badges || []).map((badge) => ({
            key: badge.key,
            label: badge.label,
            toneClass: badge.toneClass || BADGE_TONES[badge.key] || 'badge badge-neutral'
        })),
        primary: row.primary,
        meta: row.meta,
        note: row.note,
        actions: (row.actions || []).map((action) => ({
            ...action,
            buttonClass: action.variant === 'brand' ? 'btn btn-brand' : 'btn btn-outline'
        }))
    };
}

/**
 * Inter is the Linked Prototype typeface. It is self-hosted as a static
 * resource so the portal does not depend on a Google Fonts CSP entry.
 * `@font-face` is document-scoped, so one load covers every portal
 * component, including those inside a shadow root.
 */
let portalFontRequest;

export function loadPortalFont(component) {
    if (!portalFontRequest) {
        portalFontRequest = loadStyle(component, INTER_FONT + '/inter.css').catch(() => {
            // Typography is cosmetic: fall back to the system stack rather than
            // block the workspace from rendering.
            portalFontRequest = undefined;
        });
    }
    return portalFontRequest;
}