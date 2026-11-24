/**
 * @description GW-259: PMI inspection checklist for one Product Serviced line.
 * @see WoDebriefPmiInspectionController
 */
import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import loadInspection from '@salesforce/apex/WoDebriefPmiInspectionController.loadInspection';
import saveInspection from '@salesforce/apex/WoDebriefPmiInspectionController.saveInspection';

/**
 * @description Pass or Failed for a reading. Matches the Apex rule.
 * @param {string} measurementValue Value entered by the user
 * @param {string} referenceValue Reference or default value
 * @param {string} minimumValue Minimum bound
 * @param {string} maximumValue Maximum bound
 * @return {string} Pass, Failed, or blank when the value is blank
 */
function evaluateStatus(measurementValue, referenceValue, minimumValue, maximumValue) {
	const value = measurementValue == null ? '' : String(measurementValue).trim();
	if (!value) {
		return '';
	}
	const hasMin = String(minimumValue ?? '').trim() !== '';
	const hasMax = String(maximumValue ?? '').trim() !== '';
	if (!hasMin && !hasMax) {
		return sameReading(value, referenceValue) ? 'Pass' : 'Failed';
	}
	const entered = parseDecimal(value);
	if (entered == null) {
		return 'Failed';
	}
	if (hasMin) {
		const minBound = parseDecimal(minimumValue);
		if (minBound == null || entered < minBound) {
			return 'Failed';
		}
	}
	if (hasMax) {
		const maxBound = parseDecimal(maximumValue);
		if (maxBound == null || entered > maxBound) {
			return 'Failed';
		}
	}
	return 'Pass';
}

/**
 * @description True when both readings are the same number, or the same text.
 * @param {string} entered Value entered by the user
 * @param {string} reference Reference or default value
 * @return {boolean}
 */
function sameReading(entered, reference) {
	const expected = reference == null ? '' : String(reference).trim();
	const enteredNumber = parseDecimal(entered);
	const expectedNumber = parseDecimal(expected);
	if (enteredNumber != null && expectedNumber != null) {
		return enteredNumber === expectedNumber;
	}
	return entered === expected;
}

/**
 * @description Parses a reading. Blank and non-numeric text return null.
 * @param {string} value Reading text
 * @return {number|null}
 */
function parseDecimal(value) {
	if (value == null || String(value).trim() === '') {
		return null;
	}
	const number = Number(String(value).trim());
	return Number.isFinite(number) ? number : null;
}

/**
 * @description Inspection checklist modal.
 */
export default class WoDebriefPmiInspection extends LightningElement {
	isOpen = false;
	isLoading = false;
	isSaving = false;
	workOrderClosed = false;
	hasStandards = false;
	emptyMessage = '';
	errorMessage = '';
	rows = [];
	workOrderLineItemId;

	/**
	 * @description Opens the checklist for a saved Product Serviced line.
	 * @param {string} workOrderLineItemId Line Id
	 */
	@api
	open(workOrderLineItemId) {
		this.workOrderLineItemId = workOrderLineItemId;
		this.isOpen = true;
		this.errorMessage = '';
		this.rows = [];
		this.emptyMessage = '';
		this.hasStandards = false;
		this.workOrderClosed = false;
		this._load();
	}

	/**
	 * @description True when the user can add a manual measurement.
	 * @return {boolean}
	 */
	get canAddRow() {
		return this.isOpen && !this.isLoading && !this.workOrderClosed;
	}

	/**
	 * @description True when Save is available.
	 * @return {boolean}
	 */
	get canSave() {
		return this.isOpen && !this.isLoading && !this.isSaving && !this.workOrderClosed && this.rows.length > 0;
	}

	/**
	 * @description Loads Device Standards and any PMI measurements already saved.
	 */
	async _load() {
		this.isLoading = true;
		try {
			const context = await loadInspection({ workOrderLineItemId: this.workOrderLineItemId });
			this.workOrderClosed = context?.workOrderClosed === true;
			this.hasStandards = context?.hasStandards === true;
			this.emptyMessage = context?.emptyMessage || '';
			this.rows = (context?.rows || []).map((row, index) => this._fromServer(row, index));
		} catch (error) {
			this.errorMessage = this._errorMessage(error);
		} finally {
			this.isLoading = false;
		}
	}

