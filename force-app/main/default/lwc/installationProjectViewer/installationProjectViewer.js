import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getProjectItems from '@salesforce/apex/InstallationProjectViewerController.getProjectItems';
import getStatusPicklistOptions from '@salesforce/apex/InstallationProjectViewerController.getStatusPicklistOptions';
import updateProjectItem from '@salesforce/apex/InstallationProjectViewerController.updateProjectItem';
import createProjectSubline from '@salesforce/apex/InstallationProjectViewerController.createProjectSubline';
import insertProjectRootLineAfterAndShift from '@salesforce/apex/InstallationProjectViewerController.insertProjectRootLineAfterAndShift';
import insertNewFirstRootLineAndShift from '@salesforce/apex/InstallationProjectViewerController.insertNewFirstRootLineAndShift';
import isReadOnlyInstallationProjectViewer from '@salesforce/apex/InstallationProjectViewerController.isReadOnlyInstallationProjectViewer';
import massCancelProjectItems from '@salesforce/apex/InstallationProjectViewerController.massCancelProjectItems';
import massUpdateProjectItemOwner from '@salesforce/apex/InstallationProjectViewerController.massUpdateProjectItemOwner';

function normalizeSequenceKey(seq) {
	if (seq === null || seq === undefined) {
		return '';
	}
	return String(seq).trim();
}

function parentSequenceKey(seq) {
	const s = normalizeSequenceKey(seq);
	if (!s) {
		return null;
	}
	const parts = s.split('.');
	if (parts.length <= 1) {
		return null;
	}
	return parts.slice(0, -1).join('.');
}

/** True when this row is root sequence line 1 (including 1.0 canonicalized to 1). */
function isRootLineOne(seq) {
	const root = canonicalRootSequenceKeyForCascadeJs(seq);
	if (!root || parentSequenceKey(root)) {
		return false;
	}
	const first = Number.parseFloat(String(root).split('.')[0]);
	return !Number.isNaN(first) && first === 1;
}

/** Matches Apex canonicalRootSequenceKeyForCascade (N.0 → N) for root actions. */
function canonicalRootSequenceKeyForCascadeJs(seq) {
	const s = normalizeSequenceKey(seq);
	if (!s) {
		return '';
	}
	const parts = s.split('.');
	if (parts.length === 2) {
		const second = Number.parseFloat(parts[1]);
		if (!Number.isNaN(second) && second === 0) {
			return parts[0];
		}
	}
	return s;
}

/** Same hierarchical ordering as Apex (1, 1.1, 1.2, 2, …). */
function compareSequences(seqA, seqB) {
	const blankA = !seqA || String(seqA).trim() === '';
	const blankB = !seqB || String(seqB).trim() === '';
	if (blankA && blankB) {
		return 0;
	}
	if (blankA) {
		return 1;
	}
	if (blankB) {
		return -1;
	}
	const aParts = String(seqA).trim().split('.');
	const bParts = String(seqB).trim().split('.');
	const maxLen = Math.max(aParts.length, bParts.length);
	for (let i = 0; i < maxLen; i++) {
		const aVal = i < aParts.length ? Number.parseFloat(aParts[i]) || 0 : 0;
		const bVal = i < bParts.length ? Number.parseFloat(bParts[i]) || 0 : 0;
		if (aVal > bVal) {
			return 1;
		}
		if (aVal < bVal) {
			return -1;
		}
	}
	return 0;
}

function dueDateToIso(d) {
	if (d === null || d === undefined || d === '') {
		return '';
	}
	if (typeof d === 'string') {
		const m = d.match(/^(\d{4}-\d{2}-\d{2})/);
		if (m) {
			return m[1];
		}
	}
	try {
		const dt = new Date(d);
		if (Number.isNaN(dt.getTime())) {
			return '';
		}
		const y = dt.getUTCFullYear();
		const mo = String(dt.getUTCMonth() + 1).padStart(2, '0');
		const day = String(dt.getUTCDate()).padStart(2, '0');
		return `${y}-${mo}-${day}`;
	} catch (e) {
		return '';
	}
}

/** Picklist label for read-only status display (API value → label). */
function resolvePicklistLabel(value, options) {
	if (value === null || value === undefined || String(value).trim() === '') {
		return '';
	}
	const opts = Array.isArray(options) ? options : [];
	const sid = String(value);
	const match = opts.find((o) => String(o.value) === sid);
	return match ? match.label : sid;
}

