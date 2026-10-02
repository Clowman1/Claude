/**
 *********************************************************
 * @name                 : Icon
 * @date                   : 21.12.2024
 * @description       : -
 * @author               : Taras Babyn
 * @change log        : Dec 21, 2024 Taras Babyn - Initial Version
 *********************************************************
 */
import icons from './icons.js';

/**
 * @typedef {keyof typeof icons} IconName
 */

/**
 * @class Icon
 * @extends HTMLElement
 * @description Custom element for rendering icons
 * @attribute {IconName} name - Icon name

 */
export class Icon extends HTMLElement {
    static _icons = icons;

    static _fallbackIcon = `<path d="M3,3 L21,3 L21,21 L3,21 L3,3 M3,3 L21,21 M21,3 L3,21" stroke-width="1"/>`;

    constructor() {
        super();
        this.attachShadow({ mode: "open" });
    }

    _attrs = {};

    connectedCallback() {
        try {
            this._attrs.name = this.getAttribute("name");
            this._attrs.scale = this.getAttribute("scale");
            this._attrs.rotate = this.getAttribute("rotate");
            this._attrs.block = this.getAttribute("block");
            this._attrs.stroke = this.getAttribute("stroke");
            this._render();
        } catch (e) {
            console.error(e);
        }

    }

    static get observedAttributes() {
        return ["name", "scale", "rotate", "block", "style", "stroke"];
    }

    attributeChangedCallback(name, oldValue, newValue) {
        if (oldValue === newValue) return;

        this._attrs[name] = newValue;
        this._render();
    }

    wrapSvg(iconSvg) {
        return `
            <svg viewBox="0 0 24 24"  fill="none" viewBox="0 0 24 24" stroke-width=${this._attrs.stroke ?? 1.5} stroke="currentColor" >
                ${iconSvg}
            </svg>
                `;
        ;
    }

    _render() {
        let iconSvg = Icon._fallbackIcon;

        this._attrs.name = this._attrs.name ? this._attrs.name.trim() : null;

        if (Icon._icons[this._attrs.name]) {
            iconSvg = ((Icon._icons)[this._attrs.name]);
        }

        iconSvg = iconSvg.replace(/<path/g, `<path stroke-linecap="round" stroke-linejoin="round" `);

        iconSvg = this.wrapSvg(iconSvg);
        this.shadowRoot.innerHTML = `
      <style>
        :host {
          display: flex;
        }
        
      
      
        svg {
          height: ${this._attrs.scale || 1.5}em;
          ${
            this._attrs.rotate != null
                ? `transform: rotate(${this._attrs.rotate}deg);`
                : ""
        }
            ${
            this._attrs.style != null
                ? `${this._attrs.style}`
                : ""
        }
      </style>
      ${iconSvg}
    `;
    }

}

customElements.define("hero-icon", Icon);

