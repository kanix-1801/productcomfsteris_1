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

    async handleUserChange(event) {
        const key = event.target.dataset.key;
        const userId = event.detail.recordId;
        if (!userId) {
            this.updateRow(key, { userId: null, name: '', email: '' });
            return;
        }
        this.updateRow(key, { userId });
        try {
            const user = await getSalesforceUser({ userId });
            if (user) {
                this.updateRow(key, { name: user.Name || '', email: user.Email || '' });
            }
        } catch (e) {
            this.errorMessage = 'The Salesforce user could not be loaded. Select the user again.';
        }
    }

    updateRow(key, changes) {
        this.rows = this.rows.map((row) => (row.key === key ? this.shapeRow({ ...row, ...changes }) : row));
        this.errorMessage = '';
    }

    get saveDisabled() {
        return !this.rows.some((row) => {
            const name = (row.name || '').trim();
            const email = (row.email || '').trim();
            return Boolean(name || email || row.userId);
        });
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
            let userId = row.userId || null;
            if (!row.participantType || (!name && !email && !userId)) {
                continue;
            }
            if (row.participantType === 'user') {
                if (!userId) {
                    this.errorMessage = 'Select a Salesforce user.';
                    return;
                }
                if (!name || !email) {
                    this.errorMessage = 'The selected Salesforce user needs a name and email.';
                    return;
                }
            } else {
                userId = null;
                if (!name || !email) {
                    this.errorMessage = 'Enter a name and email. This person is not a Salesforce user.';
                    return;
                }
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