/** lightning-record-picker filter: active standard users (profile exclusions enforced on save in Apex). */
function buildAssignableUserFilter() {
	return {
		criteria: [
			{ fieldPath: 'IsActive', operator: 'eq', value: true },
			{ fieldPath: 'UserType', operator: 'eq', value: 'Standard' }
		],
		filterLogic: '1 AND 2'
	};
}

function normalizeSaveError(error) {
	if (!error) {
		return 'Unknown error';
	}
	if (Array.isArray(error.body)) {
		const messages = error.body.map((entry) => entry.message).filter(Boolean);
		if (messages.length) {
			return messages.join(', ');
		}
	}
	const body = error.body;
	if (body) {
		if (typeof body === 'string') {
			return body;
		}
		if (body.output?.errors?.length) {
			const messages = body.output.errors.map((entry) => entry.message).filter(Boolean);
			if (messages.length) {
				return messages.join(', ');
			}
		}
		if (body.pageErrors?.length) {
			const messages = body.pageErrors.map((entry) => entry.message).filter(Boolean);
			if (messages.length) {
				return messages.join(', ');
			}
		}
		if (body.fieldErrors) {
			const messages = [];
			Object.values(body.fieldErrors).forEach((fieldErrorList) => {
				fieldErrorList.forEach((fieldError) => {
					if (fieldError?.message) {
						messages.push(fieldError.message);
					}
				});
			});
			if (messages.length) {
				return messages.join(', ');
			}
		}
		if (body.exceptionMessage) {
			return body.exceptionMessage;
		}
		if (body.message && body.message !== 'Script-thrown exception') {
			return body.message;
		}
	}
	if (error.message && error.message !== 'Script-thrown exception') {
		return error.message;
	}
	return 'Could not save. Please try again or contact your administrator.';
}

/** Matches InstallationProjectViewerController.eventStatusLooksCompleted for client-side hide parity. */
function eventStatusLooksCompletedForUi(status) {
	if (status === null || status === undefined || String(status).trim() === '') {
		return false;
	}
	const t = String(status).trim().toLowerCase();
	if (t.includes('complete') || t.includes('cancel')) {
		return true;
	}
	if (t === 'done' || t === 'closed' || t === 'completed') {
		return true;
	}
	return false;
}

/** Matches InstallationProjectViewerController.isCancelledStatus. */
function isCancelledStatusForUi(status) {
	return status !== null && status !== undefined && String(status).trim().toLowerCase().includes('cancel');
}

function isPastDueProjectRowForUi(row) {
	if (!row || (row.objectApiName !== 'Event' && row.objectApiName !== 'Task') || row.isCompleted === true) {
		return false;
	}
	const iso = row.dueDateIso || dueDateToIso(row.dueDate);
	if (!iso) {
		return false;
	}
	const due = new Date(`${iso}T00:00:00`);
	if (Number.isNaN(due.getTime())) {
		return false;
	}
	const today = new Date();
	const todayStart = new Date(today.getFullYear(), today.getMonth(), today.getDate());
	return due < todayStart;
}

function augmentRow(r) {
	const showTypeIcon = r.objectApiName === 'Task' || r.objectApiName === 'Event';
	const typeIconName =
		r.objectApiName === 'Task' ? 'standard:task' : r.objectApiName === 'Event' ? 'standard:event' : '';
	let isCompleted = r.isCompleted === true;
	if (r.objectApiName === 'Event') {
		isCompleted = isCompleted || eventStatusLooksCompletedForUi(r.status);
	}
	return {
		...r,
		dueDateFormatted: formatDateStatic(r.dueDate),
		dueDateIso: dueDateToIso(r.dueDate),
		rowKey: `${r.objectApiName}-${r.recordId}`,
		showTypeIcon,
		typeIconName,
		isCompleted
	};
}

function formatDateStatic(value) {
	if (!value) {
		return '';
	}
	try {
		const iso = dueDateToIso(value);
		if (!iso) {
			return String(value);
		}
		const parts = iso.split('-').map(Number);
		if (parts.length !== 3 || parts.some((n) => Number.isNaN(n))) {
			return String(value);
		}
		// Local calendar date so UTC midnight ISO strings do not shift back a day
		// for users west of UTC (the completed-line readonly display).
		return new Intl.DateTimeFormat(undefined, {
			year: 'numeric',
			month: 'short',
			day: 'numeric'
		}).format(new Date(parts[0], parts[1] - 1, parts[2]));
	} catch (e) {
		return String(value);
	}
}

export default class InstallationProjectViewer extends NavigationMixin(LightningElement) {
	@api recordId;

