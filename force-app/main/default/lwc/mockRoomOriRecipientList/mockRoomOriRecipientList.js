import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';

const EXTERNAL_APPROVER_MESSAGE =
    'An external recipient is notification only. Choose Awareness for an email address, and use a valid email such as name@company.com.';
const EMAIL_PATTERN = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z][A-Za-z]+$/;
const ROLE_REQUIRED_MESSAGE = 'Select how this person receives the request.';
const USER_REQUIRED_MESSAGE = 'Select a Salesforce user.';
const EMAIL_REQUIRED_MESSAGE = 'Enter a valid email such as name@company.com.';

let rowSequence = 0;

/**
 * GC-3483. One approval recipient. The checkbox chooses a Salesforce user or an external email.
 */
function createRow(source) {
    rowSequence += 1;
    const exists = source ? source.existsInSalesforce !== false : true;
    return {
        key: String(rowSequence),
        existsInSalesforce: exists,
        userId: exists && source ? source.userId || null : null,
        email: !exists && source ? source.email || '' : '',
        role: source && source.role ? source.role : ''
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
        if (this.restored || !Array.isArray(value) || value.length === 0) {
            return;
        }
        this.rows = value.map((item) => createRow(item));
        this.restored = true;
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
        if (this.onlyOneRow) {
            return;
        }
        const key = event.currentTarget.dataset.key;
        this.rows = this.rows.filter((row) => row.key !== key);
        this.publish();
    }

    handleExistsChange(event) {
        const key = event.currentTarget.dataset.key;
        const exists = event.detail.checked === true;
        this.updateRow(key, {
            existsInSalesforce: exists,
            userId: null,
            email: ''
        });
        this.applyExternalApproverValidity(key);
    }

    handleUserChange(event) {
        this.updateRow(event.currentTarget.dataset.key, {
            userId: event.detail.recordId || null
        });
    }

    handleEmailChange(event) {
        this.updateRow(event.currentTarget.dataset.key, {
            email: event.detail.value || ''
        });
    }

    handleRoleChange(event) {
        const key = event.currentTarget.dataset.key;
        this.updateRow(key, { role: event.detail.value || '' });
        this.applyExternalApproverValidity(key);
    }

    @api
    validate() {
        let firstMessage = '';
        this.rows.forEach((row) => {
            const card = this.template.querySelector(`section[data-key="${row.key}"]`);
            if (!card) {
                return;
            }
            const roleMessage = this.roleMessage(row);
            const roleInput = card.querySelector('lightning-combobox');
            roleInput.setCustomValidity(roleMessage);
            if (!roleInput.reportValidity() && !firstMessage) {
                firstMessage = roleMessage;
            }
            if (row.existsInSalesforce) {
                const picker = card.querySelector('lightning-record-picker');
                if (picker && !picker.reportValidity() && !firstMessage) {
                    firstMessage = USER_REQUIRED_MESSAGE;
                }
            } else {
                const emailMessage = this.emailMessage(row);
                const emailField = card.querySelector('c-mock-room-ori-external-email');
                if (emailField && !emailField.setError(emailMessage) && !firstMessage) {
                    firstMessage = emailMessage;
                }
            }
        });
        if (firstMessage) {
            return { isValid: false, errorMessage: firstMessage };
        }
        this.publish();
        return { isValid: true };
    }

    updateRow(key, changes) {
        this.rows = this.rows.map((row) => (row.key === key ? { ...row, ...changes } : row));
        this.publish();
    }

    applyExternalApproverValidity(key) {
        const row = this.rows.find((item) => item.key === key);
        const card = this.template.querySelector(`section[data-key="${key}"]`);
        if (!row || !card) {
            return;
        }
        const roleInput = card.querySelector('lightning-combobox');
        const message = !row.existsInSalesforce && row.role === 'Approver' ? EXTERNAL_APPROVER_MESSAGE : '';
        roleInput.setCustomValidity(message);
        if (message || row.role) {
            roleInput.reportValidity();
        }
    }

    roleMessage(row) {
        if (!row.role) {
            return ROLE_REQUIRED_MESSAGE;
        }
        if (!row.existsInSalesforce && row.role === 'Approver') {
            return EXTERNAL_APPROVER_MESSAGE;
        }
        return '';
    }

    emailMessage(row) {
        const email = (row.email || '').trim();
        if (!EMAIL_PATTERN.test(email)) {
            return EMAIL_REQUIRED_MESSAGE;
        }
        return '';
    }

    publish() {
        const recipients = this.rows.map((row) => ({
            userId: row.existsInSalesforce ? row.userId || null : null,
            email: row.existsInSalesforce ? null : row.email || null,
            role: row.role || null,
            existsInSalesforce: row.existsInSalesforce === true
        }));
        this._recipients = recipients;
        this.dispatchEvent(new FlowAttributeChangeEvent('recipients', recipients));
    }
}