/**
 * @description GW-6193 - IMS site visit summary review on the parent Work Order.
 *              Tab 1: rollups + photo selection. Tab 2: covered (read-only).
 *              Tab 3: billable coverage overrides. Review and Approve marks the summary done.
 * @author Uptima Development Team
 */
import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import LightningAlert from 'lightning/alert';
import getSummaryAccess from '@salesforce/apex/WoDebriefIMSSummaryController.getSummaryAccess';
import getSiteVisitSummary from '@salesforce/apex/WoDebriefIMSSummaryController.getSiteVisitSummary';
import savePhotoSelection from '@salesforce/apex/WoDebriefIMSSummaryController.savePhotoSelection';
import saveCoverageChanges from '@salesforce/apex/WoDebriefIMSSummaryController.saveCoverageChanges';
import completeSummaryReview from '@salesforce/apex/WoDebriefIMSSummaryController.completeSummaryReview';
import getSummaryPhotoData from '@salesforce/apex/WoDebriefIMSSummaryController.getSummaryPhotoData';

const MAX_PHOTOS_PER_CATEGORY = 8;
const BILLING_OPTIONS = [
	{ label: 'Billable', value: 'Billable' },
	{ label: 'Warranty', value: 'Warranty' },
	{ label: 'Courtesy', value: 'Courtesy' }
];

export default class WoDebriefIMSSummary extends LightningElement {
	_recordId;
	_loadStarted = false;

	@track summary;
	@track selectedPhotoIds = {};
	@track billingEdits = {};
	@track photoPreviewByVersionId = {};

	isLoading = true;
	isSaving = false;
	isOffline = !navigator.onLine;
	accessAllowed = false;
	blockMessage = '';
	errorMessage = '';
	activeTab = 'summary';

	/**
	 * @description Screen actions set recordId after connectedCallback. Load once it arrives.
	 */
	@api
	get recordId() {
		return this._recordId;
	}
	set recordId(value) {
		this._recordId = value;
		if (value && !this._loadStarted) {
			this._loadStarted = true;
			this._load();
		}
	}

	connectedCallback() {
		this._onOnline = () => {
			this.isOffline = false;
		};
		this._onOffline = () => {
			this.isOffline = true;
		};
		window.addEventListener('online', this._onOnline);
		window.addEventListener('offline', this._onOffline);
		// Desktop/mobile Screen Actions often set recordId after connectedCallback.
		if (this._recordId && !this._loadStarted) {
			this._loadStarted = true;
			this._load();
		}
	}

	disconnectedCallback() {
		window.removeEventListener('online', this._onOnline);
		window.removeEventListener('offline', this._onOffline);
	}

	get showContent() {
		return !this.isLoading && this.accessAllowed && !this.errorMessage;
	}

	get showBlocked() {
		return !this.isLoading && !this.accessAllowed && !!this.blockMessage;
	}

	get workOrderNumber() {
		return this.summary?.header?.workOrderNumber || '';
	}

	get accountName() {
		return this.summary?.header?.accountName || '—';
	}

	get serviceDateLabel() {
		return this._formatDate(this.summary?.header?.serviceDate);
	}

	get nextServiceDateLabel() {
		return this._formatDate(this.summary?.header?.nextServiceDate);
	}

	get traysServiced() {
		return this.summary?.header?.traysServiced ?? 0;
	}

	get instrumentsBeyondRepair() {
		return this.summary?.header?.instrumentsBeyondRepair ?? 0;
	}

	get instrumentsOffSite() {
		return this.summary?.header?.instrumentsOffSite ?? 0;
	}

	get returnOrderLabel() {
		return this.summary?.header?.returnOrderNumber || null;
	}

	get childAssets() {
		return this.summary?.childAssets || [];
	}

	get photoCategories() {
		const photos = this.summary?.photos || [];
		const byCategory = {};
		for (const photo of photos) {
			const category = photo.category || 'Uncategorized';
			if (!byCategory[category]) {
				byCategory[category] = [];
			}
			const selected = !!this.selectedPhotoIds[photo.contentVersionId];
			byCategory[category].push({
				...photo,
				selected,
				cardClass: selected ? 'photo-card photo-card_selected' : 'photo-card',
				previewUrl: this.photoPreviewByVersionId[photo.contentVersionId] || null,
				metaLabel: [photo.beforeAfter, photo.lineLabel, photo.assetName]
					.filter(Boolean)
					.join(' · ')
			});
		}
		return Object.keys(byCategory)
			.sort()
			.map(category => {
				const items = byCategory[category];
				const selectedCount = items.filter(item => item.selected).length;
				return {
					category,
					items,
					selectedCount,
					limitLabel: `${selectedCount} / ${MAX_PHOTOS_PER_CATEGORY} selected`
				};
			});
	}

