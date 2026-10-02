/**
 *********************************************************
 * @name              : chat
 * @date              : 06.03.2025
 * @description       : Chat
 * @author            : Taras Babyn
 * @change log        : Mar 06, 2025 Taras Babyn - Initial Version
 *********************************************************
 */
import {api, LightningElement, track} from 'lwc';
import {formatDatetime} from './utils';

/**
 * @fires Chat#CustomEvent:chataction
 */
export default class Chat extends LightningElement {

    /** @type {boolean} */
    isLoading;
    /** @type {boolean} */
    isSending;

    /**
     * @type {groupedMessages[] | []} groupedMessages
     */
    @track groupedMessages = [];

    /** @type {string}  */
    newMessage;

    /** @type {boolean} */
    @api isExpanded;

    /** @type {Configuration} */
    configuration;

    /**
     * Getter to convert boolean to string for aria-expanded attribute
     * @returns {string} "true" or "false"
     */
    get isExpandedString() {
        return this.isExpanded === true ? 'true' : 'false';
    }

    /**
     *
     * @param {Configuration} configuration
     * @returns {void}
     */
    @api async setupChat(configuration) {
        this.configuration = configuration;

        this.groupedMessages = this.groupCommentsByDate(this.configuration?.messages);

    }

    /**
     * @param {Event} event
     */
    newMessageHandler(event) {
        this.newMessage = event.target.value;
    }

    /**
     * @param {Event} event
     * @fires Chat#CustomEvent:sendmessage - Event triggered when the selected option changes
     * */
    async sendMessageHandler(event) {
        event.preventDefault();

        const id = crypto.randomUUID();

        const newMessage = {
            createdBy: 'Me',
            isOutbound: true,
            status: 'sending',
            createdOn: new Date(Date.now()).toISOString(),
            id: id,
            message: this.newMessage,
            userTypeName: 'User',
            badge: this.getUserTypeBadgeClass('User'),
            createdOnFormatted: formatDatetime(new Date(Date.now())),
            actions: []
        };

        if (this.groupedMessages?.at(0)?.date === 'Today') {
            this.groupedMessages.at(0).messages.unshift(newMessage);
        } else {
            this.groupedMessages.unshift({
                key: `${this.groupedMessages.length}:Today`, date: 'Today', messages: [newMessage]
            });
        }
        this.scrollToTop();

        const message = this.newMessage;
        this.newMessage = '';
        this.isSending = true;

        try {
            this.dispatchEvent(
                new CustomEvent('sendmessage', {
                    detail: {
                        message: message
                    }
                })
            );
        } catch (e) {
            console.error('sendMessageHandler =>', e);
            const failedMessage = this.groupedMessages[0].messages.find(message => message.id === id);
            failedMessage.status = 'failed';
            failedMessage.createdOnFormatted = 'not sent';
        }
        this.isSending = false;

    }

    /**
     * @param {CustomEvent} event
     * @fires Chat#CustomEvent:change
     * */
    async handleCollapsibleClick(event) {
        const collapsible = event.target.closest('.collapsible');
        const content = collapsible.querySelector('.collapsible-content');
        this.isExpanded = !this.isExpanded;
        content.hidden = !content.hidden;

        /**
         * @type {CustomEvent}
         * @property {ToggleChangeEventDetail} detail - Event details
         */
        this.dispatchEvent(new CustomEvent('expanded', {
            detail: {
                isExpanded: this.isExpanded
            }
        }));
    }

    /**
     * @param {Event} event
     * @fires Chat#CustomEvent:doubleclick - Event triggered when the selected option changes
     *  */
    doubleClickHandler(event) {
        const target = event.currentTarget;
        const message = this.configuration?.messages.find(message => message.id === target.dataset.id);
        this.dispatchEvent(new CustomEvent('doubleclick', {
            detail: {
                message
            }
        }));

    }




    /**
     *
     * @param { ChatMessageDef[]} messages
     * @returns {GroupedMessages[]}
     */
    groupCommentsByDate(messages) {
        if (!messages?.length) {
            return [];
        }
        const groups = {};
        const today = new Date().toDateString();

        messages.sort((a, b) => new Date(a.createdOn) - new Date(b.createdOn)).forEach(message => {
            if (!message.id && message.Id) {
                message.id = message.Id;
            }
            !!message.userTypeName ? message.badge = this.getUserTypeBadgeClass(message.userTypeName) : void 0;

            const commentDate = new Date(message.createdOn).toDateString();
            const key = commentDate === today ? 'Today' : commentDate;
            if (!groups[key]) {
                groups[key] = [];
            }

            message.createdOnFormatted = formatDatetime(message.createdOn);
            groups[key].push(message);
        });

        return Object.entries(groups).map(([dateStr, messagesForDate], index) => {
            return {
                key: `${index}:${dateStr}`,
                date: dateStr,
                messages: messagesForDate
            };

        });
    }

    scrollToTop() {
        this.refs.list?.firstElementChild?.scrollIntoView({
            block: 'nearest',
            behavior: 'smooth'
        });
    }

    // The same string will always return the same class because the hash calculation is deterministic
    getUserTypeBadgeClass(str) {
        const colors = ['badge-red', 'badge-yellow', 'badge-green', 'badge-blue', 'badge-indigo', 'badge-purple', 'badge-pink'];
        const hash = str.split('').reduce((acc, char) => acc + char.charCodeAt(0), 0);
        return ' badge ' + colors[hash % colors.length];
    }

    get title() {
        return this.configuration?.title ?? 'Messages';
    }

    get sendDisabled() {
        return !(this.newMessage?.length > 0);
    }

}

/**
 * @typedef {Object} GroupedMessages
 * @property {string} date - The date of the comments.
 * @property {ChatMessageDef[]} messages - The list of comments for the date.
 */

/**
 * @typedef {Object} ChatMessageDef
 * @property {string} id - id
 * @property {string} message - message text
 * @property {string} createdBy
 * @property {string} createdOn
 * @property {boolean} unRead
 * @property {string} userTypeName // Appraiser, Staff ...
 * @property {string} isOutbound  // inbound, outbound
 * @property {string} badge - Css class depending on the user type.
 * @property {string} status - Status of the message.
 * @property {string} createdOnFormatted - Formatted date of the message.
 *
 */

/**
 * @typedef {Object} Configuration - Configuration object for initializing the chat
 * @property {ChatMessageDef[]} messages - Array of messages to display in the chat
 * @property {string} [title] - Chat title
 * @property {boolean} [allowAttachments] - Whether file attachments are allowed
 * @property {number} [maxMessageLength] - Maximum allowed message length
 */