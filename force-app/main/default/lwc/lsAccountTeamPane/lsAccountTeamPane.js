import { LightningElement, api, wire } from 'lwc';
import getHeaderView from '@salesforce/apex/LSAccountHeaderController.getHeaderView';

const ACCESS_FULL = 'Full';

function messageFrom(error) {
    const body = error?.body;
    if (Array.isArray(body)) {
        return body.map((item) => item?.message).filter(Boolean).join(' ');
    }
    if (typeof body?.message === 'string') {
        return body.message;
    }
    return error?.message || '';
}

/**
 * @author PWC Developer
 * @date 2026/11/05
 *
 * @description
 * GCL-100 - Right pane of the Life Sciences Customer 360 page.
 * Base renders nothing. Full shows the Life Sciences Account Team.
 */
export default class LsAccountTeamPane extends LightningElement {
    @api recordId;

    accessLevel;
    accessLoaded = false;
    accessError;

    @wire(getHeaderView, { accountId: '$recordId' })
    wiredAccess({ data, error }) {
        if (!this.recordId) {
            this.accessLoaded = true;
            this.accessLevel = undefined;
            return;
        }

        if (data) {
            this.accessLevel = data.accessLevel;
            this.accessError = undefined;
            this.accessLoaded = true;
        } else if (error) {
            this.accessLevel = undefined;
            this.accessError = messageFrom(error) || 'Unable to load the account team.';
            this.accessLoaded = true;
        }
    }

    get isLoading() {
        return Boolean(this.recordId) && !this.accessLoaded && !this.accessError;
    }

    get isFull() {
        return this.accessLevel === ACCESS_FULL;
    }
}