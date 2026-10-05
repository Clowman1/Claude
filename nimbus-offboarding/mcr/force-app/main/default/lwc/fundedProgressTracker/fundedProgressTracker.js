import { LightningElement, wire } from 'lwc';

import getVolumeProgress from '@salesforce/apex/FundedProgressTrackerController.getVolumeProgress';

export default class FundedProgressTracker extends LightningElement {
    annualVolume = 0;
    monthlyVolume = 0;
    quarterlyVolume = 0;
    annualGoal = 1; // Avoid division by zero
    monthlyGoal = 1;
    quarterlyGoal = 1;

    get annualProgress() {
        return Math.min((this.annualVolume / this.annualGoal) * 100, 100);
    }

    get monthlyProgress() {
        return Math.min((this.monthlyVolume / this.monthlyGoal) * 100, 100);
    }

    get quarterlyProgress() {
        return Math.min((this.quarterlyVolume / this.quarterlyGoal) * 100, 100);
    }

    get annualBarStyle() {
        return `width: ${this.annualProgress}%;`;
    }

    get monthlyChartUrl() {
        return "https://quickchart.io/chart?w=250&h=250&bkg=rgba(255%2C%20255%2C%20255%2C%200)&c=%7B%0A%20%20type%3A%20%27radialGauge%27%2C%0A%20%20data%3A%20%7B%0A%20%20%20%20datasets%3A%20%5B%7B%0A%20%20%20%20%20%20label%3A%20%27$" + this.formatCurrency(this.monthlyVolume) + "%20%2F%20$" + this.formatCurrency(this.monthlyGoal) + "%27%2C%0A%20%20%20%20%20%20data%3A%20%5B" + this.monthlyProgress + "%5D%2C%0A%20%20%20%20%20%20backgroundColor%3A%20getGradientFillHelper(%27horizontal%27%2C%20%5B%27%23778199%27%2C%20%27%231c2642%27%5D)%2C%0A%20%20%20%20%7D%5D%0A%20%20%7D%2C%0A%20%20options%3A%20%7B%0A%20%20%20%20title%3A%20%7B%0A%20%20%20%20%20%20display%3A%20true%2C%0A%20%20%20%20%20%20position%3A%20%27top%27%2C%0A%20%20%20%20%20%20fontSize%3A%20%2714%27%2C%0A%20%20%20%20%20%20text%3A%20%27This%20Month%27%0A%20%20%20%20%7D%2C%0A%20%20%20%20legend%3A%20%7B%0A%20%20%20%20%20%20display%3A%20true%2C%0A%20%20%20%20%20%20position%3A%20%27top%27%2C%0A%20%20%20%20%20%20labels%3A%20%7B%0A%20%20%20%20%20%20%20%20color%3A%20%27black%27%2C%0A%20%20%20%20%20%20%20%20font%3A%20%7B%0A%20%20%20%20%20%20%20%20%20%20size%3A%2012%0A%20%20%20%20%20%20%20%20%7D%0A%20%20%20%20%20%20%7D%0A%20%20%20%20%7D%2C%0A%20%20%20%20domain%3A%20%5B0%2C%20100%5D%2C%0A%20%20%20%20animation%3A%20%7B%0A%20%20%20%20%20%20animateRotate%3A%20true%2C%0A%20%20%20%20%20animateScale%3A%20true%0A%20%20%20%20%7D%2C%0A%20%20%20%20trackColor%3A%20%27%23f0f8ff%27%2C%20%0A%20%20trackColor%3A%20%27rgb(204%2C%20221%2C%20238)%27%2C%0A%20%20roundedCorners%3A%20true%2C%0A%0A%20%20%20%20centerPercentage%3A%2060%2C%0A%20%20%20%20centerArea%3A%20%7B%0A%20%20%20%20%20%20text%3A%20(val)%20%3D%3E%20val%20%2B%20%27%25%27%2C%0A%20%20%20%20%7D%2C%0A%20%20%7D%0A%7D";
    }

