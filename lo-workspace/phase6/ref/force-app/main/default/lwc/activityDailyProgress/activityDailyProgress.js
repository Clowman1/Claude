import { LightningElement, api } from 'lwc';
import getActivitySummary from '@salesforce/apex/OutsideLOActivityPageController.getActivitySummary';

export default class ActivityDailyProgress extends LightningElement {

    data;

    connectedCallback() {
        this.fetchData();
    }

    fetchData() {
        getActivitySummary().then((result) => {
            try {
                let data = result;
                data['totalProgress'] = data.dailyGoal.all > 0 ? String((data.dailyCompleted.all / data.dailyGoal.all) * 100) : "100";
                data['allCompletedIcon'] = data.dailyCompleted.all >= data.dailyGoal.all ? { name: 'utility:success', class: 'light-green-utility-icon slds-m-right_xx-small' } : {  name: 'utility:steps', class: 'light-yellow-utility-icon slds-m-right_xx-small'  };
                data['callsCompletedIcon'] = data.dailyCompleted.calls >= data.dailyGoal.calls ? { name: 'utility:success', class: 'light-green-utility-icon slds-m-right_xx-small' } : {  name: 'utility:steps', class: 'light-yellow-utility-icon slds-m-right_xx-small'  };
                data['textsCompletedIcon'] = data.dailyCompleted.texts >= data.dailyGoal.texts ?  { name: 'utility:success', class: 'light-green-utility-icon slds-m-right_xx-small' } : {  name: 'utility:steps', class: 'light-yellow-utility-icon slds-m-right_xx-small'  };
                data['emailsCompletedIcon'] = data.dailyCompleted.emails >= data.dailyGoal.emails ?  { name: 'utility:success', class: 'light-green-utility-icon slds-m-right_xx-small' } : {  name: 'utility:steps', class: 'light-yellow-utility-icon slds-m-right_xx-small'  };
                data['meetingsCompletedIcon'] = data.dailyCompleted.meetings >= data.dailyGoal.meetings ?  { name: 'utility:success', class: 'light-green-utility-icon slds-m-right_xx-small' } : {  name: 'utility:steps', class: 'light-yellow-utility-icon slds-m-right_xx-small'  };
                data['openHousesCompletedIcon'] = data.dailyCompleted.openHouses >= data.dailyGoal.openHouses ?  { name: 'utility:success', class: 'light-green-utility-icon slds-m-right_xx-small' } : {  name: 'utility:steps', class: 'light-yellow-utility-icon slds-m-right_xx-small'  };

                this.data = result;

                console.log(JSON.stringify(result));
            } catch(e) {
                console.log(e.message);
            }
        }).catch((e) => {
            console.log("ERROR", e.message);
        })
    }

    @api refresh() {

        this.fetchData();
        console.log("REFRESHED");
    }
}