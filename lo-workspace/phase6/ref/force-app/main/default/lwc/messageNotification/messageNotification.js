/**
 * Created by andrk on 6/26/2024.
 */

import { LightningElement, api } from 'lwc';

export default class MessageNotification extends LightningElement {
  @api label;
  @api variant = 'info';
  @api isRelativeModal = false; // opens as a relative modal inside the parent component
  @api isInlineModal = false; // opens as an inline modal inside the parent component
  @api isSlidingPanel = false; // opens as a sliding panel from the right side of the screen
  /** Slot fallback for Aura parents (Aura can't pass slot content to LWC). LWC parents should use slot content instead. */
  @api message;

  /** @deprecated Use variant instead */
  @api iconName;
  /** @deprecated Use variant instead */
  @api backgroundColor;
  /** @deprecated Controlled by parent via lwc:if */
  @api showNotification = false;

  _showNotification = false;

  renderedCallback() {
    if (this._showNotification) {
      return;
    }
    this.setVariantClass();
    this.template.querySelector('dialog')?.showModal();
    this._showNotification = true;
  }

  setVariantClass() {
    switch (this.variant) {
      case 'success':
        this.template.querySelector('.mn__wrapper')?.classList.add('mn__success');
        break;
      case 'error':
        this.template.querySelector('.mn__wrapper')?.classList.add('mn__error');
        break;
      case 'warning':
        this.template.querySelector('.mn__wrapper')?.classList.add('mn__warning');
        break;
      default:
        this.template.querySelector('.mn__wrapper')?.classList.add('mn__info');
        break;
    }
  }

  handleDialogClick(event) {
    try {
      const dialog = this.template.querySelector('dialog');
      const contentDimensions = dialog.getBoundingClientRect();
      if (
        event.clientX < contentDimensions.left ||
        event.clientX > contentDimensions.right ||
        event.clientY < contentDimensions.top ||
        event.clientY > contentDimensions.bottom
      ) {
        dialog.close();
        this.dispatchEvent(new CustomEvent('close'));
      }
    } catch ({ message, stack }) {
      console.log('error handling dialog click', message, stack);
    }
  }

  handleKeyDown(event) {
    if (event.key === 'Escape' || event.key === 'Esc') {
      this.template.querySelector('dialog')?.close();
      this.dispatchEvent(new CustomEvent('close'));
    }
  }

  handleCloseNotification(event) {
    event.stopPropagation();
    this.template.querySelector('dialog')?.close();
    this.dispatchEvent(new CustomEvent('close'));
  }
}