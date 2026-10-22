import { LightningElement, api } from 'lwc';
import { ICONS } from './lucideIcons';

const DEFAULT_SIZE = 20;

/**
 * Renders a Linked Prototype (lucide) icon as inline SVG.
 *
 * Colour follows `currentColor`, so set `color` on the host or a parent.
 * Provide `alternative-text` only when the icon carries meaning on its own;
 * icons that merely decorate adjacent text stay hidden from assistive tech.
 *
 * <c-portal-icon name="upload-cloud" size="20"></c-portal-icon>
 */
export default class PortalIcon extends LightningElement {
    /** lucide icon name, e.g. "trending-up". */
    @api name;

    /** Rendered edge length in pixels. */
    @api size = DEFAULT_SIZE;

    /** Accessible name. Omit for decorative icons. */
    @api alternativeText;

    get shape() {
        const definition = ICONS[this.name];
        if (!definition) {
            return undefined;
        }
        return {
            paths: (definition.p || []).map((d, index) => ({ key: `p${index}`, d })),
            circles: (definition.c || []).map((circle, index) => ({ key: `c${index}`, ...circle })),
            rects: (definition.r || []).map((rect, index) => ({ key: `r${index}`, ...rect }))
        };
    }

    get sizeStyle() {
        const edge = Number(this.size) > 0 ? Number(this.size) : DEFAULT_SIZE;
        return `width:${edge}px;height:${edge}px;`;
    }

    get role() {
        return this.alternativeText ? 'img' : undefined;
    }

    get ariaLabel() {
        return this.alternativeText || undefined;
    }

    get ariaHidden() {
        return this.alternativeText ? undefined : 'true';
    }
}