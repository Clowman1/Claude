import { LightningElement, api, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getDataFromFieldName from '@salesforce/apex/BorrowerDocumentPortalController.getDataFromFieldName';

export default class BorrowerPortalContactCard extends LightningElement {
    @track hashRecordId;
    @api contactFieldName;

    @track dataOutput;
    @track firstName;
    @track lastName;
    @track title;
    @track nmls;
    @track phone;
    @track email;
    @track error;
    @track headShotUrl;
    @track hasData;

    @wire(CurrentPageReference)
    getHashUrl(currentPageReference) {
        if (currentPageReference) {
            this.hashRecordId = currentPageReference.state?.id;
        }
    }

    async connectedCallback() {
        while (!this.hashRecordId || !this.contactFieldName) {
            await new Promise((resolve) => setTimeout(resolve, 10));
        }


        this.fetchData();
    }

    fetchData() {
        let root = this.template.host;
        getDataFromFieldName({ apiName: this.contactFieldName, hashUrl: this.hashRecordId })
            .then((data) => {
                if (data) {
                    this.firstName = data.FirstName;
                    this.lastName = data.LastName;
                    this.title = data.Title;
                    this.nmls = data.NMLS;
                    this.phone = data.Phone;
                    this.email = data.Email;
                    this.headShotUrl = data.HeadShotUrl;
                    root.style.setProperty('--hide-contact-card', 'visible');
                } else {
                    root.style.setProperty('--hide-contact-card', 'hidden');
                }
            })
            .catch((error) => {
                this.error = error;
                root.style.setProperty('--hide-contact-card', 'hidden');
            });
    }

    get fullName() {
        return `${this.firstName} ${this.lastName}`;
    }

    get nmlsText(){
        return this.nmls ?  'NMLS # ' + this.nmls : '';
    }
}