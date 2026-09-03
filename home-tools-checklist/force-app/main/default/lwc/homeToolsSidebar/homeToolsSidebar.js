import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getHomeToolsData from '@salesforce/apex/HomeToolsController.getHomeToolsData';
import addDailyChecklistItem from '@salesforce/apex/HomeToolsController.addDailyChecklistItem';
import completeDailyChecklistItem from '@salesforce/apex/HomeToolsController.completeDailyChecklistItem';
import getClearedDailyChecklistItems from '@salesforce/apex/HomeToolsController.getClearedDailyChecklistItems';
import addRunningTodoItem from '@salesforce/apex/HomeToolsController.addRunningTodoItem';
import completeRunningTodoItem from '@salesforce/apex/HomeToolsController.completeRunningTodoItem';
import updateRunningTodoItem from '@salesforce/apex/HomeToolsController.updateRunningTodoItem';
import updateDailyChecklistItem from '@salesforce/apex/HomeToolsController.updateDailyChecklistItem';
import reopenRunningTodoItem from '@salesforce/apex/HomeToolsController.reopenRunningTodoItem';
import getCompletedRunningTodoItems from '@salesforce/apex/HomeToolsController.getCompletedRunningTodoItems';
import reorderChecklistItems from '@salesforce/apex/HomeToolsController.reorderChecklistItems';

const CHECKLIST_LIST = 'checklist';

export default class HomeToolsSidebar extends NavigationMixin(LightningElement) {
    events = [];
    recentRecords = [];
    trackers = [];
    weeklyLeadTracker;
    isLoanPartnerChecklistUser = false;
    dailyChecklistItems = [];
    clearedChecklistItems = [];
    checklistLeadName = '';
    checklistDescription = '';
    checklistPriority = 'Medium';
    isSavingChecklistItem = false;
    isChecklistAddFormOpen = false;
    completingChecklistItemId;
    isClearedChecklistOpen = false;
    isLoadingClearedChecklistItems = false;
    homeToolsWireResult;
    isRunningTodoUser = false;
    runningTodoItems = [];
    completedTodoItems = [];
    todoDescription = '';
    todoPriority = 'Medium';
    isSavingTodoItem = false;
    isTodoAddFormOpen = false;
    completingTodoItemId;
    isCompletedTodoOpen = false;
    isLoadingCompletedTodoItems = false;
    editingItemId;
    editLeadName = '';
    editDescription = '';
    editPriority = 'Medium';
    isSavingEdit = false;
    draggingItemId;
    draggingList;
    draggingRow;
    dropTargetRow;

    get hasTrackers() {
        return this.trackers.length > 0;
    }

    get hasEvents() {
        return this.events.length > 0;
    }

    get hasRecentRecords() {
        return this.recentRecords.length > 0;
    }

    get eventsCardClass() {
        return this.hasTrackers ? 'tools-card tools-card-hidden' : 'tools-card';
    }

    // To-do users get a drawer dedicated to their list, without the events and recent records cards.
    get showEventsAndRecentRecords() {
        return !this.isRunningTodoUser;
    }

    get hasWeeklyLeadTracker() {
        return !!this.weeklyLeadTracker;
    }

    get hasDailyChecklistItems() {
        return this.dailyChecklistItems.length > 0;
    }

    get hasClearedChecklistItems() {
        return this.clearedChecklistItems.length > 0;
    }

    get openTaskCount() {
        return this.dailyChecklistItems.length;
    }

    get pastDueTaskCount() {
        return this.dailyChecklistItems.filter((item) => item.isPastDue).length;
    }

    get dueTodayTaskCount() {
        return this.openTaskCount - this.pastDueTaskCount;
    }

    get hasPastDueTasks() {
        return this.pastDueTaskCount > 0;
    }

    get hasDueTodayTasks() {
        return this.dueTodayTaskCount > 0;
    }

    get openTaskCountLabel() {
        return this.openTaskCount === 1 ? 'open task' : 'open tasks';
    }

    get pastDueBadgeText() {
        return `${this.pastDueTaskCount} past due`;
    }

    get dueTodayBadgeText() {
        return `${this.dueTodayTaskCount} due today`;
    }