	@track hideCompleted = true;
	@track showPastDueOnly = false;
	/** Group by sequence: nest under parent keys, merge 1.0 into 1, expand/collapse. Off = flat list. */
	@track groupBySequence = true;

	allRows = [];
	sourceRows = [];
	@track displayRows = [];

	error;

	_expandedParents = {};

	_wiredProjectItemsResult;

	taskStatusOptions = [];
	eventStatusOptions = [];

	@track savingRecordId = null;
	@track lineActionPending = false;

	/** True when user has the Read Installation Projects permission set (direct or via group). */
	@track isReadOnlyViewer = false;

	/** False until read-only access has been resolved (avoids flashing editable controls). */
	@track readOnlyAccessResolved = false;

	_readOnlyAccessPromise;

	/** rowKey → true for rows checked for mass actions. */
	@track selectedKeys = {};

	bulkOwnerId;

	get apexErrorMessage() {
		if (!this.error) {
			return '';
		}
		const body = this.error.body;
		if (body) {
			if (Array.isArray(body)) {
				return body.map((e) => e.message).join(', ');
			}
			if (body.message) {
				return body.message;
			}
		}
		return this.error.message || 'Unable to load project items.';
	}

	get hasRows() {
		return this.sourceRows && this.sourceRows.length > 0;
	}

	get disableGroupAllButton() {
		return !this.hasRows;
	}

	get hidePastDue() {
		return false;
	}

	/** Always load every row; Hide Completed filters client-side so one cached result stays current after refreshApex. */
	get serverHideCompleted() {
		return false;
	}

	get showMassActions() {
		return this.readOnlyAccessResolved && !this.isReadOnlyViewer && this.hasRows;
	}

	get selectedRows() {
		return (this.sourceRows || []).filter((r) => this.selectedKeys[r.rowKey] === true && this._isSelectableRow(r));
	}

	get selectedCount() {
		return this.selectedRows.length;
	}

	get isMassCancelDisabled() {
		return this.selectedCount === 0 || this.lineActionPending || this.savingRecordId != null;
	}

	get isMassAssignDisabled() {
		return this.isMassCancelDisabled || !this.bulkOwnerId;
	}

	get selectableDisplayRows() {
		return (this.displayRows || []).filter((r) => r.isSelectable);
	}

	get allVisibleSelected() {
		const rows = this.selectableDisplayRows;
		return rows.length > 0 && rows.every((r) => this.selectedKeys[r.rowKey] === true);
	}

	get disableSelectAll() {
		return this.selectableDisplayRows.length === 0 || this.lineActionPending;
	}

	_isSelectableRow(row) {
		return Boolean(row && row.recordId && !row.isVirtualGroup && row.isCompleted !== true) && !this.isReadOnlyViewer;
	}

	connectedCallback() {
		this._loadReadOnlyAccess();
	}

	_loadReadOnlyAccess() {
		if (!this._readOnlyAccessPromise) {
			this._readOnlyAccessPromise = isReadOnlyInstallationProjectViewer()
				.then((result) => {
					this.isReadOnlyViewer = result === true;
					return this.isReadOnlyViewer;
				})
				.catch((error) => {
					this.isReadOnlyViewer = false;
					// eslint-disable-next-line no-console
					console.warn('Read-only viewer check failed', error);
					return false;
				})
				.finally(() => {
					this.readOnlyAccessResolved = true;
					if (this.hasRows) {
						this._rebuildDisplayRows();
					}
				});
		}
		return this._readOnlyAccessPromise;
	}

	_applyClientFilters() {
		let rows = Array.isArray(this.allRows) ? [...this.allRows] : [];
		if (this.hideCompleted === true) {
			rows = rows.filter((r) => r.isCompleted !== true);
		}
		if (this.showPastDueOnly === true) {
			rows = rows.filter((r) => isPastDueProjectRowForUi(r));
		}
		this.sourceRows = rows;
		const visibleKeys = new Set(rows.map((r) => r.rowKey));
		const keptSelection = {};
		Object.keys(this.selectedKeys).forEach((k) => {
			if (visibleKeys.has(k)) {
				keptSelection[k] = true;
			}
		});
		this.selectedKeys = keptSelection;
		this._initExpandedForTree();
		this._rebuildDisplayRows();
	}

	@wire(getStatusPicklistOptions, { objectApiName: 'Task' })
	wiredTaskStatusPick({ data }) {
		this.taskStatusOptions = Array.isArray(data) ? data.map((o) => ({ label: o.label, value: o.value })) : [];
		if (this.hasRows && this.readOnlyAccessResolved) {
			this._rebuildDisplayRows();
		}
	}

