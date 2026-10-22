import { LightningElement, api } from 'lwc';
import { registerTourHooks } from 'c/loWsTourHooks';

export default class ExternalLoRecentLog extends LightningElement {
    connectedCallback() {
        registerTourHooks(this); // O4b guided tour (c/loWsTourHooks)
    }

    @api entries = [];

    get items() {
        // O3: 'text_reply' rows are Twilio replies (LoWsTextsService.withReplies): show the text and the
        // "Reply from your phone" hint instead of a count.
        return (this.entries || []).map((e) => {
            const isReply = e.activityKey === 'text_reply';
            return { ...e, isReply, showCount: !isReply };
        });
    }

    get isEmpty() {
        return !this.items.length;
    }
}