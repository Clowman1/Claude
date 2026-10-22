import { LightningElement, api } from 'lwc';
import getGateState from '@salesforce/apex/ExternalLoWorkspaceController.getGateState';
import attestOutlook from '@salesforce/apex/ExternalLoWorkspaceController.attestOutlook';
import { reduceApexError } from 'c/portalUtils';

const PILL = {
    green: { text: 'Connected', cls: 'pill pill-green' },
    red: { text: 'Not connected yet', cls: 'pill pill-red' },
    waived: { text: 'Not needed', cls: 'pill pill-muted' }
};

export default class LoWsConnectGate extends LightningElement {
    @api state;
    busy = false;
    error;

    get greeting() {
        return this.state?.firstName ? `Let's get you connected, ${this.state.firstName}!` : "Let's get you connected!";
    }

    get passed() {
        return this.state?.passed === true;
    }

    get missingText() {
        return (this.state?.missing || []).join(', ');
    }

    get hasMissing() {
        return (this.state?.missing || []).length > 0;
    }

    get rows() {
        return (this.state?.rows || []).map((r) => {
            const optionalRed = !r.required && r.status === 'red';
            const pill = optionalRed ? { text: 'Recommended', cls: 'pill pill-muted' } : PILL[r.status] || PILL.red;
            const open = r.status === 'red';
            return {
                ...r,
                pillText: pill.text,
                pillClass: pill.cls,
                rowClass: `gate-row gate-row-${optionalRed ? 'optional' : r.status}`,
                showHelp: open,
                showAttest: open && r.key === 'Outlook',
                showConnect: open && !!r.actionUrl,
                showCheck: open && r.key !== 'Outlook'
            };
        });
    }

    async run(call) {
        this.busy = true;
        this.error = undefined;
        try {
            this.state = await call();
        } catch (e) {
            this.error = reduceApexError(e);
        } finally {
            this.busy = false;
        }
    }

    handleCheck() {
        this.run(getGateState);
    }

    handleAttest() {
        this.run(attestOutlook);
    }

    handleConnect(event) {
        window.open(event.currentTarget.dataset.url, '_blank');
    }

    handleContinue() {
        this.dispatchEvent(new CustomEvent('passed'));
    }
}