	@wire(getStatusPicklistOptions, { objectApiName: 'Event' })
	wiredEventStatusPick({ data }) {
		this.eventStatusOptions = Array.isArray(data) ? data.map((o) => ({ label: o.label, value: o.value })) : [];
		if (this.hasRows && this.readOnlyAccessResolved) {
			this._rebuildDisplayRows();
		}
	}

	get assignableUserFilter() {
		return buildAssignableUserFilter();
	}

	get assignableUserMatchingInfo() {
		return {
			primaryField: { fieldPath: 'Name' },
			additionalFields: [{ fieldPath: 'Email' }]
		};
	}

	get assignableUserDisplayInfo() {
		return {
			primaryField: 'Name',
			additionalFields: ['Email']
		};
	}

	@wire(getProjectItems, {
		projectId: '$recordId',
		hideCompleted: '$serverHideCompleted',
		hidePastDue: '$hidePastDue'
	})
	wiredItems(result) {
		this._wiredProjectItemsResult = result;
		const { data, error } = result;
		if (data) {
			this.allRows = data.map((r) => augmentRow(r));
			this._loadReadOnlyAccess().then(() => {
				this._applyClientFilters();
				this.error = undefined;
			});
		} else if (error) {
			this.allRows = [];
			this.sourceRows = [];
			this.displayRows = [];
			this.error = error;
		}
	}

	_collectParentKeysWithChildren(rows) {
		const keys = new Set();
		rows.forEach((r) => {
			let p = parentSequenceKey(r.sequence);
			while (p) {
				keys.add(p);
				p = parentSequenceKey(p);
			}
		});
		return keys;
	}

	/**
	 * Keeps only expand/collapse keys that still exist as parents after refresh; missing = expanded.
	 */
	_initExpandedForTree() {
		const parentSet = this._collectParentKeysWithChildren(this.sourceRows);
		const next = {};
		Object.keys(this._expandedParents).forEach((k) => {
			if (parentSet.has(k)) {
				next[k] = this._expandedParents[k];
			}
		});
		this._expandedParents = next;
	}

	_isParentExpanded(key) {
		return this._expandedParents[key] !== false;
	}

	_upsertTreeNode(byKey, key, rowPayload) {
		const k = normalizeSequenceKey(key);
		if (!k) {
			return null;
		}
		let n = byKey.get(k);
		if (!n) {
			n = { sequenceKey: k, row: rowPayload, children: [] };
			byKey.set(k, n);
			return n;
		}
		if (rowPayload && !rowPayload.isVirtualGroup) {
			n.row = rowPayload;
		}
		return n;
	}

	_virtualGroupRow(sequenceKey) {
		const k = normalizeSequenceKey(sequenceKey);
		return {
			isVirtualGroup: true,
			sequence: k,
			typeLabel: '',
			title: '',
			dueDateFormatted: '',
			assignedToName: '',
			status: '',
			recordId: null,
			objectApiName: null,
			rowKey: `virtual-${k}`,
			showTypeIcon: false,
			typeIconName: '',
			isCompleted: false,
			dueDateIso: ''
		};
	}

	/**
	 * Hoist the real "1.0" row onto the root parent "1" (details + link), remove duplicate "1.0" child.
	 */
	_mergeDotZeroIntoRootParents(byKey) {
		const rootKeys = [...byKey.keys()].filter((k) => k && !String(k).includes('.'));
		rootKeys.forEach((rootKey) => {
			const dzKey = `${rootKey}.0`;
			if (!byKey.has(dzKey)) {
				return;
			}
			const parentNode = byKey.get(rootKey);
			const dotZeroNode = byKey.get(dzKey);
			if (!parentNode || !dotZeroNode || dotZeroNode.row.isVirtualGroup) {
				return;
			}
			parentNode.row = {
				...dotZeroNode.row,
				sequence: rootKey,
				isVirtualGroup: false
			};
			parentNode.children = (parentNode.children || []).filter((c) => c.sequenceKey !== dzKey);
			byKey.delete(dzKey);
		});
	}

