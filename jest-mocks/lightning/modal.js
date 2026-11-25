/**
 * Jest mock for lightning/modal (sfdx-lwc-jest has no LightningModal stub).
 * - LightningModal.open is a jest.fn shared by every modal subclass: tests queue results with
 *   mockResolvedValueOnce in the order the modals open.
 * - close(result) fires a "close" event with the result so tests can read what the modal returned.
 */
import { LightningElement, api } from 'lwc';

export default class LightningModal extends LightningElement {
    static open = jest.fn();

    @api size;
    @api label;
    @api description;
    @api disableClose;

    close(result) {
        this.dispatchEvent(new CustomEvent('close', { detail: result }));
    }
}
