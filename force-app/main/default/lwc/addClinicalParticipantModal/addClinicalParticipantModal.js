import { api, track } from 'lwc';
import LightningModal from 'lightning/modal';
import getSalesforceUser from '@salesforce/apex/ClinicalParticipantService.getSalesforceUser';

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export default class AddClinicalParticipantModal extends LightningModal {
    @api participantsJson;
    @track rows = [];
    errorMessage = '';

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
            return parsed.map((row) => ({
                key: this.newKey(),
                userId: row.userId || null,
                name: row.name || '',
                email: row.email || ''
            }));
        } catch (e) {
            return [];
        }
    }

    emptyRow() {
        return { key: this.newKey(), userId: null, name: '', email: '' };
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

    handleNameChange(event) {
        this.updateRow(event.target.dataset.key, { name: event.target.value });
    }

    handleEmailChange(event) {
        this.updateRow(event.target.dataset.key, { email: event.target.value });
    }

    async handleUserChange(event) {
        const key = event.target.dataset.key;
        const userId = event.detail.recordId;
        this.updateRow(key, { userId: userId || null });
        if (!userId) {
            return;
        }
        try {
            const user = await getSalesforceUser({ userId });
            if (user) {
                this.updateRow(key, { name: user.Name || '', email: user.Email || '' });
            }
        } catch (e) {
            this.errorMessage = 'The Salesforce user could not be loaded. Enter the name and email.';
        }
    }

    updateRow(key, changes) {
        this.rows = this.rows.map((row) => (row.key === key ? { ...row, ...changes } : row));
        this.errorMessage = '';
    }

    handleCancel() {
        this.close();
    }

    handleSave() {
        const kept = [];
        const emails = new Set();
        for (const row of this.rows) {
            const name = (row.name || '').trim();
            const email = (row.email || '').trim();
            const userId = row.userId || null;
            if (!name && !email && !userId) {
                continue;
            }
            if (!name || !email) {
                this.errorMessage = 'Enter a name and email, or select a Salesforce user.';
                return;
            }
            if (!EMAIL_PATTERN.test(email)) {
                this.errorMessage = 'Enter a valid email address.';
                return;
            }
            if (emails.has(email.toLowerCase())) {
                this.errorMessage = 'Each email can be added only once.';
                return;
            }
            emails.add(email.toLowerCase());
            kept.push({ userId, name, email });
        }
        this.close(JSON.stringify(kept));
    }
}