	_buildSequenceTree(rows) {
		const byKey = new Map();
		const orphanRoots = [];

		rows.forEach((r) => {
			const k = normalizeSequenceKey(r.sequence);
			if (!k) {
				orphanRoots.push({
					sequenceKey: `__orphan__${r.rowKey}`,
					row: { ...r, isVirtualGroup: false },
					children: []
				});
				return;
			}
			this._upsertTreeNode(byKey, k, { ...r, isVirtualGroup: false });
		});

		const keysNeedingAncestors = [...byKey.keys()];
		keysNeedingAncestors.forEach((k) => {
			let p = parentSequenceKey(k);
			while (p) {
				this._upsertTreeNode(byKey, p, this._virtualGroupRow(p));
				p = parentSequenceKey(p);
			}
		});

		byKey.forEach((node) => {
			const pk = parentSequenceKey(node.sequenceKey);
			if (!pk) {
				return;
			}
			const par = byKey.get(pk);
			if (par) {
				par.children.push(node);
			}
		});

		this._mergeDotZeroIntoRootParents(byKey);

		const roots = [];
		byKey.forEach((node) => {
			const pk = parentSequenceKey(node.sequenceKey);
			if (!pk) {
				roots.push(node);
			} else if (!byKey.get(pk)) {
				roots.push(node);
			}
		});

		roots.sort((a, b) => compareSequences(a.sequenceKey, b.sequenceKey));
		orphanRoots.sort((a, b) => (a.row.rowKey < b.row.rowKey ? -1 : a.row.rowKey > b.row.rowKey ? 1 : 0));
		return [...roots, ...orphanRoots];
	}

	_applyDropdownAlignment(rows) {
		if (!rows || rows.length === 0) {
			return rows;
		}
		const lastIdx = rows.length - 1;
		return rows.map((row, idx) => ({
			...row,
			// Last row: open upward so picklists are not clipped by the record page footer.
			dropdownAlignment: idx === lastIdx ? 'top-start' : 'auto'
		}));
	}

	_rebuildDisplayRows() {
		if (!this.groupBySequence || !this.sourceRows.length) {
			const rows = this.sourceRows.map((r) => this._toDisplayRow(r, 0, false, false, null));
			this.displayRows = this._applyDropdownAlignment(rows);
			return;
		}
		const tree = this._buildSequenceTree(this.sourceRows);
		const out = [];
		const walk = (node, depth) => {
			const hasChildren = Boolean(node.children && node.children.length > 0);
			const expandKey = node.sequenceKey;
			const expanded = !hasChildren || this._isParentExpanded(expandKey);
			out.push(this._toDisplayRow(node.row, depth, hasChildren, expanded, expandKey));
			if (hasChildren && expanded) {
				node.children
					.slice()
					.sort((a, b) => compareSequences(a.sequenceKey, b.sequenceKey))
					.forEach((ch) => walk(ch, depth + 1));
			}
		};
		tree.forEach((n) => walk(n, 0));
		this.displayRows = this._applyDropdownAlignment(out);
	}

	_toDisplayRow(row, depth, hasChildren, expanded, groupToggleKey) {
		const indentRem = depth * 1.25;
		const sequenceDisplay = normalizeSequenceKey(row.sequence);
		const showTypeIcon = row.objectApiName === 'Task' || row.objectApiName === 'Event';
		const typeIconName =
			row.objectApiName === 'Task' ? 'standard:task' : row.objectApiName === 'Event' ? 'standard:event' : '';
		const rowClass = row.isCompleted === true ? 'row-line-completed' : '';
		const isCompletedRow = row.isCompleted === true;
		const readOnly = this.isReadOnlyViewer === true;
		const canEditBase = Boolean(row.recordId && !row.isVirtualGroup) && !readOnly;
		const canEditDetails = canEditBase && !isCompletedRow;
		const canEditDueDate = canEditBase && !isCompletedRow;
		const canEditOwner = canEditBase && !isCompletedRow;
		const hasRecordDetails = Boolean(row.recordId && !row.isVirtualGroup);
		const showReadonlyDetails = hasRecordDetails && (isCompletedRow || readOnly);
		const eventPickCount = this.eventStatusOptions ? this.eventStatusOptions.length : 0;
		const isRequiredItem = row.cannotBeDeleted === true;
		const allStatusOptionsForRow =
			row.objectApiName === 'Task' ? this.taskStatusOptions || [] : this.eventStatusOptions || [];
		const statusOptionsForRow = isRequiredItem
			? allStatusOptionsForRow.filter((o) => !isCancelledStatusForUi(o.value) || o.value === row.status)
			: allStatusOptionsForRow;
		const showStatusCombobox =
			!readOnly &&
			canEditBase &&
			(row.objectApiName === 'Task' || (row.objectApiName === 'Event' && eventPickCount > 0));
		const statusDisplayLabel =
			resolvePicklistLabel(row.status, statusOptionsForRow) ||
			(row.status != null ? String(row.status) : '');
		const showReadonlyStatus = hasRecordDetails && !showStatusCombobox;
		const isSaving = this.savingRecordId === row.recordId;
		const normSeq = canonicalRootSequenceKeyForCascadeJs(row.sequence);
		const showLineActions = canEditBase && Boolean(normSeq);
		/** Add subline / add line only on root rows (not on 2.1, 2.2, …); not on completed lines. */
		const showRootLineButtons = showLineActions && !parentSequenceKey(normSeq) && !isCompletedRow;
		const showNewFirstLineButton = showRootLineButtons && isRootLineOne(row.sequence);
		const actionsDisabled = this.lineActionPending || this.savingRecordId != null;
		let statusCellClass = 'inline-field-cell';
		if (showStatusCombobox) {
			statusCellClass += ' status-inline-editable-cell';
		} else if (showReadonlyStatus) {
			statusCellClass += ' status-readonly-cell';
		}
		return {
			...row,
			depth,
			sequenceDisplay,
			seqIndentStyle: `margin-left: ${indentRem}rem`,
			hasChildren,
			expanded,
			groupToggleKey,
			showChevron: hasChildren,
			expandIconName: expanded ? 'utility:chevrondown' : 'utility:chevronright',
			canEditDetails,
			canEditDueDate,
			canEditOwner,
			showReadonlyDetails,
			showTypeIcon,
			typeIconName,
			rowClass,
			canEditInline: canEditBase,
			showStatusCombobox,
			showReadonlyStatus,
			statusDisplayLabel,
			statusOptionsForRow,
			isRequiredItem,
			isSelectable: this._isSelectableRow(row),
			isSelected: this.selectedKeys[row.rowKey] === true,
			isSaving,
			showRootLineButtons,
			showNewFirstLineButton,
			actionsDisabled,
			statusCellClass
		};
	}

