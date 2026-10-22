import { LightningElement, api } from 'lwc';
import { registerTourHooks } from 'c/loWsTourHooks';

export default class PortalNavList extends LightningElement {
    @api groups = [];

    connectedCallback() {
        registerTourHooks(this); // O4b: nav items answer the tour (data-tour="nav-<view>")
    }

    handleNavClick(event) {
        const view = event.currentTarget.dataset.view;
        this.dispatchEvent(
            new CustomEvent('navselect', {
                detail: { view }
            })
        );
    }
}