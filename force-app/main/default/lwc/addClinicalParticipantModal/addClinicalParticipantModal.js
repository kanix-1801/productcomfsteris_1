import { api, track, wire } from 'lwc';
import LightningModal from 'lightning/modal';
import { getFieldValue, getRecord } from 'lightning/uiRecordApi';
import USER_NAME_FIELD from '@salesforce/schema/User.Name';
import USER_EMAIL_FIELD from '@salesforce/schema/User.Email';
import getSalesforceUser from '@salesforce/apex/ClinicalParticipantService.getSalesforceUser';

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export default class AddClinicalParticipantModal extends LightningModal {
    @api participantsJson;
    @track rows = [];
    lookupUserId;
    errorMessage = '';
    saving = false;

    @wire(getRecord, { recordId: '$lookupUserId', fields: [USER_NAME_FIELD, USER_EMAIL_FIELD] })
    loadSelectedUser({ data }) {
        if (!data) {
            return;
        }
        const loadedId = data.id || '';
        const row = this.rows.find((item) => item.userId && loadedId.startsWith(item.userId));
        if (!row) {
            return;
        }
        this.updateRow(row.key, {
            name: getFieldValue(data, USER_NAME_FIELD) || '',
            email: getFieldValue(data, USER_EMAIL_FIELD) || ''
        });
    }

    connectedCallback() {
        this.rows = this.parseRows(this.participantsJson);
        if (this.rows.length === 0) {
            this.rows = [this.emptyRow()];
        }
    }

    parseRows(participantsJson) {
        try {
            const parsed = participantsJson ? JSON.parse(participantsJson) : [];
            if (!Array.isArray(parsed)) {
                return [];
            }
            return parsed.map((row) =>
                this.shapeRow({
                    key: this.newKey(),
                    participantType: row.userId ? 'user' : 'external',
                    userId: row.userId || null,
                    name: row.name || '',
                    email: row.email || ''
                })
            );
        } catch (e) {
            return [];
        }
    }

    emptyRow() {
        return this.shapeRow({
            key: this.newKey(),
            participantType: 'user',
            userId: null,
            name: '',
            email: ''
        });
    }

    shapeRow(row) {
        const participantType = row.participantType || '';
        return {
            key: row.key,
            participantType,
            userId: row.userId || null,
            name: row.name || '',
            email: row.email || '',
            isSalesforceUser: participantType === 'user',
            isExternal: participantType === 'external'
        };
    }

    newKey() {
        return `${Date.now()}-${Math.random()}`;
    }

    addRow() {
        this.rows = [...this.rows, this.emptyRow()];
        this.errorMessage = '';
    }

    removeRow(event) {
        const key = event.currentTarget.dataset.key;
        const remaining = this.rows.filter((row) => row.key !== key);
        this.rows = remaining.length === 0 ? [this.emptyRow()] : remaining;
        this.errorMessage = '';
    }

    handleExternalChange(event) {
        this.updateRow(event.target.dataset.key, {
            participantType: event.target.checked ? 'external' : 'user',
            userId: null,
            name: '',
            email: ''
        });
    }

    handleNameChange(event) {
        this.updateRow(event.target.dataset.key, { name: event.target.value });
    }

    handleEmailChange(event) {
        this.updateRow(event.target.dataset.key, { email: event.target.value });
    }

    handleUserChange(event) {
        const key = event.currentTarget.dataset.key;
        const userId = event.detail?.recordId || null;
        if (!userId) {
            this.lookupUserId = null;
            this.updateRow(key, { userId: null, name: '', email: '' });
            return;
        }
        this.updateRow(key, { userId, name: '', email: '' });
        this.lookupUserId = userId;
    }

    updateRow(key, changes) {
        this.rows = this.rows.map((row) => (row.key === key ? this.shapeRow({ ...row, ...changes }) : row));
        this.errorMessage = '';
    }

    get saveDisabled() {
        if (this.saving) {
            return true;
        }
        return !this.rows.some((row) => {
            const name = (row.name || '').trim();
            const email = (row.email || '').trim();
            return Boolean(name || email || row.userId);
        });
    }

    handleCancel() {
        if (!this.saving) {
            this.close();
        }
    }

    async handleSave() {
        if (this.saving) {
            return;
        }
        this.saving = true;
        const kept = [];
        const emails = new Set();
        for (const row of this.rows) {
            let name = (row.name || '').trim();
            let email = (row.email || '').trim();
            let userId = row.userId || null;
            if (!row.participantType || (!name && !email && !userId)) {
                continue;
            }
            if (row.participantType === 'user') {
                if (!userId) {
                    this.saving = false;
                    this.errorMessage = 'Select a Salesforce user.';
                    return;
                }
                if (!name || !email) {
                    try {
                        const user = await getSalesforceUser({ userId });
                        name = (user?.Name || name || '').trim();
                        email = (user?.Email || email || '').trim();
                    } catch (e) {
                        name = name || '';
                        email = email || '';
                    }
                }
            } else {
                userId = null;
                if (!name || !email) {
                    this.saving = false;
                    this.errorMessage = 'Enter a name and email. This person is not a Salesforce user.';
                    return;
                }
            }
            if (email && !EMAIL_PATTERN.test(email)) {
                this.saving = false;
                this.errorMessage = 'Enter a valid email address.';
                return;
            }
            const duplicateKey = email ? email.toLowerCase() : userId;
            if (duplicateKey && emails.has(duplicateKey)) {
                this.saving = false;
                this.errorMessage = 'Each email can be added only once.';
                return;
            }
            if (duplicateKey) {
                emails.add(duplicateKey);
            }
            kept.push({ userId, name, email });
        }
        this.close(JSON.stringify(kept));
    }
}