	async _persistRow(recordId, objectApiName, partial) {
		if (this.isReadOnlyViewer) {
			return;
		}
		const row = this.sourceRows.find((r) => r.recordId === recordId && r.objectApiName === objectApiName);
		if (!row) {
			return;
		}
		const statusValue = partial.status !== undefined ? partial.status : row.status;
		const ownerId =
			partial.ownerId !== undefined ? partial.ownerId || null : row.ownerId || null;
		const dueDateIso = partial.dueDateIso !== undefined ? partial.dueDateIso || '' : '';
		const subjectValue = partial.title !== undefined ? partial.title : null;
		this.savingRecordId = recordId;
		this._rebuildDisplayRows();
		try {
			await updateProjectItem({
				recordId,
				objectApiName,
				statusValue: statusValue || '',
				ownerId: ownerId || null,
				dueDateIso: dueDateIso || '',
				subjectValue
			});
			this.dispatchEvent(
				new ShowToastEvent({
					title: 'Saved',
					variant: 'success'
				})
			);
			if (this._wiredProjectItemsResult) {
				await refreshApex(this._wiredProjectItemsResult);
			}
		} catch (err) {
			console.error('Could not save project item:', JSON.stringify(err));
			this.dispatchEvent(
				new ShowToastEvent({
					title: 'Could not save',
					message: normalizeSaveError(err),
					variant: 'error',
				})
			);
		} finally {
			this.savingRecordId = null;
			this._rebuildDisplayRows();
		}
	}

	handleStatusChange(event) {
		const recordId = event.currentTarget.dataset.recId;
		const objectApiName = event.currentTarget.dataset.obj;
		const value = event.detail.value;
		if (!recordId || !objectApiName) {
			return;
		}
		this._persistRow(recordId, objectApiName, { status: value });
	}

	handleOwnerChange(event) {
		const recordId = event.currentTarget.dataset.recId;
		const objectApiName = event.currentTarget.dataset.obj;
		const value = event.detail.recordId || null;
		if (!recordId || !objectApiName) {
			return;
		}
		this._persistRow(recordId, objectApiName, { ownerId: value });
	}

	handleDueDateChange(event) {
		const recordId = event.currentTarget.dataset.recId;
		const objectApiName = event.currentTarget.dataset.obj;
		const value = event.detail.value;
		if (!recordId || !objectApiName) {
			return;
		}
		this._persistRow(recordId, objectApiName, { dueDateIso: value || '' });
	}

