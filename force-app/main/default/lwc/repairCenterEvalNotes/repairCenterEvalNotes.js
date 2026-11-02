import { LightningElement, api } from 'lwc';

/**
 * GW-3400 - Shared evaluation notes textareas.
 */
export default class RepairCenterEvalNotes extends LightningElement {
    @api evaluationNotes;
    @api internalEvaluationNotes;
    @api internalSpecialistEvaluationNotes;
    /** GW-5453 - Quality Technician notes; always read-only on evaluation screens. */
    @api qcInspectionNotes;
    @api disabled = false;

    renderedCallback() {
        if (this.matchQcNotesHeight() || this._qcHeightFrame) {
            return;
        }
        this._qcHeightFrame = requestAnimationFrame(() => {
            this._qcHeightFrame = null;
            this.matchQcNotesHeight();
        });
    }

    /**
     * GW-5453 - Copies a sibling notes field's height onto the read-only QC box.
     * The box still grows past that minimum when the note is longer.
     * @return {Boolean} True when a non-zero height was applied
     */
    matchQcNotesHeight() {
        const reference = this.template.querySelector('lightning-textarea');
        const qcNotesEl = this.template.querySelector('[data-qc-notes]');
        if (!reference || !qcNotesEl) {
            return false;
        }
        const targetHeight = Math.round(reference.getBoundingClientRect().height);
        if (!targetHeight) {
            return false;
        }
        const nextHeight = `${targetHeight}px`;
        if (qcNotesEl.style.minHeight !== nextHeight) {
            qcNotesEl.style.minHeight = nextHeight;
        }
        return true;
    }

    /**
     * GW-3400 - Forwards Evaluation Notes changes to the host.
     * @param {Event} event textarea change
     */
    handleEvaluationNotesChange(event) {
        this.emitNotesChange('evaluationNotes', event.target.value);
    }

    /**
     * GW-3400 - Forwards Internal Evaluation Notes changes to the host.
     * @param {Event} event textarea change
     */
    handleInternalNotesChange(event) {
        this.emitNotesChange('internalEvaluationNotes', event.target.value);
    }

    /**
     * GW-3400 - Forwards Internal Specialist Evaluation Notes changes to the host.
     * @param {Event} event textarea change
     */
    handleSpecialistNotesChange(event) {
        this.emitNotesChange('internalSpecialistEvaluationNotes', event.target.value);
    }

    /**
     * @description Returns current textarea values for hosts that save while a field still has focus.
     * @return {Object} Notes field map
     */
    @api
    getDraftNotes() {
        const notes = {};
        this.template.querySelectorAll('lightning-textarea[data-note-field]').forEach((fieldEl) => {
            const key = fieldEl.dataset.noteField;
            if (key) {
                notes[key] = fieldEl.value;
            }
        });
        return notes;
    }

    emitNotesChange(field, value) {
        this.dispatchEvent(
            new CustomEvent('noteschange', {
                detail: { field, value }
            })
        );
    }
}