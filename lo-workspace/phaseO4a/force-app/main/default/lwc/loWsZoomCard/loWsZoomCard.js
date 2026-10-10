import { LightningElement, api } from 'lwc';
import { isExperienceCloudContext } from 'c/portalUtils';

/**
 * "Schedule a Zoom" card body on the LO Workspace Overview of a lead, past client or realtor.
 * Reuses zoomMeetingAssistant (compact variant: Event, .ics and invite email unchanged), imported
 * on demand so the shared Partner Workspace bundle never loads it. Renders nothing in the portal;
 * the host supplies the card frame and title. Re-fires `scheduled` so the host can refresh.
 */
export default class LoWsZoomCard extends LightningElement {
    @api recordId;
    ctor;
    loadError = false;

    async connectedCallback() {
        if (isExperienceCloudContext() || this.ctor) return;
        try {
            const { default: ctor } = await import('c/zoomMeetingAssistant');
            this.ctor = ctor;
        } catch (e) {
            this.loadError = true;
        }
    }

    handleScheduled(event) {
        this.dispatchEvent(new CustomEvent('scheduled', { detail: event.detail }));
    }
}
