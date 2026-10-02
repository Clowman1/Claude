import { LightningElement, api } from 'lwc';

export default class ExternalLoRecentLog extends LightningElement {
    @api entries = [];

    get items() {
        return this.entries || [];
    }

    get isEmpty() {
        return !this.items.length;
    }
}