	/** Save Details (Subject) only when the field loses focus so typing is not interrupted. */
	handleTitleBlur(event) {
		const recordId = event.currentTarget.dataset.recId;
		const objectApiName = event.currentTarget.dataset.obj;
		if (!recordId || !objectApiName) {
			return;
		}
		const row = this.sourceRows.find((r) => r.recordId === recordId && r.objectApiName === objectApiName);
		if (!row) {
			return;
		}
		const input = event.currentTarget;
		let newVal = '';
		if (input && input.value != null) {
			newVal = String(input.value);
		} else if (event.detail && event.detail.value != null) {
			newVal = String(event.detail.value);
		} else if (typeof event.composedPath === 'function') {
			const inner = event.composedPath().find((el) => el && el.tagName === 'INPUT');
			if (inner && inner.value != null) {
				newVal = String(inner.value);
			}
		}
		const oldVal = row.title != null ? String(row.title) : '';
		if (newVal === oldVal) {
			return;
		}
		this._persistRow(recordId, objectApiName, { title: newVal });
	}

	handleGroupByChange(event) {
		this.groupBySequence = event.target.checked;
		if (this.groupBySequence) {
			this._expandedParents = {};
			this._initExpandedForTree();
		}
		this._rebuildDisplayRows();
	}

	/** Turns grouping on and collapses every parent so only roots (1, 2, 3, …) show; expand rows manually as needed. */
	handleGroupAll() {
		if (!this.sourceRows || this.sourceRows.length === 0) {
			return;
		}
		this.groupBySequence = true;
		const parentSet = this._collectParentKeysWithChildren(this.sourceRows);
		const next = {};
		parentSet.forEach((k) => {
			next[k] = false;
		});
		this._expandedParents = next;
		this._rebuildDisplayRows();
	}

	handleToggleGroup(event) {
		event.stopPropagation();
		const key = event.currentTarget.dataset.groupKey;
		if (!key) {
			return;
		}
		const expanded = this._isParentExpanded(key);
		const next = { ...this._expandedParents };
		if (expanded) {
			next[key] = false;
		} else {
			delete next[key];
		}
		this._expandedParents = next;
		this._rebuildDisplayRows();
	}

	handleHideCompletedChange(event) {
		this.hideCompleted = event.target.checked;
		this._applyClientFilters();
	}

	handleHidePastDueChange(event) {
		this.showPastDueOnly = event.target.checked;
		this._applyClientFilters();
	}

	handleRowSelect(event) {
		const key = event.currentTarget.dataset.rowKey;
		if (!key) {
			return;
		}
		const next = { ...this.selectedKeys };
		if (event.target.checked) {
			next[key] = true;
		} else {
			delete next[key];
		}
		this.selectedKeys = next;
		this._rebuildDisplayRows();
	}

	handleSelectAll(event) {
		const next = { ...this.selectedKeys };
		this.selectableDisplayRows.forEach((r) => {
			if (event.target.checked) {
				next[r.rowKey] = true;
			} else {
				delete next[r.rowKey];
			}
		});
		this.selectedKeys = next;
		this._rebuildDisplayRows();
	}

	handleBulkOwnerChange(event) {
		this.bulkOwnerId = event.detail.recordId || null;
	}

	handleMassCancel() {
		this._runMassAction(
			() => massCancelProjectItems({ recordIds: this.selectedRows.map((r) => r.recordId) }),
			'cancelled',
			'Could not cancel items'
		);
	}

	handleMassAssign() {
		const ownerId = this.bulkOwnerId;
		this._runMassAction(
			() =>
				massUpdateProjectItemOwner({
					recordIds: this.selectedRows.map((r) => r.recordId),
					ownerId
				}),
			'reassigned',
			'Could not update assignee'
		);
	}

	async _runMassAction(apexCall, actionVerb, errorTitle) {
		if (this.isReadOnlyViewer || this.selectedCount === 0) {
			return;
		}
		this.lineActionPending = true;
		this._rebuildDisplayRows();
		try {
			const result = await apexCall();
			const updatedCount = result?.updatedCount || 0;
			this.dispatchEvent(
				new ShowToastEvent({
					title: `${updatedCount} item(s) ${actionVerb}`,
					variant: updatedCount > 0 ? 'success' : 'info'
				})
			);
			const skippedRequired = result?.skippedRequired || [];
			const skippedCompleted = result?.skippedCompleted || [];
			if (skippedRequired.length || skippedCompleted.length) {
				const parts = [];
				if (skippedRequired.length) {
					parts.push(`Required by the template: ${skippedRequired.join(', ')}`);
				}
				if (skippedCompleted.length) {
					parts.push(`Already completed or cancelled: ${skippedCompleted.join(', ')}`);
				}
				this.dispatchEvent(
					new ShowToastEvent({
						title: 'Some items were skipped',
						message: parts.join('. '),
						variant: 'warning',
						mode: 'sticky'
					})
				);
			}
			this.selectedKeys = {};
			if (this._wiredProjectItemsResult) {
				await refreshApex(this._wiredProjectItemsResult);
			}
		} catch (err) {
			this.dispatchEvent(
				new ShowToastEvent({
					title: errorTitle,
					message: normalizeSaveError(err),
					variant: 'error'
				})
			);
		} finally {
			this.lineActionPending = false;
			this._rebuildDisplayRows();
		}
	}

