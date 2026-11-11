import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getHeaderView from '@salesforce/apex/LSAccountHeaderController.getHeaderView';

const ACCESS_FULL = 'Full';

/**
 * @author PWC Developer
 * @date 2026/11/06
 *
 * @description
 * GCL-100 - Headless gate used by the LS Customer 360 record page template.
 * Resolves Full or Base for the logged-in user and tells the template.
 * Any failure (for example no class access for another persona) resolves to
 * Full so that user keeps the standard Customer page.
 */
export default class LsAccessGate extends LightningElement {
    recordId;
    resolved = false;

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        const id = pageRef?.attributes?.recordId;
        if (id && id !== this.recordId) {
            this.recordId = id;
        }
    }

    @wire(getHeaderView, { accountId: '$recordId' })
    wiredAccess({ data, error }) {
        if (data) {
            this.resolve(data.accessLevel || ACCESS_FULL);
        } else if (error) {
            this.resolve(ACCESS_FULL);
        }
    }

    resolve(accessLevel) {
        this.dispatchEvent(
            new CustomEvent('accessresolved', {
                detail: { accessLevel, recordId: this.recordId }
            })
        );
    }
}