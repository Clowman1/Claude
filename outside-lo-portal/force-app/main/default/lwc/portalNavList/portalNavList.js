import { LightningElement, api } from 'lwc';

export default class PortalNavList extends LightningElement {
    @api groups = [];

    handleNavClick(event) {
        const view = event.currentTarget.dataset.view;
        this.dispatchEvent(
            new CustomEvent('navselect', {
                detail: { view }
            })
        );
    }
}