import { LightningElement, api } from 'lwc';

const COLUMN_ONE = [
    {
        field: 'isInsertionTubeChannelDistalEnd',
        label: 'Insertion Tube Channel / Distal End'
    },
    { field: 'isElevatorIrrigationChannel', label: 'Elevator / Irrigation Channel' },
    { field: 'isAuxiliaryWaterPort', label: 'Auxiliary Water Port' },
    { field: 'isBiopsyPort', label: 'Biopsy Port' },
    { field: 'isAirWaterPort', label: 'Air / Water Port' },
    { field: 'isSuctionPort', label: 'Suction Port' },
    { field: 'isLightGuideTubes', label: 'Light Guide Tubes' },
    { field: 'isAirWaterConnectors', label: 'Air / Water Connectors' },
    { field: 'isEyePiece', label: 'Eye Piece' }
];

const COLUMN_TWO = [
    { field: 'isShaft', label: 'Shaft' },
    { field: 'isPowerCord', label: 'Power Cord' },
    { field: 'isInstrument', label: 'Instrument' },
    { field: 'isLockingMechanism', label: 'Locking Mechanism' },
    { field: 'isFootPedal', label: 'Foot Pedal' },
    { field: 'isOphthalmic', label: 'Ophthalmic' }
];

/**
 * GW-5883 editable Contamination Information section.
 * Visible only when the parent sets visible (Sub Status = Contaminated).
 */
export default class ContaminationInformation extends LightningElement {
    @api visible = false;
    @api disabled = false;
    @api value;

    get columnOneFields() {
        return this.toCheckboxRows(COLUMN_ONE);
    }

    get columnTwoFields() {
        return this.toCheckboxRows(COLUMN_TWO);
    }

    get otherValue() {
        return this.value?.contaminationOther || '';
    }

    toCheckboxRows(definitions) {
        return definitions.map((item) => {
            const checked = this.value?.[item.field] === true;
            return {
                ...item,
                checked,
                // Stable key — do not include checked or remounting clears the click state.
                rowKey: item.field
            };
        });
    }

    handleCheckboxChange(event) {
        const field = event.target?.dataset?.field;
        if (!field) {
            return;
        }
        const checked =
            event.detail && Object.prototype.hasOwnProperty.call(event.detail, 'checked')
                ? event.detail.checked === true
                : event.target.checked === true;
        this.emitChange(field, checked);
    }

    handleOtherChange(event) {
        this.emitChange('contaminationOther', event.target.value || '');
    }

    emitChange(field, value) {
        this.dispatchEvent(
            new CustomEvent('contaminationchange', {
                detail: { field, value }
            })
        );
    }
}