import { LightningElement, api } from 'lwc';
import getActivitySummary from '@salesforce/apex/OutsideLOActivityPageController.getActivitySummary';

export default class ActivityWeeklyProgress extends LightningElement {

    totalVolume = 0; // 0
    totalGoal = 1; // 1

    data;
    weeklyProgress;

    connectedCallback() {
        this.fetchData();
    }

    fetchData() {
        getActivitySummary().then((result) => {
            let data = result;
            this.weeklyProgress = data.weeklyGoal.all > 0 ? ((data.weeklyCompleted.all / data.weeklyGoal.all) * 100) : 100;
            data['allCompletedIcon'] = data.weeklyCompleted.all >= data.weeklyGoal.all ? { name: 'utility:success', class: 'light-green-utility-icon slds-m-right_xx-small' } : {  name: 'utility:steps', class: 'light-yellow-utility-icon slds-m-right_xx-small'  };
            data['callsCompletedIcon'] = data.weeklyCompleted.calls >= data.weeklyGoal.calls ? { name: 'utility:success', class: 'light-green-utility-icon slds-m-right_xx-small' } : {  name: 'utility:steps', class: 'light-yellow-utility-icon slds-m-right_xx-small'  };
            data['textsCompletedIcon'] = data.weeklyCompleted.texts >= data.weeklyGoal.texts ?  { name: 'utility:success', class: 'light-green-utility-icon slds-m-right_xx-small' } : {  name: 'utility:steps', class: 'light-yellow-utility-icon slds-m-right_xx-small'  };
            data['emailsCompletedIcon'] = data.weeklyCompleted.emails >= data.weeklyGoal.emails ?  { name: 'utility:success', class: 'light-green-utility-icon slds-m-right_xx-small' } : {  name: 'utility:steps', class: 'light-yellow-utility-icon slds-m-right_xx-small'  };
            data['meetingsCompletedIcon'] = data.weeklyCompleted.meetings >= data.weeklyGoal.meetings ?  { name: 'utility:success', class: 'light-green-utility-icon slds-m-right_xx-small' } : {  name: 'utility:steps', class: 'light-yellow-utility-icon slds-m-right_xx-small'  };
            data['openHousesCompletedIcon'] = data.weeklyCompleted.openHouses >= data.weeklyGoal.openHouses ?  { name: 'utility:success', class: 'light-green-utility-icon slds-m-right_xx-small' } : {  name: 'utility:steps', class: 'light-yellow-utility-icon slds-m-right_xx-small'  };

            console.log(data['allCompletedIcon'].name, data['allCompletedIcon'].class);

            this.data = data;
        }).catch((e) => {
            console.log("ERROR", e.message);
        })
    }

    @api refresh() {
        this.fetchData();

        console.log("REFRESHED");
    }

    // get weeklyProgress() {
    //     return Math.min((this.totalVolume / this.totalGoal) * 100, 100);
    // }

    get chartUrl() {
        return "https://quickchart.io/chart?w=250&h=250&bkg=rgba(255%2C%20255%2C%20255%2C%200)&c=%7B%0A%20%20type%3A%20%27radialGauge%27%2C%0A%20%20data%3A%20%7B%0A%20%20%20%20datasets%3A%20%5B%7B%0A%20%20%20%20%20%20label%3A%20%27$" + this.formatCurrency(this.totalVolume) + "%20%2F%20$" + this.formatCurrency(this.totalGoal) + "%27%2C%0A%20%20%20%20%20%20data%3A%20%5B" + this.weeklyProgress + "%5D%2C%0A%20%20%20%20%20%20backgroundColor%3A%20getGradientFillHelper(%27horizontal%27%2C%20%5B%27%23778199%27%2C%20%27%231c2642%27%5D)%2C%0A%20%20%20%20%7D%5D%0A%20%20%7D%2C%0A%20%20options%3A%20%7B%0A%20%20%20%20title%3A%20%7B%0A%20%20%20%20%20%20display%3A%20false%2C%0A%20%20%20%20%20%20position%3A%20%27top%27%2C%0A%20%20%20%20%20%20fontSize%3A%20%2714%27%2C%0A%20%20%20%20%20%20text%3A%20%27Monthly%27%0A%20%20%20%20%7D%2C%0A%20%20%20%20legend%3A%20%7B%0A%20%20%20%20%20%20display%3A%20false%2C%0A%20%20%20%20%20%20position%3A%20%27top%27%2C%0A%20%20%20%20%20%20labels%3A%20%7B%0A%20%20%20%20%20%20%20%20color%3A%20%27black%27%2C%0A%20%20%20%20%20%20%20%20font%3A%20%7B%0A%20%20%20%20%20%20%20%20%20%20size%3A%2012%0A%20%20%20%20%20%20%20%20%7D%0A%20%20%20%20%20%20%7D%0A%20%20%20%20%7D%2C%0A%20%20%20%20domain%3A%20%5B0%2C%20100%5D%2C%0A%20%20%20%20animation%3A%20%7B%0A%20%20%20%20%20%20animateRotate%3A%20true%2C%0A%20%20%20%20%20animateScale%3A%20true%0A%20%20%20%20%7D%2C%0A%20%20%20%20trackColor%3A%20%27%23f0f8ff%27%2C%20%0A%20%20trackColor%3A%20%27rgb(204%2C%20221%2C%20238)%27%2C%0A%20%20roundedCorners%3A%20true%2C%0A%0A%20%20%20%20centerPercentage%3A%2060%2C%0A%20%20%20%20centerArea%3A%20%7B%0A%20%20%20%20%20%20text%3A%20(val)%20%3D%3E%20val%20%2B%20%27%25%27%2C%0A%20%20%20%20%7D%2C%0A%20%20%7D%0A%7D";
    }

    formatCurrency(value) {
        return value.toString().replace(/\B(?<!\.\d*)(?=(\d{3})+(?!\d))/g, ",");
    }

}