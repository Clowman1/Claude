import { LightningElement, api } from 'lwc';
import LOGO from '@salesforce/resourceUrl/Reach_Partner_Logo';
import LOGO_WHITE from '@salesforce/resourceUrl/Reach_Partner_Logo_White';

// Light DOM so the page-layout rules in partnerLogin.css can reach the Builder
// sections around it. Those rules only load on pages that use this component.
export default class PartnerLogin extends LightningElement {
    static renderMode = 'light';

    // hero | welcome | help | footer
    @api variant = 'hero';

    logo = LOGO;
    logoWhite = LOGO_WHITE;
    year = new Date().getFullYear();

    get isHero() {
        return this.variant === 'hero';
    }
    get isWelcome() {
        return this.variant === 'welcome';
    }
    get isHelp() {
        return this.variant === 'help';
    }
    get isFooter() {
        return this.variant === 'footer';
    }
}