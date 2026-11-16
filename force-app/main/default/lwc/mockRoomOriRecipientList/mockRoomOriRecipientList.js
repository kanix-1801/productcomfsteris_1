import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';

const EXTERNAL_APPROVER_MESSAGE =
    'An external recipient is notification only. Choose Awareness for an email address, and use a valid email such as name@company.com.';
const EMAIL_PATTERN = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z][A-Za-z]+$/;
const ROLE_REQUIRED_MESSAGE = 'Select how this person receives the request.';
const USER_REQUIRED_MESSAGE = 'Select a Salesforce user.';
const EMAIL_REQUIRED_MESSAGE = 'Enter a valid email such as name@company.com.';

let rowSequence = 0;

/** GC-3483. One approval recipient. The checkbox chooses a Salesforce user or an external email. */
function createRow(source) {
    const { isSalesforceUser, userId, email, role } = source || {};
    const exists = isSalesforceUser !== false;
    rowSequence += 1;
    return {
        key: String(rowSequence),
        existsInSalesforce: exists,
        userId: exists ? userId || null : null,
        email: exists ? '' : email || '',
        role: role || ''
    };
}

export default class MockRoomOriRecipientList extends LightningElement {
    roleOptions = [
        { label: 'Approver', value: 'Approver' },
        { label: 'Awareness / Notification Only', value: 'Awareness' }
    ];

    rows = [];
    restored = false;

    @api
    get recipients() {
        return this._recipients;
    }
    set recipients(value) {
        this._recipients = value;
        if (!this.restored && Array.isArray(value) && value.length > 0) {
            this.rows = value.map((item) => createRow(item));
            this.restored = true;
        }
    }

    connectedCallback() {
        if (this.rows.length === 0) {
            this.rows = [createRow()];
            this.restored = true;
        }
        this.publish();
    }

    get onlyOneRow() {
        return this.rows.length <= 1;
    }

    handleAdd() {
        this.rows = [...this.rows, createRow()];
        this.publish();
    }

    handleRemove(event) {
        this.rows = this.rows.filter((row) => row.key !== event.currentTarget.dataset.key);
        this.publish();
    }

    handleExistsChange(event) {
        const key = event.currentTarget.dataset.key;
        this.updateRow(key, { existsInSalesforce: event.detail.checked === true, userId: null, email: '' });
        this.showExternalApproverError(key);
    }

    handleUserChange(event) {
        this.updateRow(event.currentTarget.dataset.key, { userId: event.detail.recordId || null });
    }

    handleEmailChange(event) {
        this.updateRow(event.currentTarget.dataset.key, { email: event.detail.value || '' });
    }

    handleRoleChange(event) {
        const key = event.currentTarget.dataset.key;
        this.updateRow(key, { role: event.detail.value || '' });
        this.showExternalApproverError(key);
    }

    /** Runs on Submit for Approval. Required and email errors are shown only here, not while the user is typing. */
    @api
    validate() {
        let errorMessage = '';
        this.rows.forEach((row) => {
            const card = this.cardFor(row.key);
            if (!card) {
                return;
            }
            const roleMessage = row.role ? this.externalApproverMessage(row) : ROLE_REQUIRED_MESSAGE;
            const roleInput = card.querySelector('lightning-combobox');
            roleInput.setCustomValidity(roleMessage);
            if (!roleInput.reportValidity()) {
                errorMessage = errorMessage || roleMessage;
            }
            const personValid = row.existsInSalesforce
                ? card.querySelector('lightning-record-picker').reportValidity()
                : card.querySelector('c-mock-room-ori-external-email')
                    .setError(EMAIL_PATTERN.test((row.email || '').trim()) ? '' : EMAIL_REQUIRED_MESSAGE);
            if (!personValid) {
                errorMessage = errorMessage || (row.existsInSalesforce ? USER_REQUIRED_MESSAGE : EMAIL_REQUIRED_MESSAGE);
            }
        });
        if (errorMessage) {
            return { isValid: false, errorMessage };
        }
        this.publish();
        return { isValid: true };
    }

    updateRow(key, changes) {
        this.rows = this.rows.map((row) => (row.key === key ? { ...row, ...changes } : row));
        this.publish();
    }

    showExternalApproverError(key) {
        const row = this.rows.find((item) => item.key === key);
        const roleInput = this.cardFor(key)?.querySelector('lightning-combobox');
        if (!row || !roleInput) {
            return;
        }
        const message = this.externalApproverMessage(row);
        roleInput.setCustomValidity(message);
        if (message || row.role) {
            roleInput.reportValidity();
        }
    }

    externalApproverMessage(row) {
        return !row.existsInSalesforce && row.role === 'Approver' ? EXTERNAL_APPROVER_MESSAGE : '';
    }

    cardFor(key) {
        return this.template.querySelector(`section[data-key="${key}"]`);
    }

    publish() {
        const recipients = this.rows.map((row) => ({
            userId: row.existsInSalesforce ? row.userId || null : null,
            email: row.existsInSalesforce ? null : row.email || null,
            role: row.role || null,
            isSalesforceUser: row.existsInSalesforce === true
        }));
        this._recipients = recipients;
        this.dispatchEvent(new FlowAttributeChangeEvent('recipients', recipients));
    }
}