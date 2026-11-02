import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord, getRecordNotifyChange, updateRecord } from 'lightning/uiRecordApi';

const CASE_FIELDS = ['Case.EmailType__c'];

export default class CaseEmailTypeSaver extends LightningElement {
    @api recordId;
    selectedValue;
    isSaving = false;

    // Fixed 3 options per your requirement
    get options() {
        return [
            { label: 'SOA', value: 'SOA' },
            { label: 'COA Project', value: 'COA Project' },
            { label: 'COA Turns', value: 'COA Turns' }
        ];
    }

    // Load current Case.EmailType__c so the combobox shows the existing value
    @wire(getRecord, { recordId: '$recordId', fields: CASE_FIELDS })
    wiredCase({ data, error }) {
        if (data) {
            this.selectedValue = data.fields.EmailType__c?.value ?? null;
        } else if (error) {
            this.toast('Error loading Case', this.normalizeError(error), 'error');
        }
    }

    // Auto-save on change
    async handleChange(event) {
        const newValue = event.detail.value;

        // If same value selected, skip unnecessary save
        if (newValue === this.selectedValue) return;

        this.isSaving = true;
        try {
            await updateRecord({
                fields: {
                    Id: this.recordId,
                    EmailType__c: newValue
                }
            });

            this.selectedValue = newValue;

            // Notify LDS and refresh the page (hard refresh for your requirement)
            getRecordNotifyChange([{ recordId: this.recordId }]);

            this.toast('Success', 'Email Type updated', 'success');

            // Full page refresh after a brief delay so toast is visible
            setTimeout(() => {
                // In Lightning Experience this will refresh the record page
                // If you prefer NOT to hard-reload, comment this line out.
                window.location.reload();
            }, 350);
        } catch (e) {
            this.toast('Save failed', this.normalizeError(e), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    normalizeError(error) {
        if (Array.isArray(error?.body)) return error.body.map(e => e.message).join(', ');
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return 'Unknown error';
    }
}