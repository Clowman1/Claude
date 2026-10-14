import { LightningElement, api } from 'lwc';
import markReviewed from '@salesforce/apex/PayrollReviewController.markReviewed';
import submitFeedback from '@salesforce/apex/PayrollReviewController.submitFeedback';

// Payroll Review body (2026-10-14), shared by the Command Center modal and the LO Workspace Volume drawer.
// Fires "done" after Looks good so the host can close itself; after a sent issue it stays open to confirm.
const MONEY = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' });
const WHOLE = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 });

function longDate(iso) {
    if (!iso) return '';
    const [y, m, d] = iso.split('-').map(Number);
    return new Date(y, m - 1, d).toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' });
}

export default class PayrollReview extends LightningElement {
    @api review;
    reporting = false;
    message = '';
    busy = false;
    error;
    sent = false;
    confirmed = false;

    get period() {
        return this.review?.Period__c;
    }
    get payDate() {
        return longDate(this.review?.Pay_Date__c);
    }
    get closes() {
        return longDate(this.review?.Review_Closes__c);
    }
    get total() {
        return MONEY.format(this.review?.Total__c || 0);
    }

    // Rows grouped under their Section__c heading, in load order; a subtotal only when there are 2+ sections.
    get sections() {
        const groups = [];
        (this.review?.Lines__r || []).forEach((l, i) => {
            const name = l.Section__c || '';
            let g = groups.find((x) => x.name === name);
            if (!g) {
                g = { key: `s${groups.length}`, name, rows: [], sum: 0 };
                groups.push(g);
            }
            g.sum += l.Commission__c || 0;
            g.rows.push({
                key: `r${i}`,
                loan: l.Loan__c,
                amount: l.Loan_Amount__c == null ? '' : WHOLE.format(l.Loan_Amount__c),
                bizDev: l.Biz_Dev__c,
                rate: l.Rate__c,
                commission: l.Commission__c == null ? '' : MONEY.format(l.Commission__c)
            });
        });
        const multi = groups.length > 1;
        return groups.map((g) => ({ ...g, showSubtotal: multi, subtotal: MONEY.format(g.sum) }));
    }

    get status() {
        if (this.sent) return 'Your issue was sent to Christopher and Bianca. They will follow up with you.';
        if (this.confirmed || this.review?.Status__c === 'Reviewed') return 'You confirmed this payroll looks good.';
        if (this.review?.Status__c === 'Disputed') return 'You reported an issue. You can send another below.';
        return '';
    }

    get showLooksGood() {
        return this.review?.Status__c === 'Not Reviewed' && !this.confirmed && !this.sent && !this.reporting;
    }

    startReport() {
        this.reporting = true;
        this.sent = false;
        this.error = undefined;
    }

    cancelReport() {
        this.reporting = false;
        this.message = '';
    }

    handleMessage(event) {
        this.message = event.target.value;
    }

    get sendDisabled() {
        return this.busy || !this.message.trim();
    }

    async looksGood() {
        this.busy = true;
        this.error = undefined;
        try {
            await markReviewed({ reviewId: this.review.Id });
            this.confirmed = true;
            this.dispatchEvent(new CustomEvent('done', { detail: 'Reviewed' }));
        } catch (e) {
            this.error = e?.body?.message || 'Could not save. Please try again.';
        } finally {
            this.busy = false;
        }
    }

    async send() {
        this.busy = true;
        this.error = undefined;
        try {
            await submitFeedback({ reviewId: this.review.Id, message: this.message });
            this.sent = true;
            this.reporting = false;
            this.message = '';
        } catch (e) {
            this.error = e?.body?.message || 'Could not send. Please try again.';
        } finally {
            this.busy = false;
        }
    }
}