	handleNavigate(event) {
		const recordId = event.currentTarget.dataset.recordId;
		const objectApiName = event.currentTarget.dataset.objectApiName;
		if (!recordId || !objectApiName) {
			return;
		}
		this[NavigationMixin.Navigate]({
			type: 'standard__recordPage',
			attributes: {
				recordId,
				objectApiName,
				actionName: 'view'
			}
		});
	}

	async handleAddSubline(event) {
		event.stopPropagation();
		if (this.isReadOnlyViewer) {
			return;
		}
		const seq = event.currentTarget.dataset.seq;
		const recId = event.currentTarget.dataset.recId;
		const obj = event.currentTarget.dataset.obj;
		if (!this.recordId || !seq || !recId || !obj) {
			return;
		}
		this.lineActionPending = true;
		this._rebuildDisplayRows();
		try {
			await createProjectSubline({
				projectId: this.recordId,
				parentSequence: seq,
				anchorRecordId: recId,
				anchorObjectApiName: obj
			});
			this.dispatchEvent(
				new ShowToastEvent({
					title: 'Task added',
					variant: 'success'
				})
			);
			if (this._wiredProjectItemsResult) {
				await refreshApex(this._wiredProjectItemsResult);
			}
		} catch (err) {
			this.dispatchEvent(
				new ShowToastEvent({
					title: 'Could not add subline',
					message: normalizeSaveError(err),
					variant: 'error'
				})
			);
		} finally {
			this.lineActionPending = false;
			this._rebuildDisplayRows();
		}
	}

	async handleAddRootLine(event) {
		event.stopPropagation();
		if (this.isReadOnlyViewer) {
			return;
		}
		const seq = event.currentTarget.dataset.seq;
		const recId = event.currentTarget.dataset.recId;
		const obj = event.currentTarget.dataset.obj;
		if (!this.recordId || !seq || !recId || !obj) {
			return;
		}
		this.lineActionPending = true;
		this._rebuildDisplayRows();
		try {
			await insertProjectRootLineAfterAndShift({
				projectId: this.recordId,
				anchorSequence: seq,
				anchorRecordId: recId,
				anchorObjectApiName: obj
			});
			this.dispatchEvent(
				new ShowToastEvent({
					title: 'Event added',
					variant: 'success'
				})
			);
			if (this._wiredProjectItemsResult) {
				await refreshApex(this._wiredProjectItemsResult);
			}
		} catch (err) {
			this.dispatchEvent(
				new ShowToastEvent({
					title: 'Could not add line',
					message: normalizeSaveError(err),
					variant: 'error'
				})
			);
		} finally {
			this.lineActionPending = false;
			this._rebuildDisplayRows();
		}
	}

	async handleInsertNewFirstLine(event) {
		event.stopPropagation();
		if (this.isReadOnlyViewer) {
			return;
		}
		const seq = event.currentTarget.dataset.seq;
		const recId = event.currentTarget.dataset.recId;
		const obj = event.currentTarget.dataset.obj;
		if (!this.recordId || !seq || !recId || !obj) {
			return;
		}
		this.lineActionPending = true;
		this._rebuildDisplayRows();
		try {
			await insertNewFirstRootLineAndShift({
				projectId: this.recordId,
				anchorSequence: seq,
				anchorRecordId: recId,
				anchorObjectApiName: obj
			});
			this.dispatchEvent(
				new ShowToastEvent({
					title: 'New first line added',
					variant: 'success'
				})
			);
			if (this._wiredProjectItemsResult) {
				await refreshApex(this._wiredProjectItemsResult);
			}
		} catch (err) {
			this.dispatchEvent(
				new ShowToastEvent({
					title: 'Could not add new first line',
					message: normalizeSaveError(err),
					variant: 'error'
				})
			);
		} finally {
			this.lineActionPending = false;
			this._rebuildDisplayRows();
		}
	}
}