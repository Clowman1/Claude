import { LightningElement } from 'lwc';

import CreateEventModal from 'c/createEventModal';

export default class ActivityLogButtons extends LightningElement {
    handleAddCall() {
        this.openModal('Call - Prospecting')
    }

    handleAddText() {
        this.openModal('Text')
    }

    handleAddEmail() {
        this.openModal('Email')
    }

    handleAddMeeting() {
        this.openModal('Meeting (New Agent)')
    }

    handleAddOpenHouse() {
        this.openModal('Open House')
    }

    async openModal(type) {
        const result = await CreateEventModal.open({
            size: 'small',
            description: 'Accessible description of modal\'s purpose',
            activityType: type
        });
        console.log(result);

        this.dispatchEvent(new CustomEvent("finished"));
    }
}