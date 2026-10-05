import { LightningElement, api } from 'lwc';

const VARIANT_CLASSES = {
  neutral: 'action-button--neutral',
  brand: 'action-button--brand',
  destructive: 'action-button--destructive',
  success: 'action-button--success'
};

export default class ActionButton extends LightningElement {
  /** @type {string} Button label text */
  @api label = '';
  /** @type {'neutral'|'brand'|'destructive'|'success'} */
  @api variant = 'neutral';
  /** @type {string} Lucide icon name (e.g. 'plus', 'check', 'trash-2') */
  @api iconName;
  /** @type {'left'|'right'} Icon position relative to the label */
  @api iconPosition = 'left';
  /** @type {boolean} */
  @api disabled = false;

  isLoading = false;

  @api
  startLoading() {
    this.isLoading = true;
  }

  @api
  stopLoading() {
    this.isLoading = false;
  }

  get buttonClass() {
    const classes = ['action-button'];
    classes.push(VARIANT_CLASSES[this.variant] || VARIANT_CLASSES.neutral);
    if (this.isLoading) {
      classes.push('action-button--loading');
    }
    return classes.join(' ');
  }

  get isDisabled() {
    return this.disabled || this.isLoading;
  }

  get hasLeftIcon() {
    return this.iconName && this.iconPosition !== 'right';
  }

  get hasRightIcon() {
    return this.iconName && this.iconPosition === 'right';
  }

  handleClick(event) {
    if (this.isDisabled) {
      event.stopPropagation();
    }
  }
}