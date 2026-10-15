import { LightningElement, api } from 'lwc';
import markReviewed from '@salesforce/apex/PayrollReviewController.markReviewed';
import submitFeedback from '@salesforce/apex/PayrollReviewController.submitFeedback';

// Payroll Review body (2026-10-14), shared by the Command Center modal and the LO Workspace Volume drawer.
// Looks good / Report an issue until Feedback_Closes__c (the 8th), then view-only until the 11th.
// Fires "done" after Looks good so the host can close itself; after a sent issue it stays open to confirm.
const MONEY = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' });
const WHOLE = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 });

function longDate(iso) {
    if (!iso) return '';
    const [y, m, d] = iso.split('-').map(Number);
    return new Date(y, m - 1, d).toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' });
}

function todayIso() {
    const d = new Date();
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

export function feedbackOpen(review) {
    return !!review?.Feedback_Closes__c && review.Feedback_Closes__c >= todayIso();
}

// Hosts pop the review open on their own while this is true: not yet answered, or a dispute that
// Christopher/Bianca marked Resolved (so the LO can now accept it). Never after the 8th.
export function needsResponse(review) {
    const waiting = review?.Status__c === 'Not Reviewed' || (review?.Status__c === 'Disputed' && review?.Resolved__c);
    return feedbackOpen(review) && waiting;
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
    get feedbackBy() {
        return longDate(this.review?.Feedback_Closes__c);
    }
    get canRespond() {
        return feedbackOpen(this.review);
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
        if (this.confirmed || (!this.sent && this.review?.Status__c === 'Reviewed')) return 'You confirmed this payroll looks good.';
        if (this.sent) {
            return 'Your issue was sent to Christopher and Bianca. Once it is sorted out, click Looks good to accept this payroll.';
        }
        if (this.review?.Status__c === 'Disputed') {
            if (!this.canRespond) return 'You reported an issue.';
            return this.review.Resolved__c
                ? 'Your issue was marked resolved. If this payroll is right, click Looks good.'
                : 'You reported an issue. Once it is sorted out, click Looks good, or send another note.';
        }
        return '';
    }

    // Also offered after a dispute, so the LO can accept once it is sorted out.
    get showLooksGood() {
        return this.canRespond && !this.confirmed && !this.reporting && (this.sent || this.review?.Status__c !== 'Reviewed');
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
