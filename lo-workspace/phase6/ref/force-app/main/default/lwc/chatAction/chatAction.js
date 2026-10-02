/**
 *********************************************************
 * @name             : chatAction
 * @date             : 19.03.2025
 * @description      : -
 * @author           : Taras Babyn
 * @change log       : Mar 19, 2025 Taras Babyn - Initial Version
 *********************************************************
 */
import {LightningElement, api} from 'lwc';

export default class ChatAction extends LightningElement {
    /** @type {ChatActionTypeDef} */
    @api action;

    /** @type {import('c/chat').ChatMessageDef} */
    @api message;

    /**
     * @param {CustomEvent} event
     * @fires Chat#CustomEvent:chataction
     */
    toggleChangeHandler(event) {
        event.preventDefault();

        this.dispatchEvent(
            new CustomEvent('chataction', {
                detail: event.detail,
                bubbles: true,
                composed: true
            })
        );

    }

    get actionTypeIsToggle() {
        return this.action?.type === 'TOGGLE';
    }

}

/**
 * @typedef {Object} ChatActionTypeDef
 * @property {string} type - The type of the action (e.g., 'TOGGLE').
 * @property {Object | ToggleConfig } config - The configuration object for the action.
 */