import { LightningElement, api } from 'lwc';

export default class ExternalLoRecentLog extends LightningElement {
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