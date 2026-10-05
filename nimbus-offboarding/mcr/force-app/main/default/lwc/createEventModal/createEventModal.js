import { api } from 'lwc';
import LightningModal from 'lightning/modal';

export default class CreateEventModal extends LightningModal {
    @api content;
    @api start;
    @api end;
    @api activityType;

    get inputVariables() {
        return [
            {
                name: 'DefaultActivityType',
                type: 'String',
                value: this.activityType
            },
            {
                name: 'UiStart',
                type: 'DateTime',
                value: this.start
            },
            {
                name: 'UiEnd',
                type: 'DateTime',
                value: this.end
            }
        ];
    }
    
    handleStatusChange(event) {
        if (event.detail.status === 'FINISHED') {
            console.log("Closing flow");
            this.close('okay');
        } else {
            console.log(event.detail.status);
        }
    }

    handleOkay() {
        this.close('okay');
    }
}