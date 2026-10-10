import { LightningElement } from 'lwc';
import getVolume from '@salesforce/apex/LoWsVolumeService.getVolume';
import { reduceApexError } from 'c/portalUtils';

// Volume drawer (2026-10-08): fixed right-edge tab on the LO Workspace main screens.
// Figures load each time it opens, so they are never stale.
const MONEY = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 });

function units(n) {
    return `${n || 0} unit${n === 1 ? '' : 's'}`;
}

export default class LoWsVolumeDrawer extends LightningElement {
    open = false;
    loading = false;
    error;
    v;

    connectedCallback() {
        this._onKeydown = (event) => {
            if (event.key === 'Escape' && this.open) this.close();
        };
        window.addEventListener('keydown', this._onKeydown);
    }

    disconnectedCallback() {
        window.removeEventListener('keydown', this._onKeydown);
    }

    get drawerClass() {
        return this.open ? 'drawer drawer-open' : 'drawer';
    }

    get scrimClass() {
        return this.open ? 'scrim scrim-open' : 'scrim';
    }

    get expanded() {
        return String(this.open);
    }

    get hidden() {
        return String(!this.open);
    }

    async toggle() {
        if (this.open) {
            this.close();
            return;
        }
        this.open = true;
        this.loading = !this.v;
        this.error = undefined;
        try {
            this.v = await getVolume();
        } catch (e) {
            this.error = reduceApexError(e);
        } finally {
            this.loading = false;
        }
    }

    close() {
        this.open = false;
    }

    get ready() {
        return !!this.v && !this.error;
    }

    // ---------- Personalised header (v2) ----------

    get greeting() {
        const h = new Date().getHours();
        const part = h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening';
        return this.v?.firstName ? `${part}, ${this.v.firstName}` : part;
    }

    get headline() {
        const month = (this.v?.monthLabel || '').split(' ')[0];
        return month ? `Your ${month} volume` : 'Your volume';
    }

    get photoUrl() {
        // The default silhouette is less personal than an initial.
        const url = this.v?.photoUrl;
        return url && !url.includes('/profilephoto/005/') ? url : null;
    }

    get initial() {
        return (this.v?.firstName || '?').charAt(0).toUpperCase();
    }

    get pace() {
        const last = this.v?.closedLastMonthAmount || 0;
        return last > 0 ? (this.v?.closedMtdAmount || 0) / last : null;
    }

    get paceStyle() {
        const pct = this.pace == null ? 0 : Math.min(this.pace, 1) * 100;
        return `width: ${pct.toFixed(1)}%`;
    }

    get dayMarkStyle() {
        const d = this.v?.dayOfMonth || 0;
        const n = this.v?.daysInMonth || 30;
        return `left: ${((d / n) * 100).toFixed(1)}%`;
    }

    get paceLabel() {
        const day = `day ${this.v?.dayOfMonth || 0} of ${this.v?.daysInMonth || 30}`;
        if (this.pace == null) {
            return `Nothing closed in ${this.v?.lastMonthLabel || 'last month'} to compare · ${day}`;
        }
        return `${Math.round(this.pace * 100)}% of ${this.v.lastMonthLabel}'s total · ${day}`;
    }

    get monthLabel() {
        return this.v?.monthLabel;
    }
    get lastMonthLabel() {
        return this.v?.lastMonthLabel;
    }
    get closedMtd() {
        return MONEY.format(this.v?.closedMtdAmount || 0);
    }
    get closedMtdUnits() {
        return units(this.v?.closedMtdUnits);
    }
    get closedLast() {
        return MONEY.format(this.v?.closedLastMonthAmount || 0);
    }
    get closedLastUnits() {
        return units(this.v?.closedLastMonthUnits);
    }
    get preApproved() {
        return MONEY.format(this.v?.preApprovedAmount || 0);
    }
    get preApprovedUnits() {
        return units(this.v?.preApprovedUnits);
    }
    get newLeadsMtd() {
        return this.v?.newLeadsMtd ?? 0;
    }
    get newLeadsLast() {
        return `${this.v?.newLeadsLastMonth ?? 0} in ${this.v?.lastMonthLabel || 'last month'}`;
    }
    get realtorsMtd() {
        return this.v?.realtorsMtd ?? 0;
    }
    get realtorsLast() {
        return `${this.v?.realtorsLastMonth ?? 0} in ${this.v?.lastMonthLabel || 'last month'}`;
    }
}