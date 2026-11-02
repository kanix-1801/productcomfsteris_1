import { LightningElement, api } from 'lwc';

const MODE_SINGLE = 'single';
const MODE_MULTI = 'multi';

/**
 * GW-3400 - Selectable product / repair-code card grid.
 * Host owns selected state on each card (`selected`).
 */
export default class RepairCenterProductCardGrid extends LightningElement {
    /**
     * Card objects: { cardId, title, name, selected }.
     * @type {Array}
     */
    @api cards = [];

    /**
     * `single` fires cardselect; `multi` fires cardtoggle.
     * @type {string}
     */
    @api selectionMode = MODE_SINGLE;

    /**
     * Empty-state copy when there are no cards.
     * @type {string}
     */
    @api emptyMessage = 'No items available.';

    get hasCards() {
        return Array.isArray(this.cards) && this.cards.length > 0;
    }

    get displayCards() {
        return (this.cards || []).map((card) => {
            const selected = card?.selected === true;
            return {
                ...card,
                buttonClass: selected ? 'code-card code-card_selected' : 'code-card',
                checkboxClass: selected
                    ? 'code-card__checkbox code-card__checkbox_checked'
                    : 'code-card__checkbox'
            };
        });
    }

    /**
     * GW-3400 - Selects or toggles a card.
     * @param {Event} event click
     */
    handleCardClick(event) {
        const cardId = event.currentTarget?.dataset?.cardId;
        this.emitSelection(cardId);
    }

    /**
     * GW-3400 - Keyboard activation for card buttons.
     * @param {KeyboardEvent} event keydown
     */
    handleCardKeyDown(event) {
        if (event.key !== 'Enter' && event.key !== ' ') {
            return;
        }
        event.preventDefault();
        const cardId = event.currentTarget?.dataset?.cardId;
        this.emitSelection(cardId);
    }

    emitSelection(cardId) {
        if (!cardId) {
            return;
        }
        const isMulti = this.selectionMode === MODE_MULTI;
        this.dispatchEvent(
            new CustomEvent(isMulti ? 'cardtoggle' : 'cardselect', {
                detail: { cardId }
            })
        );
    }
}