    get taskCounterClass() {
        const classes = ['checklist-counter'];
        if (!this.hasDailyChecklistItems) {
            classes.push('checklist-counter-clear-state');
        } else if (this.hasPastDueTasks) {
            classes.push('checklist-counter-alert');
        }
        return classes.join(' ');
    }

    get clearedChecklistToggleLabel() {
        return this.isClearedChecklistOpen ? 'Hide cleared items' : 'View cleared items (today & yesterday)';
    }

    get hasRunningTodoItems() {
        return this.runningTodoItems.length > 0;
    }

    get hasCompletedTodoItems() {
        return this.completedTodoItems.length > 0;
    }

    get openTodoCount() {
        return this.runningTodoItems.length;
    }

    get openTodoCountLabel() {
        return this.openTodoCount === 1 ? 'open item' : 'open items';
    }

    get highPriorityTodoCount() {
        return this.runningTodoItems.filter((item) => item.priority === 'High').length;
    }

    get hasHighPriorityTodos() {
        return this.highPriorityTodoCount > 0;
    }

    get highPriorityTodoBadgeText() {
        return `${this.highPriorityTodoCount} high priority`;
    }

    get todoCounterClass() {
        const classes = ['checklist-counter'];
        if (!this.hasRunningTodoItems) {
            classes.push('checklist-counter-clear-state');
        } else if (this.hasHighPriorityTodos) {
            classes.push('checklist-counter-alert');
        }
        return classes.join(' ');
    }

    get completedTodoToggleLabel() {
        return this.isCompletedTodoOpen ? 'Hide completed items' : 'View recently completed';
    }

    get checklistPriorityOptions() {
        return [
            { label: 'High', value: 'High' },
            { label: 'Medium', value: 'Medium' },
            { label: 'Low', value: 'Low' }
        ];
    }

    get formattedRollingTwelveMonthWeeklyAverage() {
        const average = this.weeklyLeadTracker ? this.weeklyLeadTracker.rollingTwelveMonthWeeklyAverage : 0;
        return new Intl.NumberFormat('en-US', {
            minimumFractionDigits: 1,
            maximumFractionDigits: 1
        }).format(average || 0);
    }

    @wire(getHomeToolsData)
    wiredHomeTools(result) {
        this.homeToolsWireResult = result;
        const { data } = result;
        if (data) {
            this.events = data.events || [];
            this.recentRecords = data.recentRecords || [];
            this.trackers = this.decorateTrackers(data.trackers || []);
            this.weeklyLeadTracker = data.weeklyLeadTracker;
            this.isLoanPartnerChecklistUser = data.isLoanPartnerChecklistUser || false;
            this.dailyChecklistItems = this.decorateDailyChecklistItems(data.dailyChecklistItems || []);
            this.isRunningTodoUser = data.isRunningTodoUser || false;
            this.runningTodoItems = this.decorateRunningTodoItems(data.runningTodoItems || []);
        }
    }

    decorateRunningTodoItems(items) {
        return items.map((item) => {
            const isEditing = item.id === this.editingItemId;
            return {
                ...item,
                priorityClass: `checklist-priority checklist-priority-${(item.priority || 'Medium').toLowerCase()}`,
                addedLabel: item.addedText ? `Added ${item.addedText}` : '',
                isCompleting: item.id === this.completingTodoItemId,
                isEditing,
                // A row being edited stops being draggable so the textarea stays selectable.
                draggable: isEditing ? 'false' : 'true'
            };
        });
    }

    decorateDailyChecklistItems(items) {
        return items.map((item) => {
            const isEditing = item.id === this.editingItemId;
            return {
                ...item,
                priorityClass: `checklist-priority checklist-priority-${(item.priority || 'Medium').toLowerCase()}`,
                dueText: item.isPastDue
                    ? `Past due: ${item.dueDate}`
                    : (item.dueDate ? `Due today: ${item.dueDate}` : 'Due today'),
                isCompleting: item.id === this.completingChecklistItemId,
                isEditing,
                // A row being edited stops being draggable so the textarea stays selectable.
                draggable: isEditing ? 'false' : 'true'
            };
        });
    }



