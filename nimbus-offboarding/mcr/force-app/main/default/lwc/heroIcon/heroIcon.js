/**
 *********************************************************
 * @name                 : heroIcon
 * @date                   : 29.12.2024
 * @description       : -
 * @author               : Taras Babyn
 * @change log        : Dec 29, 2024 Taras Babyn - Initial Version
 *********************************************************
 */
import {api, LightningElement} from "lwc";
import './icon';

export {Icon} from './icon';

/**
 * @example <c-hero-icon name="check" scale="2" rotate="90" block stroke="currentColor" icon-style="color: red;"></c-hero-icon>
 * @attr {string} name - icon name
 * @attr {number} [scale] - icon scale
 * @attr {number} [rotate] - icon rotate
 * @attr {boolean} [block] - icon block
 * @attr {string} [stroke] - icon stroke
 * @attr {string} [icon-style] - icon style
 * @attr {boolean} [checked] - icon checked
 */
export default class HeroIcon extends LightningElement {

    @api name;
    @api scale = 1.5;
    @api rotate;
    @api block;
    @api stroke;
    @api iconStyle;
    @api checked;

    _isLoading;

    @api set isBoolean(value) {
        this._isBoolean = value;
        if (this._isBoolean) {
            this.name = this.checked ? 'check' : 'x-mark';
            this.iconStyle = 'color: ' + (this.checked ? '#2ECC40FF' : '#FF4136FF') + ';';
        }
    }

    get isBoolean() {
        return this._isBoolean;
    }

    @api get isLoading() {
        return this._isLoading;
    }

    set isLoading(value) {
        this._isLoading = value;
    }

    get scaleAsEm() {
        return `${this.scale}em`;
    }
}