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
        return `${this.v?.lastMonthLabel || 'Last month'}: ${this.v?.newLeadsLastMonth ?? 0}`;
    }
    get realtorsMtd() {
        return this.v?.realtorsMtd ?? 0;
    }
    get realtorsLast() {
        return `${this.v?.lastMonthLabel || 'Last month'}: ${this.v?.realtorsLastMonth ?? 0}`;
    }
}