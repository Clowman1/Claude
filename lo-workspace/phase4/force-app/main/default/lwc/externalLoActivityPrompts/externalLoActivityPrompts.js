import { LightningElement, api } from 'lwc';
import EXTLO_PROMPT_LOG from '@salesforce/label/c.ExtLO_Prompt_Log';
import EXTLO_PROMPT_TOMORROW from '@salesforce/label/c.ExtLO_Prompt_Tomorrow';

export default class ExternalLoActivityPrompts extends LightningElement {
    @api prompts = [];

    labels = {
        log: EXTLO_PROMPT_LOG,
        tomorrow: EXTLO_PROMPT_TOMORROW
    };

    get items() {
        return this.prompts || [];
    }

    get isEmpty() {
        return !this.items.length;
    }

    handleLog(event) {
        const promptKey = event.currentTarget.dataset.key;
        const prompt = this.items.find((item) => item.promptKey === promptKey);
        this.dispatchEvent(new CustomEvent('logprompt', { detail: { prompt } }));
    }

    handleSnooze(event) {
        const promptKey = event.currentTarget.dataset.key;
        const prompt = this.items.find((item) => item.promptKey === promptKey);
        this.dispatchEvent(new CustomEvent('snoozeprompt', { detail: { prompt } }));
    }
}