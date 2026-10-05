/**
 *********************************************************
 * @name                 : enhancedSwitcher
 * @date                   : 06.03.2025
 * @description       : -
 * @author               : Taras Babyn
 * @change log        : Mar 06, 2025 Taras Babyn - Initial Version
 *********************************************************
 */
import { api, LightningElement, track } from 'lwc';


const DEFAULT_ICON_SIZE ='xx-small';

/**
 * Dynamic toggle component that can be configured for different use cases.
 * @fires CustomEvent#change - Event triggered when the selected option changes
 */
export default class EnhancedSwitcher extends LightningElement {
    /**
     * Component configuration
     * @type {ToggleConfig}
     */
    @api
    get config() {
        return this._config;
    }
    set config(value) {
        this._config = value;
        this.processConfig();
    }

    /** @type {ToggleConfig} */
    @track _config;

    /** @type {Array<ToggleOption & {computedClass: string}>} */
    @track options = [];

    /** @type {string|null} */
    @track selectedValue = null;

    /** @type {string|null} */
    @track previousValue = null;

    /** @type {string} */
    containerStyle = '';

    /** @type {boolean} */
    allowDeselect = false;

    /** @type {string} */
    iconSize;

    /**
     * Called when the component is created
     */
    connectedCallback() {
        if (this._config) {
            this.processConfig();
        }
    }

    /**
     * Processes the configuration and sets up the component
     * @private
     */
    processConfig() {
        if (!this._config) return;

        this.containerStyle = this._config.containerStyle || '';

        this.allowDeselect = !!this._config.allowDeselect;
        this.iconSize = this._config.iconSize || DEFAULT_ICON_SIZE;
        this.id = this._config.id;

        if (this._config.options && Array.isArray(this._config.options)) {
            this.options = JSON.parse(JSON.stringify(this._config.options));

            if (this._config.defaultValue) {
                this.selectedValue = this._config.defaultValue;
            } else if (this.options.length > 0) {
                this.selectedValue = this.options[0].value;
            }

            this.updateComputedClasses();
        }
    }

    /**
     * Updates computed CSS classes for each option
     * @private
     */
    updateComputedClasses() {
        this.options = this.options.map(option => {
            return {
                ...option,
                computedClass: `toggle-item ${option.value === this.selectedValue ? 'selected' : ''} ${option.customClass || ''}`
            };
        });
    }

    /**
     * Handles click on an option
     * @param {CustomEvent} event - Click event
     * @private
     */
    handleToggle(event) {
        const value = event.currentTarget.dataset.value;

        if (this.allowDeselect && value === this.selectedValue) {
            this.previousValue = this.selectedValue;
            this.selectedValue = null;
            this.updateComputedClasses();

            this.dispatchEvent(new CustomEvent('change', {
                detail: {
                    id: this.id,
                    type:'TOGGLE',
                    value: null,
                    option: null,
                    previousValue: this.previousValue
                }
            }));
            return;
        }

        if (value !== this.selectedValue) {
            this.previousValue = this.selectedValue;
            this.selectedValue = value;
            this.updateComputedClasses();

            const selectedOption = this.options.find(opt => opt.value === value);

            /**
             * Selected option change event
             * @event EnhancedSwitcher#change
             * @type {CustomEvent}
             * @property {ToggleChangeEventDetail} detail - Event details
             */
            this.dispatchEvent(new CustomEvent('change', {
                detail: {
                    id: this.id,
                    type:'TOGGLE',
                    value: value,
                    option: selectedOption,
                    previousValue: this.previousValue
                }
            }));
        }
    }

    /**
     * Returns the current selected value
     * @returns {string|null} The value of the selected option or null if nothing is selected
     * @public
     */
    @api
    getValue() {
        return this.selectedValue;
    }

    /**
     * Sets the selected value programmatically
     * @param {string|null} value - Value to select or null to deselect
     * @returns {boolean} true if the value was successfully set, false if the value was not found
     * @public
     */
    @api
    setValue(value) {
        if (value === null && this.allowDeselect) {
            this.previousValue = this.selectedValue;
            this.selectedValue = null;
            this.updateComputedClasses();
            return true;
        }

        if (this.options.some(opt => opt.value === value)) {
            this.previousValue = this.selectedValue;
            this.selectedValue = value;
            this.updateComputedClasses();
            return true;
        }

        return false;
    }

    /**
     * Returns the full object of the selected option
     * @returns {ToggleOption|null} Selected option object or null if nothing is selected
     * @public
     */
    @api
    getSelectedOption() {
        if (!this.selectedValue) return null;
        return this.options.find(opt => opt.value === this.selectedValue) || null;
    }

    /**
     * Updates the component configuration
     * @param {ToggleConfig} newConfig - New configuration
     * @param {boolean} [preserveSelection=false] - Preserve the current selection if possible
     * @public
     */
    @api
    updateConfig(newConfig, preserveSelection = false) {
        const currentValue = preserveSelection ? this.selectedValue : null;
        this._config = newConfig;
        this.processConfig();

        if (preserveSelection && currentValue) {
            this.setValue(currentValue);
        }
    }
}



/**
 * @typedef {Object} ToggleOption
 * @property {string} value - Unique option value
 * @property {string} label - Text displayed for the option
 * @property {string} [iconName] - Salesforce icon name (format: 'utility:world')
 * @property {string} [customClass] - Additional CSS class for the option
 * @property {Object} [metadata] - Additional metadata associated with the option
 */

/**
 * @typedef {Object} ToggleConfig
 * @property {ToggleOption[]} options - Array of options to display
 * @property {string} [defaultValue] - Default selected option value
 * @property {string} [id] - Toggle id
 * @property {string} [containerStyle] - Inline CSS styles for the container (format: 'property: value;')
 * @property {boolean} [allowDeselect=false] - Allows deselection (not selecting any option)
 * @property {string} [iconSize=xx-small] - Allows deselection (not selecting any option)
 * @property {Object} [metadata] - Additional metadata for the component
 * @example  {
 *         containerStyle: 'max-width: 300px;',
 *         defaultValue: 'internal',
 *         allowDeselect: false,
 *         iconSize: : "xx-small", // all icon sizes
 *         options: [
 *             {
 *                 value: 'portal',
 *                 label: 'Portal',
 *                 iconName: 'utility:world',
 *                 customClass: 'portal-option',
 *                 metadata: {
 *                     description: 'External portal access',
 *                     permissions: ['view_portal']
 *                 }
 *             },
 *             {
 *                 value: 'internal',
 *                 label: 'Internal',
 *                 iconName: 'utility:lock',
 *                 customClass: 'internal-option',
 *                 metadata: {
 *                     description: 'Internal system access',
 *                     permissions: ['view_internal', 'edit_internal']
 *                 }
 *             }
 *         ],
 *         metadata: {
 *             context: "any useful data"
 *         }
 *     }
 */

/**
 * @typedef {Object} ToggleChangeEventDetail
 * @property {string} value - Selected option value
 * @property {ToggleOption} option - Selected option object
 * @property {string|null} previousValue - Previously selected value
 */