	get coveredGroups() {
		return (this.summary?.coveredGroups || []).map(group => ({
			...group,
			title: this._assetTitle(group),
			lines: (group.lines || []).map(line => ({
				...line,
				quantityLabel: line.quantity == null ? '—' : String(line.quantity)
			}))
		}));
	}

	get billableGroups() {
		return (this.summary?.billableGroups || []).map(group => ({
			...group,
			title: this._assetTitle(group),
			lines: (group.lines || []).map(line => {
				const billingType = this.billingEdits[line.lineId] || line.billingType || 'Billable';
				const display = this._pricedLine(line, billingType);
				return {
					...line,
					billingType,
					billingOptions: BILLING_OPTIONS,
					quantityLabel: line.quantity == null ? '—' : String(line.quantity),
					unitPriceLabel: this._formatMoney(display.unitPrice),
					totalPriceLabel: this._formatMoney(display.totalPrice),
					rowClass: display.priceIsZero ? 'line-row line-row_zero' : 'line-row'
				};
			})
		}));
	}

	get billableGrandTotalLabel() {
		let total = 0;
		for (const group of this.summary?.billableGroups || []) {
			for (const line of group.lines || []) {
				const billingType = this.billingEdits[line.lineId] || line.billingType || 'Billable';
				total += this._pricedLine(line, billingType).totalPrice || 0;
			}
		}
		return this._formatMoney(total);
	}

	get isSummaryTab() {
		return this.activeTab === 'summary';
	}

	get isCoveredTab() {
		return this.activeTab === 'covered';
	}

	get isBillableTab() {
		return this.activeTab === 'billable';
	}

	get summaryTabClass() {
		return this._tabClass('summary');
	}

	get coveredTabClass() {
		return this._tabClass('covered');
	}

	get billableTabClass() {
		return this._tabClass('billable');
	}

	get disableActions() {
		return this.isSaving || this.isOffline || this.summary?.header?.summaryReviewDone;
	}

	get approveLabel() {
		return this.summary?.header?.summaryReviewDone
			? 'Summary Approved'
			: 'Review and Approve';
	}

	handleTabClick(event) {
		this.activeTab = event.currentTarget.dataset.tab;
	}

	handlePhotoToggle(event) {
		const versionId = event.currentTarget.dataset.versionId;
		const category = event.currentTarget.dataset.category;
		if (!versionId || this.disableActions) {
			return;
		}
		const next = { ...this.selectedPhotoIds };
		if (next[versionId]) {
			delete next[versionId];
		} else {
			const selectedInCategory = (this.summary?.photos || []).filter(
				photo =>
					(photo.category || 'Uncategorized') === category && next[photo.contentVersionId]
			).length;
			if (selectedInCategory >= MAX_PHOTOS_PER_CATEGORY) {
				this._toast(
					`Select no more than ${MAX_PHOTOS_PER_CATEGORY} photos in ${category}.`,
					'error'
				);
				return;
			}
			next[versionId] = true;
			this._ensurePhotoPreview(versionId);
		}
		this.selectedPhotoIds = next;
	}

	handleBillingChange(event) {
		const lineId = event.target.dataset.lineId;
		const billingType = event.detail.value;
		if (!lineId) {
			return;
		}
		this.billingEdits = {
			...this.billingEdits,
			[lineId]: billingType
		};
	}

	async handleSavePhotos() {
		if (this.disableActions) {
			return;
		}
		this.isSaving = true;
		try {
			await savePhotoSelection({
				workOrderId: this.recordId,
				selectedContentVersionIds: Object.keys(this.selectedPhotoIds)
			});
			this._toast('Photo selection saved.', 'success');
			await this._loadSummaryOnly();
		} catch (error) {
			this._toast(this._errorMessage(error), 'error');
		} finally {
			this.isSaving = false;
		}
	}

	async handleSaveCoverage() {
		if (this.disableActions) {
			return;
		}
		const changes = Object.keys(this.billingEdits).map(lineId => ({
			lineId,
			billingType: this.billingEdits[lineId]
		}));
		if (!changes.length) {
			this._toast('No coverage changes to save.', 'info');
			return;
		}
		this.isSaving = true;
		try {
			await saveCoverageChanges({
				workOrderId: this.recordId,
				changesJson: JSON.stringify(changes)
			});
			this.billingEdits = {};
			this._toast('Coverage updates saved.', 'success');
			await this._loadSummaryOnly();
		} catch (error) {
			this._toast(this._errorMessage(error), 'error');
		} finally {
			this.isSaving = false;
		}
	}

