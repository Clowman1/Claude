import { LightningElement, track } from 'lwc';
import scheduleSmsJobs from '@salesforce/apex/RingCentralSmsScheduler.scheduleSmsJobs';


export default class RingCentralSchedulerForUser extends LightningElement {
    @track message;

    handleSchedule() {
        scheduleSmsJobs()
            .then(result => {
                this.message = result;
            })
            .catch(error => {
                this.message = error.body.message;
            });
    }
}