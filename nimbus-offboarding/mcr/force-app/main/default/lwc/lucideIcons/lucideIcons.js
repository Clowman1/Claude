/**
 *****************************************************
 * @date created date : March 10, 2026
 * @description       : Renders Lucide icons via static resource
 * @author            : Andrei Karanko
 Modification Log:
 Ver   Date         Author                               Modification
 1.0   10.03.2026   Andrei Karanko                          Initial Version
 2.0   15.03.2026   Andrei Karanko                          Refactored to use Lucide static resource
 *****************************************************
 */
import { api, LightningElement } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import LUCIDE from '@salesforce/resourceUrl/LucideIcons';

export default class LucideIcons extends LightningElement {
  @api name;

  lucideLoaded = false;
  currentName;

  async renderedCallback() {
    if (this.currentName === this.name) {
      return;
    }
    this.currentName = this.name;

    if (!this.lucideLoaded) {
      await loadScript(this, LUCIDE);
      this.lucideLoaded = true;
    }

    const iconName = LucideIcons.toPascalCase(this.name);
    const iconData = globalThis.lucide?.icons?.[iconName];

    if (!iconData) {
      console.warn(`lucideIcons: icon "${this.name}" (${iconName}) not found`);
      return;
    }

    const container = this.template.querySelector('.icon');
    container.innerHTML = '';
    container.appendChild(globalThis.lucide.createElement(iconData));
  }

  static toPascalCase(name) {
    return name
      .split('-')
      .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
      .join('');
  }
}