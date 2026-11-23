// Paste a list of Category / Service Codes. Step 1: paste. Step 2: check (one Apex query) and add the valid ones.
// Closes with [{ productId, code, name }] for the codes to add, or undefined when cancelled.
import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import resolveCodes from '@salesforce/apex/PricingProgramController.resolveCodes';

const RESULT = {
    ok: { label: 'Will be added', cls: 'res ok' },
    dup: { label: 'Already on program', cls: 'res dup' },
    wrong: { label: 'Wrong category', cls: 'res bad' },
    missing: { label: 'No product with this code', cls: 'res bad' }
};

export default class PricingProgramPaste extends LightningModal {
    @api programType;
    @api codesLabel = 'Codes';
    @api existingProductIds = [];

    text = '';
    results = null;
    checking = false;
    error = '';

    get onInput() {
        return !this.results;
    }

    get heading() {
        return `Paste ${this.codesLabel}`;
    }

    handleText(event) {
        this.text = event.detail.value || '';
        this.error = '';
    }

    async handleCheck() {
        const codes = this.text.split(/[\s,;]+/).map((c) => c.trim()).filter(Boolean);
        if (!codes.length) {
            this.error = 'Paste at least one code.';
            return;
        }
        this.checking = true;
        try {
            const found = await resolveCodes({ codes, programType: this.programType });
            const have = new Set(this.existingProductIds || []);
            this.results = (found || []).map((r, i) => {
                const status = r.status === 'ok' && have.has(r.productId) ? 'dup' : r.status;
                return {
                    key: `${i}-${r.code}`,
                    code: r.code,
                    name: r.name || '—',
                    productId: r.productId,
                    status,
                    label: RESULT[status].label,
                    cls: RESULT[status].cls
                };
            });
        } catch (e) {
            this.error = (e && e.body && e.body.message) || 'The codes could not be checked.';
        } finally {
            this.checking = false;
        }
    }

    get addCount() {
        return this.results ? this.results.filter((r) => r.status === 'ok').length : 0;
    }

    get dupCount() {
        return this.results ? this.results.filter((r) => r.status === 'dup').length : 0;
    }

    get badCount() {
        return this.results ? this.results.filter((r) => r.status === 'wrong' || r.status === 'missing').length : 0;
    }

    get addLabel() {
        return `Add ${this.addCount} Code${this.addCount === 1 ? '' : 's'}`;
    }

    get addDisabled() {
        return this.addCount === 0;
    }

    handleBack() {
        this.results = null;
    }

    handleCancel() {
        this.close();
    }

    handleAdd() {
        this.close(this.results.filter((r) => r.status === 'ok').map((r) => ({ productId: r.productId, code: r.code, name: r.name })));
    }
}