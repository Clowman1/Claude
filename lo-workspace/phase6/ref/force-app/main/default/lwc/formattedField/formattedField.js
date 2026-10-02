/**
 *****************************************************
 * @date created date : Feb 20, 2025
 * @description       :
 * @author            : Andrei Karanko
 Modification Log:
 Ver   Date         Author                               Modification
 1.0   20.02.2025   Andrei Karanko                          Initial Version
 *****************************************************
 */
import { LightningElement, api } from 'lwc';

export default class FormattedField extends LightningElement {
  @api fieldValue;
  @api fieldType;
  @api percentFormatStyle = 'percent';

  get isText() {
    const textTypes = new Set([
      'STRING',
      'ADDRESS',
      'ANYTYPE',
      'COMBOBOX',
      'DATACATEGORYGROUPREFERENCE',
      'ENCRYPTEDSTRING',
      'ID',
      'JSON',
      'LOCATION',
      'MULTIPICKLIST',
      'PICKLIST',
      'REFERENCE',
      'SOBJECT',
      'TEXTAREA',
      'TIME',
      'URL'
    ]);
    return textTypes.has(this.fieldType);
  }

  get isDate() {
    return this.fieldType === 'DATE';
  }

  get isDateTime() {
    return this.fieldType === 'DATETIME';
  }

  get isCurrency() {
    return this.fieldType === 'CURRENCY';
  }

  get isInteger() {
    return this.fieldType === 'INTEGER';
  }

  get isDecimal() {
    return this.fieldType === 'DOUBLE' || this.fieldType === 'LONG';
  }

  get isPercent() {
    return this.fieldType === 'PERCENT';
  }

  get isBoolean() {
    return this.fieldType === 'BOOLEAN';
  }

  get isEmail() {
    return this.fieldType === 'EMAIL';
  }

  get isPhone() {
    return this.fieldType === 'PHONE';
  }
}