// /**
//  * @typedef {Object} IconName
//  * @property {string} academic-cap
//  * @property {string} adjustments-horizontal
//  * @property {string} adjustments-vertical
//  * @property {string} archive-box-arrow-down
//  * @property {string} archive-box-x-mark
//  * @property {string} archive-box
//  * @property {string} arrow-down-circle
//  * @property {string} arrow-down-left
//  * @property {string} arrow-down-on-square-stack
//  * @property {string} arrow-down-on-square
//  * @property {string} arrow-down-right
//  * @property {string} arrow-down-tray
//  * @property {string} arrow-down
//  * @property {string} arrow-left-circle
//  * @property {string} arrow-left-end-on-rectangle
//  * @property {string} arrow-left-on-rectangle
//  * @property {string} arrow-left-start-on-rectangle
//  * @property {string} arrow-left
//  * @property {string} arrow-long-down
//  * @property {string} arrow-long-left
//  * @property {string} arrow-long-right
//  * @property {string} arrow-long-up
//  * @property {string} arrow-path-rounded-square
//  * @property {string} arrow-path
//  * @property {string} arrow-right-circle
//  * @property {string} arrow-right-end-on-rectangle
//  * @property {string} arrow-right-on-rectangle
//  * @property {string} arrow-right-start-on-rectangle
//  * @property {string} arrow-right
//  * @property {string} arrow-small-down
//  * @property {string} arrow-small-left
//  * @property {string} arrow-small-right
//  * @property {string} arrow-small-up
//  * @property {string} arrow-top-right-on-square
//  * @property {string} arrow-trending-down
//  * @property {string} arrow-trending-up
//  * @property {string} arrow-turn-down-left
//  * @property {string} arrow-turn-down-right
//  * @property {string} arrow-turn-left-down
//  * @property {string} arrow-turn-left-up
//  * @property {string} arrow-turn-right-down
//  * @property {string} arrow-turn-right-up
//  * @property {string} arrow-turn-up-left
//  * @property {string} arrow-turn-up-right
//  * @property {string} arrow-up-circle
//  * @property {string} arrow-up-left
//  * @property {string} arrow-up-on-square-stack
//  * @property {string} arrow-up-on-square
//  * @property {string} arrow-up-right
//  * @property {string} arrow-up-tray
//  * @property {string} arrow-up
//  * @property {string} arrow-uturn-down
//  * @property {string} arrow-uturn-left
//  * @property {string} arrow-uturn-right
//  * @property {string} arrow-uturn-up
//  * @property {string} arrows-pointing-in
//  * @property {string} arrows-pointing-out
//  * @property {string} arrows-right-left
//  * @property {string} arrows-up-down
//  * @property {string} at-symbol
//  * @property {string} backspace
//  * @property {string} backward
//  * @property {string} banknotes
//  * @property {string} bars-2
//  * @property {string} bars-3-bottom-left
//  * @property {string} bars-3-bottom-right
//  * @property {string} bars-3-center-left
//  * @property {string} bars-3
//  * @property {string} bars-4
//  * @property {string} bars-arrow-down
//  * @property {string} bars-arrow-up
//  * @property {string} battery-0
//  * @property {string} battery-100
//  * @property {string} battery-50
//  * @property {string} beaker
//  * @property {string} bell-alert
//  * @property {string} bell-slash
//  * @property {string} bell-snooze
//  * @property {string} bell
//  * @property {string} bold
//  * @property {string} bolt-slash
//  * @property {string} bolt
//  * @property {string} book-open
//  * @property {string} bookmark-slash
//  * @property {string} bookmark-square
//  * @property {string} bookmark
//  * @property {string} briefcase
//  * @property {string} bug-ant
//  * @property {string} building-library
//  * @property {string} building-office-2
//  * @property {string} building-office
//  * @property {string} building-storefront
//  * @property {string} cake
//  * @property {string} calculator
//  * @property {string} calendar-date-range
//  * @property {string} calendar-days
//  * @property {string} calendar
//  * @property {string} camera
//  * @property {string} chart-bar-square
//  * @property {string} chart-bar
//  * @property {string} chart-pie
//  * @property {string} chat-bubble-bottom-center-text
//  * @property {string} chat-bubble-bottom-center
//  * @property {string} chat-bubble-left-ellipsis
//  * @property {string} chat-bubble-left-right
//  * @property {string} chat-bubble-left
//  * @property {string} chat-bubble-oval-left-ellipsis
//  * @property {string} chat-bubble-oval-left
//  * @property {string} check-badge
//  * @property {string} check-circle
//  * @property {string} check
//  * @property {string} chevron-double-down
//  * @property {string} chevron-double-left
//  * @property {string} chevron-double-right
//  * @property {string} chevron-double-up
//  * @property {string} chevron-down
//  * @property {string} chevron-left
//  * @property {string} chevron-right
//  * @property {string} chevron-up-down
//  * @property {string} chevron-up
//  * @property {string} circle-stack
//  * @property {string} clipboard-document-check
//  * @property {string} clipboard-document-list
//  * @property {string} clipboard-document
//  * @property {string} clipboard
//  * @property {string} clock
//  * @property {string} cloud-arrow-down
//  * @property {string} cloud-arrow-up
//  * @property {string} cloud
//  * @property {string} code-bracket-square
//  * @property {string} code-bracket
//  * @property {string} cog-6-tooth
//  * @property {string} cog-8-tooth
//  * @property {string} cog
//  * @property {string} command-line
//  * @property {string} computer-desktop
//  * @property {string} cpu-chip
//  * @property {string} credit-card
//  * @property {string} cube-transparent
//  * @property {string} cube
//  * @property {string} currency-bangladeshi
//  * @property {string} currency-dollar
//  * @property {string} currency-euro
//  * @property {string} currency-pound
//  * @property {string} currency-rupee
//  * @property {string} currency-yen
//  * @property {string} cursor-arrow-rays
//  * @property {string} cursor-arrow-ripple
//  * @property {string} device-phone-mobile
//  * @property {string} device-tablet
//  * @property {string} divide
//  * @property {string} document-arrow-down
//  * @property {string} document-arrow-up
//  * @property {string} document-chart-bar
//  * @property {string} document-check
//  * @property {string} document-currency-bangladeshi
//  * @property {string} document-currency-dollar
//  * @property {string} document-currency-euro
//  * @property {string} document-currency-pound
//  * @property {string} document-currency-rupee
//  * @property {string} document-currency-yen
//  * @property {string} document-duplicate
//  * @property {string} document-magnifying-glass
//  * @property {string} document-minus
//  * @property {string} document-plus
//  * @property {string} document-text
//  * @property {string} document
//  * @property {string} ellipsis-horizontal-circle
//  * @property {string} ellipsis-horizontal
//  * @property {string} ellipsis-vertical
//  * @property {string} envelope-open
//  * @property {string} envelope
//  * @property {string} equals
//  * @property {string} exclamation-circle
//  * @property {string} exclamation-triangle
//  * @property {string} eye-dropper
//  * @property {string} eye-slash
//  * @property {string} eye
//  * @property {string} face-frown
//  * @property {string} face-smile
//  * @property {string} film
//  * @property {string} finger-print
//  * @property {string} fire
//  * @property {string} flag
//  * @property {string} folder-arrow-down
//  * @property {string} folder-minus
//  * @property {string} folder-open
//  * @property {string} folder-plus
//  * @property {string} folder
//  * @property {string} forward
//  * @property {string} funnel
//  * @property {string} gif
//  * @property {string} gift-top
//  * @property {string} gift
//  * @property {string} globe-alt
//  * @property {string} globe-americas
//  * @property {string} globe-asia-australia
//  * @property {string} globe-europe-africa
//  * @property {string} h1
//  * @property {string} h2
//  * @property {string} h3
//  * @property {string} hand-raised
//  * @property {string} hand-thumb-down
//  * @property {string} hand-thumb-up
//  * @property {string} hashtag
//  * @property {string} heart
//  * @property {string} home-modern
//  * @property {string} home
//  * @property {string} identification
//  * @property {string} inbox-arrow-down
//  * @property {string} inbox-stack
//  * @property {string} inbox
//  * @property {string} information-circle
//  * @property {string} italic
//  * @property {string} key
//  * @property {string} language
//  * @property {string} lifebuoy
//  * @property {string} light-bulb
//  * @property {string} link-slash
//  * @property {string} link
//  * @property {string} list-bullet
//  * @property {string} lock-closed
//  * @property {string} lock-open
//  * @property {string} magnifying-glass-circle
//  * @property {string} magnifying-glass-minus
//  * @property {string} magnifying-glass-plus
//  * @property {string} magnifying-glass
//  * @property {string} map-pin
//  * @property {string} map
//  * @property {string} megaphone
//  * @property {string} microphone
//  * @property {string} minus-circle
//  * @property {string} minus-small
//  * @property {string} minus
//  * @property {string} moon
//  * @property {string} musical-note
//  * @property {string} newspaper
//  * @property {string} no-symbol
//  * @property {string} numbered-list
//  * @property {string} paint-brush
//  * @property {string} paper-airplane
//  * @property {string} paper-clip
//  * @property {string} pause-circle
//  * @property {string} pause
//  * @property {string} pencil-square
//  * @property {string} pencil
//  * @property {string} percent-badge
//  * @property {string} phone-arrow-down-left
//  * @property {string} phone-arrow-up-right
//  * @property {string} phone-x-mark
//  * @property {string} phone
//  * @property {string} photo
//  * @property {string} play-circle
//  * @property {string} play-pause
//  * @property {string} play
//  * @property {string} plus-circle
//  * @property {string} plus-small
//  * @property {string} plus
//  * @property {string} power
//  * @property {string} presentation-chart-bar
//  * @property {string} presentation-chart-line
//  * @property {string} printer
//  * @property {string} puzzle-piece
//  * @property {string} qr-code
//  * @property {string} question-mark-circle
//  * @property {string} queue-list
//  * @property {string} radio
//  * @property {string} receipt-percent
//  * @property {string} receipt-refund
//  * @property {string} rectangle-group
//  * @property {string} rectangle-stack
//  * @property {string} rocket-launch
//  * @property {string} rss
//  * @property {string} scale
//  * @property {string} scissors
//  * @property {string} server-stack
//  * @property {string} server
//  * @property {string} share
//  * @property {string} shield-check
//  * @property {string} shield-exclamation
//  * @property {string} shopping-bag
//  * @property {string} shopping-cart
//  * @property {string} signal-slash
//  * @property {string} signal
//  * @property {string} slash
//  * @property {string} sparkles
//  * @property {string} speaker-wave
//  * @property {string} speaker-x-mark
//  * @property {string} square-2-stack
//  * @property {string} square-3-stack-3d
//  * @property {string} squares-2x2
//  * @property {string} squares-plus
//  * @property {string} star
//  * @property {string} stop-circle
//  * @property {string} stop
//  * @property {string} strikethrough
//  * @property {string} sun
//  * @property {string} swatch
//  * @property {string} table-cells
//  * @property {string} tag
//  * @property {string} ticket
//  * @property {string} trash
//  * @property {string} trophy
//  * @property {string} truck
//  * @property {string} tv
//  * @property {string} underline
//  * @property {string} user-circle
//  * @property {string} user-group
//  * @property {string} user-minus
//  * @property {string} user-plus
//  * @property {string} user
//  * @property {string} users
//  * @property {string} variable
//  * @property {string} video-camera-slash
//  * @property {string} video-camera
//  * @property {string} view-columns
//  * @property {string} viewfinder-circle
//  * @property {string} wallet
//  * @property {string} wifi
//  * @property {string} window
//  * @property {string} wrench-screwdriver
//  * @property {string} wrench
//  * @property {string} x-circle
//  * @property {string} x-mark
//  */