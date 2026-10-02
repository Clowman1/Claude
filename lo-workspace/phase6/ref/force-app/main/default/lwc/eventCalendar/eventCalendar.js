import { LightningElement, api } from 'lwc';
import { loadScript, loadStyle } from 'lightning/platformResourceLoader';
import FULL_CALENDAR from '@salesforce/resourceUrl/FullCalendar';

import getTransactions from '@salesforce/apex/OutsideLOActivityPageController.getTransactions';
import getTasks from '@salesforce/apex/OutsideLOActivityPageController.getTasks';

import CreateEventModal from 'c/createEventModal';

export default class EventCalendar extends LightningElement {
    static renderMode = 'light';
    fullCalendarJs;
    events = [];
    calendar;

    transactions;
    isLoading = true;

    connectedCallback() {
        this.fetchData();
    }

    @api refresh() {
        this.fetchData();
    }

    async fetchData() {
        try {
            this.isLoading = true;
            let transactions = await getTransactions();
            for (const transaction of transactions) {
                console.log(transaction.Id);
                console.log(transaction.Name);
            }
            this.transactions = transactions;
            let tasks = await getTasks();
            let events = [];
            for (const task of tasks) {
                console.log(task.Status);
                events.push( { // this object will be "parsed" into an Event Object
                    title: task.Activity_Title__c ? task.Activity_Title__c : task.Subject, // a property!
                    start: task.Activity_Start_DateTime__c, // a property!
                    end: task.Activity_End_DateTime__c, // a property! ** see important note below about 'end' **
                    color: task.Status === 'Completed' ? 'green' : '#484f6c'
                })
            }
            if (this.calendar) {
                this.calendar.removeAllEvents();
                this.events = events;
                this.calendar.refetchEvents();
            }

            this.isLoading = false;
        } catch (e) {
            console.log(e.message);
        }
    }

    renderedCallback() {
        if (this.fullCalendarJs) {
            return;
        }
        this.fullCalendarJs = true;

        Promise.all([
            loadScript(this, FULL_CALENDAR + '/FullCalendar/lib/main.js'),
            loadStyle(this, FULL_CALENDAR + '/FullCalendar/lib/main.css') //specified filename
        ])
        .then(() => {
            this.initializeCalendar();
        })
        .catch(e => {
            alert('Error loading FullCalendar', e);
        });
    }


    initializeCalendar() {
        const calendarEl = this.querySelector(".calendar");
        

        if (!calendarEl) {
            alert('Calendar element not found');
            return;
        }

        try {
            const containerEl = this.querySelector(".container");

            // new window.FullCalendar.Draggable(containerEl, {
            //     itemSelector: '.transaction-item',
            //     eventData: function(eventEl) {
            //         return {
            //           title: eventEl.innerText
            //         };
            //       }
            // });

            console.log(window.FullCalendar);
            console.log(window.FullCalendar.timeGridPlugin);

            const calendar = new window.FullCalendar.Calendar(calendarEl, {
                initialView: 'timeGridWeek',


                // plugins: [ window.FullCalendar.timeGridPlugin ],

                // headerToolbar: {
                //     right: 'prev,next' // user can switch between the two
                // },

                slotMinTime: "07:00:00", slotMaxTime: "21:00:00",
                height: 700,
                eventColor: '#484f6c',
                //droppable: true,
                selectable: true,
                allDaySlot: false,
  
                eventSources: [
                    (fetchInfo, successCallback, failureCallback) => {
                        successCallback(this.events);  // Pass updated events
                    }
                ],
                // eventClick: function(info) {
                //     console.log("CLICKED")
                //     //info.jsEvent.preventDefault(); 
                //     console.log(info);
                // },
                // dateClick: async function(info) {
                //     // console.log('Clicked on: ', info.date);
                //     // const result = await CreateEventModal.open({
                //     //     size: 'large',
                //     //     description: 'Accessible description of modal\'s purpose',
                //     //     start: info.date,
                //     //     end: info.date
                //     // });

                //     // console.log(result);
                // },
                // drop: async (info) => {
                //     console.log(info.date);
                //     let transactionId = info.draggedEl.getAttribute('data-transaction-id');
                //     const result = await CreateEventModal.open({
                //         size: 'large',
                //         description: 'Accessible description of modal\'s purpose',
                //         start: info.date,
                //         end: info.date,
                //         transactionId: transactionId
                //     });

                //     console.log(result);
                //     if (!result) {
                //         info.revert();
                //     }

                //     this.fetchData();

                    
                // }
            });
            calendar.render();
            console.log("RENDERED!");
            this.calendar = calendar;
        } catch (e) {
            alert(e.message);
        }

    }
}