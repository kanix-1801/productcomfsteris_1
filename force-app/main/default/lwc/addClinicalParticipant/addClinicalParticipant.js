import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import AddClinicalParticipantModal from 'c/addClinicalParticipantModal';

export default class AddClinicalParticipant extends LightningElement {
    @api participantsJson = '';
    summary = 'No clinical participants added.';

    connectedCallback() {
        this.refreshSummary();
    }

    async openPopup() {
        const result = await AddClinicalParticipantModal.open({
            size: 'small',
            label: 'Add Clinical Participant',
            description: 'Add one or more clinical participants',
            participantsJson: this.participantsJson
        });
        if (result === undefined) {
            return;
        }
        this.participantsJson = result;
        this.refreshSummary();
        this.dispatchEvent(new FlowAttributeChangeEvent('participantsJson', this.participantsJson));
    }

    refreshSummary() {
        let rows = [];
        try {
            rows = this.participantsJson ? JSON.parse(this.participantsJson) : [];
        } catch (e) {
            rows = [];
        }
        if (!Array.isArray(rows) || rows.length === 0) {
            this.summary = 'No clinical participants added.';
            return;
        }
        const labels = rows
            .map((row) => {
                if (row.name && row.email) {
                    return `${row.name} (${row.email})`;
                }
                return row.name || row.email;
            })
            .filter((label) => label);
        this.summary = `${rows.length} added: ${labels.join(', ')}`;
    }
}