    get annualChartUrl() {
        return "https://quickchart.io/chart?w=250&h=250&bkg=rgba(255%2C%20255%2C%20255%2C%200)&c=%7B%0A%20%20type%3A%20%27radialGauge%27%2C%0A%20%20data%3A%20%7B%0A%20%20%20%20datasets%3A%20%5B%7B%0A%20%20%20%20%20%20label%3A%20%27%24" + this.formatCurrency(this.annualVolume) + "%20%2F%20%24" + this.formatCurrency(this.annualGoal) + "%27%2C%0A%20%20%20%20%20%20data%3A%20%5B" + this.annualProgress + "%5D%2C%0A%20%20%20%20%20%20backgroundColor%3A%20getGradientFillHelper(%27horizontal%27%2C%20%5B%27%23778199%27%2C%20%27%231c2642%27%5D)%2C%0A%20%20%20%20%7D%5D%0A%20%20%7D%2C%0A%20%20options%3A%20%7B%0A%20%20%20%20title%3A%20%7B%0A%20%20%20%20%20%20display%3A%20true%2C%0A%20%20%20%20%20%20position%3A%20%27top%27%2C%0A%20%20%20%20%20%20fontSize%3A%20%2714%27%2C%0A%20%20%20%20%20%20text%3A%20%27This%20Year%27%0A%20%20%20%20%7D%2C%0A%20%20%20%20legend%3A%20%7B%0A%20%20%20%20%20%20display%3A%20true%2C%0A%20%20%20%20%20%20position%3A%20%27top%27%2C%0A%20%20%20%20%20%20labels%3A%20%7B%0A%20%20%20%20%20%20%20%20color%3A%20%27black%27%2C%0A%20%20%20%20%20%20%20%20font%3A%20%7B%0A%20%20%20%20%20%20%20%20%20%20size%3A%2012%0A%20%20%20%20%20%20%20%20%7D%0A%20%20%20%20%20%20%7D%0A%20%20%20%20%7D%2C%0A%20%20%20%20domain%3A%20%5B0%2C%20100%5D%2C%0A%20%20%20%20animation%3A%20%7B%0A%20%20%20%20%20%20animateRotate%3A%20true%2C%0A%20%20%20%20%20animateScale%3A%20true%0A%20%20%20%20%7D%2C%0A%20%20%20%20trackColor%3A%20%27%23f0f8ff%27%2C%20%0A%20%20trackColor%3A%20%27rgb(204%2C%20221%2C%20238)%27%2C%0A%20%20roundedCorners%3A%20true%2C%0A%0A%20%20%20%20centerPercentage%3A%2060%2C%0A%20%20%20%20centerArea%3A%20%7B%0A%20%20%20%20%20%20text%3A%20(val)%20%3D%3E%20val%20%2B%20%27%25%27%2C%0A%20%20%20%20%7D%2C%0A%20%20%7D%0A%7D";
    }

    get quarterlyChartUrl() {
        return "https://quickchart.io/chart?w=250&h=250&bkg=rgba(255%2C%20255%2C%20255%2C%200)&c=%7B%0A%20%20type%3A%20%27radialGauge%27%2C%0A%20%20data%3A%20%7B%0A%20%20%20%20datasets%3A%20%5B%7B%0A%20%20%20%20%20%20label%3A%20%27%24" + this.formatCurrency(this.quarterlyVolume) + "%20%2F%20%24" + this.formatCurrency(this.quarterlyGoal) + "%27%2C%0A%20%20%20%20%20%20data%3A%20%5B" + this.quarterlyProgress + "%5D%2C%0A%20%20%20%20%20%20backgroundColor%3A%20getGradientFillHelper(%27horizontal%27%2C%20%5B%27%23778199%27%2C%20%27%231c2642%27%5D)%2C%0A%20%20%20%20%7D%5D%0A%20%20%7D%2C%0A%20%20options%3A%20%7B%0A%20%20%20%20title%3A%20%7B%0A%20%20%20%20%20%20display%3A%20true%2C%0A%20%20%20%20%20%20position%3A%20%27top%27%2C%0A%20%20%20%20%20%20fontSize%3A%20%2714%27%2C%0A%20%20%20%20%20%20text%3A%20%27This%20Quarter%27%0A%20%20%20%20%7D%2C%0A%20%20%20%20legend%3A%20%7B%0A%20%20%20%20%20%20display%3A%20true%2C%0A%20%20%20%20%20%20position%3A%20%27top%27%2C%0A%20%20%20%20%20%20labels%3A%20%7B%0A%20%20%20%20%20%20%20%20color%3A%20%27black%27%2C%0A%20%20%20%20%20%20%20%20font%3A%20%7B%0A%20%20%20%20%20%20%20%20%20%20size%3A%2012%0A%20%20%20%20%20%20%20%20%7D%0A%20%20%20%20%20%20%7D%0A%20%20%20%20%7D%2C%0A%20%20%20%20domain%3A%20%5B0%2C%20100%5D%2C%0A%20%20%20%20animation%3A%20%7B%0A%20%20%20%20%20%20animateRotate%3A%20true%2C%0A%20%20%20%20%20animateScale%3A%20true%0A%20%20%20%20%7D%2C%0A%20%20%20%20trackColor%3A%20%27%23f0f8ff%27%2C%20%0A%20%20trackColor%3A%20%27rgb(204%2C%20221%2C%20238)%27%2C%0A%20%20roundedCorners%3A%20true%2C%0A%0A%20%20%20%20centerPercentage%3A%2060%2C%0A%20%20%20%20centerArea%3A%20%7B%0A%20%20%20%20%20%20text%3A%20(val)%20%3D%3E%20val%20%2B%20%27%25%27%2C%0A%20%20%20%20%7D%2C%0A%20%20%7D%0A%7D";
    }

    formatCurrency(value) {
        return value.toString().replace(/\B(?<!\.\d*)(?=(\d{3})+(?!\d))/g, ",");
    }

    get monthlyBarStyle() {
        return `width: ${this.monthlyProgress}%;`;
    }

    get quarterlyBarStyle() {
        return `width: ${this.quarterlyProgress}%;`;
    }

    @wire(getVolumeProgress)
    wiredProgress({ error, data }) {
        if (data) {
            this.annualVolume = data.annualVolume;
            this.monthlyVolume = data.monthlyVolume;
            this.quarterlyVolume = data.quarterlyVolume;
            this.annualGoal = data.annualGoal;
            this.monthlyGoal = data.monthlyGoal;
            this.quarterlyGoal = data.quarterlyGoal;
        } else if (error) {
            console.error('Error fetching progress:', error);
        }
    }
}