	async handleApprove() {
		if (this.disableActions) {
			return;
		}
		this.isSaving = true;
		try {
			const selectedIds = Object.keys(this.selectedPhotoIds);
			await savePhotoSelection({
				workOrderId: this.recordId,
				selectedContentVersionIds: selectedIds
			});
			const coverageChanges = Object.keys(this.billingEdits).map(lineId => ({
				lineId,
				billingType: this.billingEdits[lineId]
			}));
			if (coverageChanges.length) {
				await saveCoverageChanges({
					workOrderId: this.recordId,
					changesJson: JSON.stringify(coverageChanges)
				});
				this.billingEdits = {};
			}
			await completeSummaryReview({ workOrderId: this.recordId });
			await LightningAlert.open({
				message: 'Site visit summary approved. You can complete the service appointment and send the report.',
				theme: 'success',
				label: 'Summary Approved'
			});
			this.dispatchEvent(new CloseActionScreenEvent());
		} catch (error) {
			this._toast(this._errorMessage(error), 'error');
		} finally {
			this.isSaving = false;
		}
	}

	handleCancel() {
		this.dispatchEvent(new CloseActionScreenEvent());
	}

	async _load() {
		this.isLoading = true;
		this.errorMessage = '';
		try {
			if (!this._recordId) {
				this.accessAllowed = false;
				this.blockMessage = 'Work order could not be identified. Open this action from a work order record.';
				return;
			}
			const access = await getSummaryAccess({ workOrderId: this._recordId });
			this.accessAllowed = !!access?.allowed;
			this.blockMessage = access?.blockMessage || '';
			if (!this.accessAllowed) {
				return;
			}
			await this._loadSummaryOnly();
		} catch (error) {
			this.errorMessage = this._errorMessage(error);
		} finally {
			this.isLoading = false;
		}
	}

	async _loadSummaryOnly() {
		const summary = await getSiteVisitSummary({ workOrderId: this._recordId });
		this.summary = summary;
		const selected = {};
		for (const photo of summary?.photos || []) {
			if (photo.includeInSummaryReport) {
				selected[photo.contentVersionId] = true;
				this._ensurePhotoPreview(photo.contentVersionId);
			}
		}
		this.selectedPhotoIds = selected;
		this.billingEdits = {};
	}

	async _ensurePhotoPreview(contentVersionId) {
		if (!contentVersionId || this.photoPreviewByVersionId[contentVersionId]) {
			return;
		}
		try {
			const base64 = await getSummaryPhotoData({ contentVersionId });
			if (base64) {
				this.photoPreviewByVersionId = {
					...this.photoPreviewByVersionId,
					[contentVersionId]: `data:image/jpeg;base64,${base64}`
				};
			}
		} catch (error) {
			// Preview is optional; selection still works from metadata.
			console.warn('woDebriefIMSSummary photo preview failed', error);
		}
	}

	_pricedLine(line, billingType) {
		const isZero = billingType === 'Warranty' || billingType === 'Courtesy';
		const quantity = Number(line.quantity || 0);
		const unitPrice = isZero ? 0 : Number(line.unitPrice || 0);
		const totalPrice = isZero
			? 0
			: (line.totalPrice != null && billingType === line.billingType
				? Number(line.totalPrice)
				: unitPrice * quantity);
		return { unitPrice, totalPrice, priceIsZero: isZero };
	}

	_assetTitle(group) {
		const asset = group.assetName || 'Asset';
		const wo = group.workOrderNumber || '';
		return wo ? `${asset} (${wo})` : asset;
	}

	_tabClass(tab) {
		return this.activeTab === tab ? 'tab-link tab-link_active' : 'tab-link';
	}

	_formatDate(value) {
		if (!value) {
			return '—';
		}
		try {
			return new Intl.DateTimeFormat(undefined, {
				year: 'numeric',
				month: 'short',
				day: 'numeric'
			}).format(new Date(value));
		} catch (error) {
			return String(value);
		}
	}

	_formatMoney(value) {
		const amount = Number(value || 0);
		return new Intl.NumberFormat(undefined, {
			style: 'currency',
			currency: 'USD'
		}).format(amount);
	}

	_errorMessage(error) {
		return error?.body?.message || error?.message || 'Something went wrong.';
	}

	_toast(message, variant) {
		this.dispatchEvent(
			new ShowToastEvent({
				title: variant === 'error' ? 'Error' : 'Site Visit Summary',
				message,
				variant
			})
		);
	}
}