    decorateTrackers(trackers) {
        return trackers.map((tracker, index) => ({
            ...tracker,
            key: `${tracker.label}-${index}`,
            className: ['tracker-card', tracker.variant ? `tracker-card-${tracker.variant}` : ''].filter(Boolean).join(' '),
            formattedVolume: this.formatCurrency(tracker.volume),
            unitsText: `${tracker.units || 0} ${(tracker.units || 0) === 1 ? 'unit' : 'units'}`
        }));
    }

    formatCurrency(value) {
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD',
            maximumFractionDigits: 0
        }).format(value || 0);
    }

    openRecord(event) {
        const recordId = event.currentTarget.dataset.id;
        const objectApiName = event.currentTarget.dataset.object;
        if (!recordId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName,
                actionName: 'view'
            }
        });
    }

    openReport(event) {
        const reportUrl = event.currentTarget.dataset.reportUrl;
        if (!reportUrl) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: reportUrl
            }
        });
    }

    openCalendar() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Event',
                actionName: 'home'
            }
        });
    }

    handleChecklistLeadNameChange(event) {
        this.checklistLeadName = event.target.value;
    }

    handleChecklistDescriptionChange(event) {
        this.checklistDescription = event.target.value;
    }

    handleChecklistPriorityChange(event) {
        this.checklistPriority = event.detail.value;
    }

    toggleChecklistAddForm() {
        this.isChecklistAddFormOpen = !this.isChecklistAddFormOpen;
    }

    closeChecklistAddForm() {
        this.isChecklistAddFormOpen = false;
        this.checklistLeadName = '';
        this.checklistDescription = '';
        this.checklistPriority = 'Medium';
    }

    async addChecklistItem() {
        if (!this.checklistLeadName || !this.checklistLeadName.trim()) {
            this.showToast('Add a Lead name', 'Type the name this checklist item belongs to.', 'error');
            return;
        }
        if (!this.checklistDescription || !this.checklistDescription.trim()) {
            this.showToast('Add a description', 'Enter a brief description of what needs to be done.', 'error');
            return;
        }
        this.isSavingChecklistItem = true;
        try {
            await addDailyChecklistItem({
                leadName: this.checklistLeadName,
                description: this.checklistDescription,
                priority: this.checklistPriority
            });
            await refreshApex(this.homeToolsWireResult);
            this.closeChecklistAddForm();
            this.showToast('Checklist item added', 'It was added to your Daily Checklist.', 'success');
        } catch (error) {
            this.showToast('Unable to add checklist item', this.errorMessage(error), 'error');
        } finally {
            this.isSavingChecklistItem = false;
        }
    }

    async completeChecklistItem(event) {
        const taskId = event.currentTarget.dataset.id;
        this.completingChecklistItemId = taskId;
        try {
            await completeDailyChecklistItem({ taskId });
            await refreshApex(this.homeToolsWireResult);
            if (this.isClearedChecklistOpen) {
                await this.loadClearedChecklistItems();
            }
        } catch (error) {
            this.showToast('Unable to complete checklist item', this.errorMessage(error), 'error');
        } finally {
            this.completingChecklistItemId = undefined;
        }
    }

    async toggleClearedChecklistItems() {
        this.isClearedChecklistOpen = !this.isClearedChecklistOpen;
        if (this.isClearedChecklistOpen) {
            await this.loadClearedChecklistItems();
        }
    }

    async loadClearedChecklistItems() {
        this.isLoadingClearedChecklistItems = true;
        try {
            this.clearedChecklistItems = await getClearedDailyChecklistItems();
        } catch (error) {
            this.showToast('Unable to load cleared items', this.errorMessage(error), 'error');
        } finally {
            this.isLoadingClearedChecklistItems = false;
        }
    }

    handleTodoDescriptionChange(event) {
        this.todoDescription = event.target.value;
    }

    handleTodoPriorityChange(event) {
        this.todoPriority = event.detail.value;
    }

    toggleTodoAddForm() {
        this.isTodoAddFormOpen = !this.isTodoAddFormOpen;
    }

    closeTodoAddForm() {
        this.isTodoAddFormOpen = false;
        this.todoDescription = '';
        this.todoPriority = 'Medium';
    }

    async addTodoItem() {
        if (!this.todoDescription || !this.todoDescription.trim()) {
            this.showToast('Add a description', 'Enter a brief description of what needs to be done.', 'error');
            return;
        }
        this.isSavingTodoItem = true;
        try {
            await addRunningTodoItem({ description: this.todoDescription, priority: this.todoPriority });
            await refreshApex(this.homeToolsWireResult);
            this.closeTodoAddForm();
        } catch (error) {
            this.showToast('Unable to add item', this.errorMessage(error), 'error');
        } finally {
            this.isSavingTodoItem = false;
        }
    }

    async completeTodoItem(event) {
        const taskId = event.currentTarget.dataset.id;
        this.completingTodoItemId = taskId;
        try {
            await completeRunningTodoItem({ taskId });
            await refreshApex(this.homeToolsWireResult);
            if (this.isCompletedTodoOpen) {
                await this.loadCompletedTodoItems();
            }
        } catch (error) {
            this.showToast('Unable to complete item', this.errorMessage(error), 'error');
        } finally {
            this.completingTodoItemId = undefined;
        }
    }

    // A running list is worth an undo: checking something off by mistake would otherwise
    // mean retyping it, since completed items cannot be edited back into the open list.
    async reopenTodoItem(event) {
        const taskId = event.currentTarget.dataset.id;
        try {
            await reopenRunningTodoItem({ taskId });
            await refreshApex(this.homeToolsWireResult);
            await this.loadCompletedTodoItems();
            this.showToast('Item reopened', 'It is back on your open list.', 'success');
        } catch (error) {
            this.showToast('Unable to reopen item', this.errorMessage(error), 'error');
        }
    }

    async toggleCompletedTodoItems() {
        this.isCompletedTodoOpen = !this.isCompletedTodoOpen;
        if (this.isCompletedTodoOpen) {
            await this.loadCompletedTodoItems();
        }
    }

    async loadCompletedTodoItems() {
        this.isLoadingCompletedTodoItems = true;
        try {
            this.completedTodoItems = await getCompletedRunningTodoItems();
        } catch (error) {
            this.showToast('Unable to load completed items', this.errorMessage(error), 'error');
        } finally {
            this.isLoadingCompletedTodoItems = false;
        }
    }

    // One editor at a time, shared by both lists: the row swaps to a form in place and the
    // description/priority are written back through the matching Apex update.
    startEditItem(event) {
        const id = event.currentTarget.dataset.id;
        const source = [...this.runningTodoItems, ...this.dailyChecklistItems];
        const item = source.find((candidate) => candidate.id === id);
        if (!item) {
            return;
        }
        this.editingItemId = id;
        this.editLeadName = item.leadName || '';
        this.editDescription = item.description || '';
        this.editPriority = item.priority || 'Medium';
        this.refreshDecoratedLists();
    }

    cancelEditItem() {
        this.editingItemId = undefined;
        this.editLeadName = '';
        this.editDescription = '';
        this.editPriority = 'Medium';
        this.refreshDecoratedLists();
    }

    handleEditLeadNameChange(event) {
        this.editLeadName = event.target.value;
    }

    handleEditDescriptionChange(event) {
        this.editDescription = event.target.value;
    }

    handleEditPriorityChange(event) {
        this.editPriority = event.detail.value;
    }

    async saveEditItem(event) {
        const id = event.currentTarget.dataset.id;
        const isTodo = this.runningTodoItems.some((item) => item.id === id);
        if (!this.editDescription || !this.editDescription.trim()) {
            this.showToast('Add a description', 'Enter a brief description of what needs to be done.', 'error');
            return;
        }
        if (!isTodo && (!this.editLeadName || !this.editLeadName.trim())) {
            this.showToast('Add a Lead name', 'Type the name this checklist item belongs to.', 'error');
            return;
        }
        this.isSavingEdit = true;
        try {
            const payload = { taskId: id, description: this.editDescription, priority: this.editPriority };
            if (isTodo) {
                await updateRunningTodoItem(payload);
            } else {
                await updateDailyChecklistItem({ ...payload, leadName: this.editLeadName });
            }
            this.editingItemId = undefined;
            await refreshApex(this.homeToolsWireResult);
        } catch (error) {
            this.showToast('Unable to save changes', this.errorMessage(error), 'error');
        } finally {
            this.isSavingEdit = false;
        }
    }

    /**
     * Drag and drop reorders the list, and the drop position sets the item's priority: it adopts
     * the priority of the row it lands under. A list that is all one priority therefore just
     * rearranges, while dropping into a group of another priority moves the item into it.
     */
    handleDragStart(event) {
        this.draggingItemId = event.currentTarget.dataset.id;
        this.draggingList = event.currentTarget.dataset.list;
        this.draggingRow = event.currentTarget;
        this.draggingRow.classList.add('daily-checklist-item-dragging');
        if (event.dataTransfer) {
            event.dataTransfer.effectAllowed = 'move';
            // Firefox will not start a drag unless something is written to the transfer.
            event.dataTransfer.setData('text/plain', this.draggingItemId);
        }
    }

    handleDragOver(event) {
        if (!this.draggingItemId || event.currentTarget.dataset.list !== this.draggingList) {
            return;
        }
        event.preventDefault();
        if (event.dataTransfer) {
            event.dataTransfer.dropEffect = 'move';
        }
        this.markDropTarget(event.currentTarget);
    }

    handleDragEnd() {
        if (this.draggingRow) {
            this.draggingRow.classList.remove('daily-checklist-item-dragging');
        }
        this.markDropTarget(undefined);
        this.draggingItemId = undefined;
        this.draggingList = undefined;
        this.draggingRow = undefined;
    }

    // Drag feedback is written straight to the DOM. Re-rendering the rows mid-drag replaces the
    // element the browser is dragging, which silently cancels the drag.
    markDropTarget(row) {
        if (this.dropTargetRow === row) {
            return;
        }
        if (this.dropTargetRow) {
            this.dropTargetRow.classList.remove('daily-checklist-item-drag-over');
        }
        this.dropTargetRow = row;
        if (row) {
            row.classList.add('daily-checklist-item-drag-over');
        }
    }

    async handleDrop(event) {
        event.preventDefault();
        const targetId = event.currentTarget.dataset.id;
        const list = event.currentTarget.dataset.list;
        const draggedId = this.draggingItemId;
        const draggedList = this.draggingList;
        this.handleDragEnd();
        if (!draggedId || list !== draggedList || draggedId === targetId) {
            return;
        }

        const isChecklist = list === CHECKLIST_LIST;
        const source = isChecklist ? this.dailyChecklistItems : this.runningTodoItems;
        const fromIndex = source.findIndex((item) => item.id === draggedId);
        const toIndex = source.findIndex((item) => item.id === targetId);
        if (fromIndex < 0 || toIndex < 0) {
            return;
        }

        const reordered = [...source];
        const [moved] = reordered.splice(fromIndex, 1);
        reordered.splice(toIndex, 0, moved);
        reordered[toIndex] = { ...moved, priority: this.priorityForPosition(reordered, toIndex) };

        // Show the new arrangement straight away; the server call re-sorts it the same way.
        if (isChecklist) {
            this.dailyChecklistItems = this.decorateDailyChecklistItems(reordered);
        } else {
            this.runningTodoItems = this.decorateRunningTodoItems(reordered);
        }

        try {
            await reorderChecklistItems({
                orderedItems: reordered.map((item) => ({ id: item.id, priority: item.priority }))
            });
            await refreshApex(this.homeToolsWireResult);
        } catch (error) {
            await refreshApex(this.homeToolsWireResult);
            this.showToast('Unable to reorder', this.errorMessage(error), 'error');
        }
    }

    // An item takes the priority of the row above it, so dropping it inside a group joins that
    // group. Dropped at the very top there is no row above, so the row below decides.
    priorityForPosition(items, index) {
        const neighbour = index > 0 ? items[index - 1] : items[index + 1];
        return neighbour ? neighbour.priority : items[index].priority;
    }

    refreshDecoratedLists() {
        this.runningTodoItems = this.decorateRunningTodoItems(this.runningTodoItems);
        this.dailyChecklistItems = this.decorateDailyChecklistItems(this.dailyChecklistItems);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    errorMessage(error) {
        return error && error.body && error.body.message ? error.body.message : 'Please try again.';
    }
}