	/**
	 * @description Copies a server row into the form shape.
	 * @param {Object} row Server row
	 * @param {number} index Row index
	 * @return {Object}
	 */
	_fromServer(row, index) {
		const manual = row?.manual === true;
		return this._withStatus({
			key: row?.standardId || row?.measurementId || `row-${index}`,
			index,
			standardId: row?.standardId || null,
			measurementId: row?.measurementId || null,
			measurementName: row?.measurementName || '',
			referenceValue: row?.referenceValue || '',
			minimumValue: row?.minimumValue || '',
			maximumValue: row?.maximumValue || '',
			measurementValue: row?.measurementValue || '',
			comments: row?.comments || '',
			manual,
			nameReadOnly: !manual,
			referenceReadOnly: !manual,
			boundsReadOnly: !manual
		});
	}

	/**
	 * @description Adds the live Pass or Failed indicator.
	 * @param {Object} row Form row
	 * @return {Object}
	 */
	_withStatus(row) {
		const status = evaluateStatus(
			row.measurementValue,
			row.referenceValue,
			row.minimumValue,
			row.maximumValue
		);
		return {
			...row,
			status,
			isPass: status === 'Pass',
			isFail: status === 'Failed',
			showStatus: status === 'Pass' || status === 'Failed'
		};
	}

	/**
	 * @description Reindexes rows after an edit or an added row.
	 * @param {Object[]} rows Form rows
	 * @return {Object[]}
	 */
	_indexRows(rows) {
		return rows.map((row, index) => this._withStatus({ ...row, index }));
	}

	/**
	 * @description Writes one field and refreshes Pass or Failed.
	 * @param {CustomEvent} event Input change
	 */
	handleFieldChange(event) {
		const index = Number(event.target.dataset.index);
		const field = event.target.dataset.field;
		this.rows = this.rows.map((row) => {
			if (row.index !== index) {
				return row;
			}
			return this._withStatus({ ...row, [field]: event.target.value });
		});
	}

	/**
	 * @description Adds a blank manual measurement.
	 */
	handleAddRow() {
		const key = `manual-${Date.now()}`;
		this.rows = this._indexRows([
			...this.rows,
			{
				key,
				standardId: null,
				measurementId: null,
				measurementName: '',
				referenceValue: '',
				minimumValue: '',
				maximumValue: '',
				measurementValue: '',
				comments: '',
				manual: true,
				nameReadOnly: false,
				referenceReadOnly: false,
				boundsReadOnly: false
			}
		]);
	}

	/**
	 * @description Saves the checklist and tells the debrief when the outcome changes.
	 */
	async handleSave() {
		if (!this.canSave) {
			return;
		}
		this.isSaving = true;
		this.errorMessage = '';
		try {
			const result = await saveInspection({
				workOrderLineItemId: this.workOrderLineItemId,
				rows: this.rows.map((row) => ({
					measurementId: row.measurementId,
					standardId: row.standardId,
					measurementName: row.measurementName,
					referenceValue: row.referenceValue,
					minimumValue: row.minimumValue,
					maximumValue: row.maximumValue,
					measurementValue: row.measurementValue,
					comments: row.comments
				}))
			});
			this.dispatchEvent(new CustomEvent('inspectionsaved', {
				detail: {
					workOrderLineItemId: this.workOrderLineItemId,
					inspectionOutcome: result?.inspectionOutcome || '',
					outcomeUpdated: result?.outcomeUpdated === true,
					checklistComplete: result?.checklistComplete === true
				}
			}));
			this.dispatchEvent(new ShowToastEvent({
				title: 'Inspection saved',
				message: result?.hasFailure
					? 'A reading failed. Inspection Outcome is Performance Standard Not Met (P1).'
					: 'Inspection measurements were saved.',
				variant: result?.hasFailure ? 'warning' : 'success'
			}));
			this.isOpen = false;
		} catch (error) {
			this.errorMessage = this._errorMessage(error);
		} finally {
			this.isSaving = false;
		}
	}

	/**
	 * @description Closes the popup without saving.
	 */
	handleClose() {
		this.isOpen = false;
	}

	/**
	 * @description User-visible message from an Apex error.
	 * @param {Object} error Caught error
	 * @return {string}
	 */
	_errorMessage(error) {
		return error?.body?.message || error?.message || 'The inspection could not be saved.';
	}
}