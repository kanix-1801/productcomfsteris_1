/**
 * @description GW-5892 / GW-6600: Field Service quote editor (Quote "Edit Quote" action).
 *              Header strip + Time (Labor/Travel), Parts and Expenses tabs. Changes stay local until Save All;
 *              lines show New / Modified badges as in the debrief.
 *              The quote is loaded through GraphQL, so the Field Service mobile app reads it from its offline
 *              store: a quote created on the device opens before it has synced. Save All and Calculate Pricing
 *              run in Apex and need the quote to be on the server.
 * @see FieldServiceQuoteController
 */
import { LightningElement, api, wire } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord, getFieldValue, notifyRecordUpdateAvailable, updateRecord } from 'lightning/uiRecordApi';
import { getPicklistValues } from 'lightning/uiObjectInfoApi';
import { gql, graphql, refreshGraphQL } from 'lightning/uiGraphQLApi';
import FORM_FACTOR from '@salesforce/client/formFactor';
import HAS_PRICE_OVERRIDE from '@salesforce/customPermission/FS_Quote_Price_Override';
import QUOTE_RECORD_TYPE_FIELD from '@salesforce/schema/Quote.RecordTypeId';
import QUOTE_STATUS_FIELD from '@salesforce/schema/Quote.Status';
import QUOTE_ID_FIELD from '@salesforce/schema/Quote.Id';
import AWAITING_PO_FIELD from '@salesforce/schema/Quote.AwaitingPO__c';
import PURCHASE_ORDER_FIELD from '@salesforce/schema/Quote.PurchaseOrder__c';
import PO_FOLLOW_UP_DATE_FIELD from '@salesforce/schema/Quote.POFollowUpDate__c';
import EXPENSE_TYPE_FIELD from '@salesforce/schema/QuoteLineItem.ExpenseType__c';
import getQuote from '@salesforce/apex/FieldServiceQuoteController.getQuote';
import saveQuote from '@salesforce/apex/FieldServiceQuoteController.saveQuote';
import calculatePricing from '@salesforce/apex/FieldServiceQuotePricingService.calculatePricing';
import {
	RATE_OPTIONS,
	TRAVEL_TYPE_ACTUAL,
	buildLaborRateOptionsFromRateList,
	buildTravelTypeOptionsFromRateList,
	defaultTravelType
} from 'c/fsRateListOptions';

const LINE_TYPE = { PARTS: 'Parts', LABOR: 'Labor', TRAVEL: 'Travel', EXPENSE: 'Expense' };
const TAB = { TIME: 'time', PARTS: 'parts', EXPENSES: 'expenses' };
const TAB_LINE_TYPES = {
	[TAB.TIME]: [LINE_TYPE.LABOR, LINE_TYPE.TRAVEL],
	[TAB.PARTS]: [LINE_TYPE.PARTS],
	[TAB.EXPENSES]: [LINE_TYPE.EXPENSE]
};
const STATE = { SAVED: 'saved', NEW: 'new', MODIFIED: 'modified' };
// QuoteLineItem has no record types, so its picklists are read from the master record type.
const MASTER_RECORD_TYPE_ID = '012000000000000AAA';
const CALCULATE_PRICING_FLOW = 'Quote_SCR_CalculatePricing';
const PRICING_BADGE_CLASS = {
	Priced: 'slds-badge slds-theme_success',
	'Repricing Required': 'slds-badge slds-theme_warning',
	'Pricing Error': 'slds-badge slds-theme_error'
};
// Same as FieldServiceQuoteService.EXPENSE_PRODUCT_CODE.
const EXPENSE_PRODUCT_CODE = 'FSEXPPRT';
const QUOTE_NOT_FOUND = 'The quote was not found or you do not have access to it.';
// Field Service mobile fails an Apex call without a message when the quote is not on the server yet.
const NOT_SYNCED_MESSAGE =
	'The quote has not finished syncing to Salesforce. Your changes are kept. Wait a moment and try again.';

// Quote header, Rate List and editor lines in one query (same fields as FieldServiceQuoteController).
const QUOTE_EDITOR_QUERY = gql`
	query fieldServiceQuoteEditor($quoteId: ID) {
		uiapi {
			query {
				Quote(where: { Id: { eq: $quoteId } }, first: 1) {
					edges {
						node {
							Id
							QuoteNumber {
								value
							}
							Status {
								value
							}
							AccountId {
								value
							}
							Account {
								Name {
									value
								}
							}
							QuoteAccountId {
								value
							}
							QuoteAccount {
								Name {
									value
								}
							}
							Asset__r {
								Name {
									value
								}
							}
							WorkOrder__r {
								WorkOrderNumber {
									value
								}
							}
							ContactId {
								value
							}
							ShipToAccount__c {
								value
							}
							OwnerId {
								value
							}
							Pricebook2Id {
								value
							}
							CurrencyIsoCode {
								value
							}
							PricingStatus__c {
								value
							}
							PricingMessage__c {
								value
							}
							GrandTotal {
								value
							}
							RateList__r {
								Id
								Name {
									value
								}
								LaborHour__c {
									value
								}
								TravelHour__c {
									value
								}
								PremiumRateHour__c {
									value
								}
								ExtendedOvertimeRatePerHour__c {
									value
								}
								TravelZone1__c {
									value
								}
								TravelZone2__c {
									value
								}
								TravelZone3__c {
									value
								}
								TravelZone4__c {
									value
								}
							}
						}
					}
				}
				QuoteLineItem(
					where: {
						and: [
							{ QuoteId: { eq: $quoteId } }
							{ LineType__c: { in: ["Parts", "Labor", "Travel", "Expense"] } }
						]
					}
					orderBy: { SortOrder: { order: ASC, nulls: LAST }, CreatedDate: { order: ASC } }
					first: 2000
				) {
					edges {
						node {
							Id
							LineType__c {
								value
							}
							Product2Id {
								value
							}
							Product2 {
								Name {
									value
								}
								ProductCode {
									value
								}
							}
							Quantity {
								value
							}
							Rate__c {
								value
							}
							TravelType__c {
								value
							}
							ExpenseType__c {
								value
							}
							ListPrice {
								value
							}
							UnitPrice {
								value
							}
							Discount {
								value
							}
							TotalPrice {
								value
							}
							Description {
								value
							}
							IsManualPrice__c {
								value
							}
							PricingMessage__c {
								value
							}
						}
					}
				}
			}
		}
	}
`;

// The expense product and its price in the quote's price book and currency.
const EXPENSE_PRODUCT_QUERY = gql`
	query fieldServiceQuoteExpenseProduct($pricebookId: ID, $currencyIsoCode: Picklist, $productCode: String) {
		uiapi {
			query {
				PricebookEntry(
					where: {
						and: [
							{ Pricebook2Id: { eq: $pricebookId } }
							{ CurrencyIsoCode: { eq: $currencyIsoCode } }
							{ IsActive: { eq: true } }
							{ Product2: { ProductCode: { eq: $productCode } } }
							{ Product2: { IsActive: { eq: true } } }
						]
					}
					first: 1
				) {
					edges {
						node {
							Id
							UnitPrice {
								value
							}
							Product2Id {
								value
							}
							Product2 {
								Name {
									value
								}
								ProductCode {
									value
								}
							}
						}
					}
				}
			}
		}
	}
`;

// Price of the Parts product picked on a line, from the quote's price book and currency (no Apex).
const PRODUCT_PRICE_QUERY = gql`
	query fieldServiceQuoteProductPrice($pricebookId: ID, $productId: ID, $currencyIsoCode: Picklist) {
		uiapi {
			query {
				PricebookEntry(
					where: {
						and: [
							{ Pricebook2Id: { eq: $pricebookId } }
							{ Product2Id: { eq: $productId } }
							{ CurrencyIsoCode: { eq: $currencyIsoCode } }
							{ IsActive: { eq: true } }
						]
					}
					first: 1
				) {
					edges {
						node {
							Id
							UnitPrice {
								value
							}
							Product2Id {
								value
							}
							Product2 {
								Name {
									value
								}
								ProductCode {
									value
								}
							}
						}
					}
				}
			}
		}
	}
`;

let keySequence = 0;
const nextKey = () => `new-${++keySequence}`;

const valueOf = (field) => field?.value ?? null;

export default class FieldServiceQuoteEditor extends LightningElement {
	@api recordId;

	// Quote Id from GraphQL: the server Id once a quote created on the device has synced.
	quoteNodeId;
	quoteResult;
	expenseProduct;
	// Set once Apex returned the quote (Save All, Calculate Pricing). From then on the server view is shown:
	// on Field Service mobile the GraphQL cache keeps the old lines until the app syncs.
	hasServerView = false;

	isLoading = true;
	isSaving = false;
	errorMessage;
	activeTab = TAB.TIME;
	editingKey;
	showPricingFlow = false;
	pricingRunning = false;
	pricingResultMessage;
	pricingResultIsError = false;

	view;
	header = {};
	originalHeader = {};
	lines = [];
	deletedLineIds = [];

	// ---------------------------------------------------------------- data

	get quoteVariables() {
		return this.recordId ? { quoteId: this.recordId } : undefined;
	}

	/**
	 * @description Loads the quote from LDS (the device's offline store on Field Service mobile). A refresh
	 *              while the user has unsaved changes keeps their changes and only takes the new quote Id.
	 */
	@wire(graphql, { query: QUOTE_EDITOR_QUERY, variables: '$quoteVariables' })
	wiredQuote(result) {
		this.quoteResult = result;
		const { data, errors } = result;
		if (!data && !errors) {
			return;
		}
		const node = data?.uiapi?.query?.Quote?.edges?.[0]?.node;
		if (!node) {
			this.errorMessage = errors ? this.reduceError({ body: errors }) : QUOTE_NOT_FOUND;
			this.isLoading = false;
			return;
		}
		this.errorMessage = undefined;
		this.quoteNodeId = node.Id;
		if (!this.view || (!this.hasServerView && this.quoteChangeCount === 0)) {
			this.applyView(this.toView(node, data.uiapi.query.QuoteLineItem?.edges || []));
		}
		this.isLoading = false;
	}

	toView(node, lineEdges) {
		const rateList = node.RateList__r;
		return {
			header: {
				quoteNumber: valueOf(node.QuoteNumber),
				status: valueOf(node.Status),
				workOrderNumber: valueOf(node.WorkOrder__r?.WorkOrderNumber),
				accountId: valueOf(node.AccountId) || valueOf(node.QuoteAccountId),
				accountName: valueOf(node.AccountId)
					? valueOf(node.Account?.Name)
					: valueOf(node.QuoteAccount?.Name),
				assetName: valueOf(node.Asset__r?.Name),
				contactId: valueOf(node.ContactId),
				shipToId: valueOf(node.ShipToAccount__c),
				ownerId: valueOf(node.OwnerId),
				rateListName: valueOf(rateList?.Name),
				pricebookId: valueOf(node.Pricebook2Id),
				currencyIsoCode: valueOf(node.CurrencyIsoCode),
				pricingStatus: valueOf(node.PricingStatus__c),
				pricingMessage: valueOf(node.PricingMessage__c),
				totalPrice: valueOf(node.GrandTotal)
			},
			lines: lineEdges.map(({ node: line }) => ({
				id: line.Id,
				lineType: valueOf(line.LineType__c),
				product2Id: valueOf(line.Product2Id),
				productName: valueOf(line.Product2?.Name),
				productCode: valueOf(line.Product2?.ProductCode),
				quantity: valueOf(line.Quantity),
				rate: valueOf(line.Rate__c),
				travelType: valueOf(line.TravelType__c),
				expenseType: valueOf(line.ExpenseType__c),
				listPrice: valueOf(line.ListPrice),
				unitPrice: valueOf(line.UnitPrice),
				discount: valueOf(line.Discount),
				totalPrice: valueOf(line.TotalPrice),
				description: valueOf(line.Description),
				isManualPrice: valueOf(line.IsManualPrice__c),
				pricingMessage: valueOf(line.PricingMessage__c)
			})),
			rateList: rateList?.Id
				? {
						rateListId: rateList.Id,
						name: valueOf(rateList.Name),
						laborHour: valueOf(rateList.LaborHour__c),
						travelHour: valueOf(rateList.TravelHour__c),
						premiumRateHour: valueOf(rateList.PremiumRateHour__c),
						extendedOvertimeRatePerHour: valueOf(rateList.ExtendedOvertimeRatePerHour__c),
						travelZone1: valueOf(rateList.TravelZone1__c),
						travelZone2: valueOf(rateList.TravelZone2__c),
						travelZone3: valueOf(rateList.TravelZone3__c),
						travelZone4: valueOf(rateList.TravelZone4__c)
					}
				: null,
			canOverridePrice: HAS_PRICE_OVERRIDE === true
		};
	}

	get expenseProductVariables() {
		if (!this.h.pricebookId || !this.h.currencyIsoCode) {
			return undefined;
		}
		return {
			pricebookId: this.h.pricebookId,
			currencyIsoCode: this.h.currencyIsoCode,
			productCode: EXPENSE_PRODUCT_CODE
		};
	}

	@wire(graphql, { query: EXPENSE_PRODUCT_QUERY, variables: '$expenseProductVariables' })
	wiredExpenseProduct({ data }) {
		const node = data?.uiapi?.query?.PricebookEntry?.edges?.[0]?.node;
		if (data) {
			this.expenseProduct = node
				? {
						product2Id: valueOf(node.Product2Id),
						productName: valueOf(node.Product2?.Name),
						productCode: valueOf(node.Product2?.ProductCode),
						listPrice: valueOf(node.UnitPrice)
					}
				: null;
		}
	}

	/** @description Quote Id for Apex: the synced server Id when GraphQL has it. */
	get quoteId() {
		return this.quoteNodeId || this.recordId;
	}

	/** @description Shows the quote as Apex returned it; later GraphQL results no longer replace it. */
	applyServerView(view) {
		this.applyView(view);
		this.hasServerView = true;
	}

	/** @description Reads the quote from the server after Calculate Pricing or a PO save changed it. */
	async reloadFromServer() {
		this.applyServerView(await getQuote({ quoteId: this.quoteId }));
		await this.refreshQuote();
	}

	/**
	 * @description Tells LDS (the offline store on Field Service mobile) that Apex changed the quote, so the
	 *              editor opens with current data next time. The editor keeps showing the Apex result.
	 */
	async refreshQuote() {
		try {
			await refreshGraphQL(this.quoteResult);
		} catch (e) {
			// The view already shows the Apex result; a failed cache refresh is not shown to the user.
		}
		notifyRecordUpdateAvailable([{ recordId: this.quoteId }]);
	}

	applyView(view) {
		this.view = view;
		this.header = {
			status: view.header.status,
			contactId: view.header.contactId,
			shipToId: view.header.shipToId,
			ownerId: view.header.ownerId
		};
		this.originalHeader = { ...this.header };
		this.lines = (view.lines || []).map((line) => ({ ...line, key: line.id, state: STATE.SAVED }));
		this.deletedLineIds = [];
		this.editingKey = undefined;
	}

	// ---------------------------------------------------------------- header

	get h() {
		return this.view?.header || {};
	}

	// Picklist options come from LDS (no Apex); Status follows the quote's record type.
	// GW-5898: the PO fields are read and saved through LDS too (works offline in the Field Service app).
	quoteRecord;
	poHeader = { awaitingPO: false, purchaseOrder: null };
	originalPoHeader = { awaitingPO: false, purchaseOrder: null };
	poFollowUpDate;

	// The PO fields are optional so a user without access to them still gets the record type (Status picklist).
	@wire(getRecord, {
		recordId: '$recordId',
		fields: [QUOTE_RECORD_TYPE_FIELD],
		optionalFields: [AWAITING_PO_FIELD, PURCHASE_ORDER_FIELD, PO_FOLLOW_UP_DATE_FIELD]
	})
	wiredQuoteRecord(result) {
		this.quoteRecord = result;
		if (result.data) {
			this.poFollowUpDate = getFieldValue(result.data, PO_FOLLOW_UP_DATE_FIELD);
			// Keep the technician's unsaved PO edits when the record refreshes.
			if (!this.poChangeCount) {
				this.poHeader = {
					awaitingPO: getFieldValue(result.data, AWAITING_PO_FIELD) === true,
					purchaseOrder: getFieldValue(result.data, PURCHASE_ORDER_FIELD) || null
				};
				this.originalPoHeader = { ...this.poHeader };
			}
		}
	}

	@wire(getPicklistValues, { recordTypeId: '$quoteRecord.data.recordTypeId', fieldApiName: QUOTE_STATUS_FIELD })
	statusPicklist;

	@wire(getPicklistValues, { recordTypeId: MASTER_RECORD_TYPE_ID, fieldApiName: EXPENSE_TYPE_FIELD })
	expenseTypePicklist;

	get statusOptions() {
		return this.statusPicklist?.data?.values || [];
	}

	get contactFilter() {
		const accountId = this.h.accountId;
		return accountId
			? { criteria: [{ fieldPath: 'AccountId', operator: 'eq', value: accountId }] }
			: undefined;
	}

	get userFilter() {
		return { criteria: [{ fieldPath: 'IsActive', operator: 'eq', value: true }] };
	}

	get productFilter() {
		return { criteria: [{ fieldPath: 'IsActive', operator: 'eq', value: true }] };
	}

	get rateListLabel() {
		const parts = [this.h.rateListName || 'No Rate List', this.h.currencyIsoCode].filter(Boolean);
		return parts.join(' · ');
	}

	get pricingLabel() {
		return this.h.pricingStatus || 'Not Priced';
	}

	get pricingBadgeClass() {
		return PRICING_BADGE_CLASS[this.h.pricingStatus] || 'slds-badge';
	}

	get quoteTotalLabel() {
		return this.h.totalPrice === null || this.h.totalPrice === undefined
			? '—'
			: this.formatCurrency(this.h.totalPrice);
	}

	handleHeaderChange(event) {
		const field = event.target.dataset.field;
		const value = event.detail.recordId !== undefined ? event.detail.recordId : event.detail.value;
		this.header = { ...this.header, [field]: value || null };
	}

	// ---------------------------------------------------------------- PO follow-up (GW-5898)

	handleAwaitingPoChange(event) {
		this.poHeader = { ...this.poHeader, awaitingPO: event.target.checked };
	}

	handlePurchaseOrderChange(event) {
		const value = (event.detail.value || '').trim();
		this.poHeader = { ...this.poHeader, purchaseOrder: value || null };
	}

	get poFollowUpLabel() {
		return this.originalPoHeader.awaitingPO && this.poFollowUpDate ? this.poFollowUpDate : null;
	}

	get poChangeCount() {
		return Object.keys(this.poHeader).filter((field) => this.poHeader[field] !== this.originalPoHeader[field])
			.length;
	}

	// ---------------------------------------------------------------- tabs & lines

	get timeTabLabel() {
		return `Time (${this.countFor(TAB.TIME)})`;
	}

	get partsTabLabel() {
		return `Parts (${this.countFor(TAB.PARTS)})`;
	}

	get expensesTabLabel() {
		return `Expenses (${this.countFor(TAB.EXPENSES)})`;
	}

	countFor(tab) {
		return this.lines.filter((line) => TAB_LINE_TYPES[tab].includes(line.lineType)).length;
	}

	get timeLines() {
		return this.decorate(TAB.TIME);
	}

	get partLines() {
		return this.decorate(TAB.PARTS);
	}

	get expenseLines() {
		return this.decorate(TAB.EXPENSES);
	}

	get hasTimeLines() {
		return this.countFor(TAB.TIME) > 0;
	}

	get hasPartLines() {
		return this.countFor(TAB.PARTS) > 0;
	}

	get hasExpenseLines() {
		return this.countFor(TAB.EXPENSES) > 0;
	}

	get canOverridePrice() {
		return this.view?.canOverridePrice === true;
	}

	get laborRateOptions() {
		return buildLaborRateOptionsFromRateList(this.view?.rateList);
	}

	get travelTypeOptions() {
		return buildTravelTypeOptionsFromRateList(this.view?.rateList);
	}

	get travelTypeHelp() {
		const options = this.travelTypeOptions;
		if (!options.length) {
			return 'The Rate List has no travel amounts.';
		}
		const offered = options
			.map((o) => (o.value === TRAVEL_TYPE_ACTUAL ? o.label : `${o.label} (${this.formatCurrency(o.amount)})`))
			.join(', ');
		return `Options from the Rate List: ${offered}. Zones without an amount are not offered.`;
	}

	get expenseTypeOptions() {
		return this.expenseTypePicklist?.data?.values || [];
	}

	decorate(tab) {
		return this.lines
			.filter((line) => TAB_LINE_TYPES[tab].includes(line.lineType))
			.map((line) => {
				const isLabor = line.lineType === LINE_TYPE.LABOR;
				const isTravel = line.lineType === LINE_TYPE.TRAVEL;
				const isZoneTravel = isTravel && line.travelType && line.travelType !== TRAVEL_TYPE_ACTUAL;
				const total = this.computeTotal(line);
				return {
					...line,
					isEditing: line.key === this.editingKey,
					isNew: line.state === STATE.NEW,
					isModified: line.state === STATE.MODIFIED,
					isLabor,
					isTravel,
					isZoneTravel,
					isSaved: line.state !== STATE.NEW,
					laborVariant: isLabor ? 'brand' : 'neutral',
					travelVariant: isTravel ? 'brand' : 'neutral',
					rateOptions: isLabor ? this.laborRateOptions : RATE_OPTIONS,
					rateDisabled: isZoneTravel,
					ratePlaceholder: isZoneTravel ? 'Not used for zone travel' : 'Select a rate',
					quantityDisabled: isZoneTravel,
					quantityLabel: isLabor || (isTravel && !isZoneTravel) ? 'Quantity (hours)' : 'Quantity',
					unitPriceDisabled: !(this.canOverridePrice || line.lineType === LINE_TYPE.EXPENSE),
					title: this.lineTitle(line),
					subtitle: [line.description, total === null ? null : this.formatCurrency(total)]
						.filter(Boolean)
						.join(' · '),
					computedTotal: total,
					cardClass: `slds-box slds-box_x-small slds-m-bottom_x-small line-card line-${line.state}`
				};
			});
	}

	lineTitle(line) {
		const hours = line.quantity ? `${Number(line.quantity).toFixed(1)} h` : null;
		switch (line.lineType) {
			case LINE_TYPE.LABOR:
				return ['Labor', line.rate, hours].filter(Boolean).join(' · ');
			case LINE_TYPE.TRAVEL:
				return line.travelType === TRAVEL_TYPE_ACTUAL
					? ['Travel', line.travelType, line.rate, hours].filter(Boolean).join(' · ')
					: ['Travel', line.travelType].filter(Boolean).join(' · ');
			case LINE_TYPE.EXPENSE:
				return ['Expense', line.expenseType, line.quantity ? `Qty ${line.quantity}` : null]
					.filter(Boolean)
					.join(' · ');
			default:
				return [line.productName || 'New part', line.productCode, line.quantity ? `Qty ${line.quantity}` : null]
					.filter(Boolean)
					.join(' · ');
		}
	}

	computeTotal(line) {
		if (line.unitPrice === null || line.unitPrice === undefined || !line.quantity) {
			return line.totalPrice ?? null;
		}
		const discount = Number(line.discount || 0);
		return Number(line.quantity) * Number(line.unitPrice) * (1 - discount / 100);
	}

	handleTabActive(event) {
		this.activeTab = event.target.value;
		this.editingKey = undefined;
	}

	handleAddTimeLine() {
		const rateList = this.view?.rateList;
		this.addLine({
			lineType: LINE_TYPE.LABOR,
			quantity: 1,
			rate: this.laborRateOptions[0]?.value || null,
			travelType: defaultTravelType(rateList) || null
		});
	}

	handleAddPart() {
		this.addLine({ lineType: LINE_TYPE.PARTS, quantity: 1 });
	}

	handleAddExpense() {
		const product = this.expenseProduct;
		if (!product) {
			this.toast('Expense part missing', 'The expense part has no price in this quote price book.', 'error');
			return;
		}
		this.addLine({
			lineType: LINE_TYPE.EXPENSE,
			quantity: 1,
			product2Id: product.product2Id,
			productName: product.productName,
			productCode: product.productCode,
			listPrice: product.listPrice,
			unitPrice: product.listPrice
		});
	}

	addLine(values) {
		const key = nextKey();
		this.lines = [
			...this.lines,
			{
				id: null,
				key,
				state: STATE.NEW,
				discount: null,
				description: null,
				isManualPrice: false,
				...values
			}
		];
		this.editingKey = key;
	}

	handleEditLine(event) {
		const key = event.currentTarget.dataset.key;
		this.editingKey = this.editingKey === key ? undefined : key;
	}

	handleDoneEditing() {
		this.editingKey = undefined;
	}

	handleDeleteLine(event) {
		const key = event.currentTarget.dataset.key;
		const line = this.lines.find((l) => l.key === key);
		if (!line) {
			return;
		}
		if (line.id) {
			this.deletedLineIds = [...this.deletedLineIds, line.id];
		}
		this.lines = this.lines.filter((l) => l.key !== key);
		if (this.editingKey === key) {
			this.editingKey = undefined;
		}
	}

	handleLineTypeChange(event) {
		const key = event.currentTarget.dataset.key;
		const lineType = event.currentTarget.dataset.value;
		this.updateLine(key, (line) => {
			const next = { ...line, lineType };
			if (lineType === LINE_TYPE.LABOR) {
				next.rate = this.laborRateOptions.some((o) => o.value === line.rate)
					? line.rate
					: this.laborRateOptions[0]?.value || null;
			} else {
				next.travelType = line.travelType || defaultTravelType(this.view?.rateList) || null;
				next.rate = next.travelType === TRAVEL_TYPE_ACTUAL ? line.rate || 'Standard' : null;
				if (next.travelType !== TRAVEL_TYPE_ACTUAL) {
					next.quantity = 1;
				}
			}
			return next;
		});
	}

	handleLineFieldChange(event) {
		const key = event.target.dataset.key;
		const field = event.target.dataset.field;
		let value = event.target.type === 'checkbox' ? event.target.checked : event.detail.value;
		if (['quantity', 'unitPrice', 'discount'].includes(field)) {
			value = value === '' || value === null || value === undefined ? null : Number(value);
		}
		this.updateLine(key, (line) => {
			const next = { ...line, [field]: value };
			if (field === 'travelType') {
				if (value !== TRAVEL_TYPE_ACTUAL) {
					next.quantity = 1;
					next.rate = null;
				} else if (!next.rate) {
					next.rate = 'Standard';
				}
			}
			if (field === 'unitPrice' && this.canOverridePrice && line.lineType !== LINE_TYPE.EXPENSE) {
				next.isManualPrice = true;
			}
			return next;
		});
	}

	// Parts product lookups: results are cached per product; lines wait by key while a lookup runs.
	pendingProductId;
	productCache = new Map();
	linesWaitingForProduct = new Map();

	get productPriceVariables() {
		if (!this.pendingProductId || !this.h.pricebookId || !this.h.currencyIsoCode) {
			return undefined;
		}
		return {
			pricebookId: this.h.pricebookId,
			productId: this.pendingProductId,
			currencyIsoCode: this.h.currencyIsoCode
		};
	}

	@wire(graphql, { query: PRODUCT_PRICE_QUERY, variables: '$productPriceVariables' })
	wiredProductPrice({ data, errors }) {
		const productId = this.pendingProductId;
		if (!productId || (!data && !errors)) {
			return;
		}
		if (errors) {
			this.linesWaitingForProduct.delete(productId);
			this.toast('Product not available', this.reduceError({ body: errors }), 'error');
			this.lookUpNextWaitingProduct();
			return;
		}
		const node = data?.uiapi?.query?.PricebookEntry?.edges?.[0]?.node;
		const product = node
			? {
					product2Id: node.Product2Id?.value,
					productName: node.Product2?.Name?.value,
					productCode: node.Product2?.ProductCode?.value,
					listPrice: node.UnitPrice?.value
				}
			: null;
		this.productCache.set(productId, product);
		const keys = this.linesWaitingForProduct.get(productId) || new Set();
		this.linesWaitingForProduct.delete(productId);
		keys.forEach((key) => this.applyProduct(key, product));
		this.lookUpNextWaitingProduct();
	}

	// A product picked while another lookup was running is looked up once that lookup finishes.
	lookUpNextWaitingProduct() {
		const nextProductId = this.linesWaitingForProduct.keys().next().value;
		if (nextProductId) {
			this.pendingProductId = nextProductId;
		}
	}

	handleProductChange(event) {
		const key = event.target.dataset.key;
		const productId = event.detail.recordId;
		if (!productId) {
			this.updateLine(key, (line) => ({
				...line,
				product2Id: null,
				productName: null,
				productCode: null,
				listPrice: null,
				unitPrice: null
			}));
			return;
		}
		if (this.productCache.has(productId)) {
			this.applyProduct(key, this.productCache.get(productId));
			return;
		}
		const keys = this.linesWaitingForProduct.get(productId) || new Set();
		keys.add(key);
		this.linesWaitingForProduct.set(productId, keys);
		this.pendingProductId = productId;
	}

	applyProduct(key, product) {
		if (!product) {
			this.toast(
				'Product not available',
				`This product has no active price in the quote price book (${this.h.currencyIsoCode}).`,
				'error'
			);
			return;
		}
		this.updateLine(key, (line) => ({
			...line,
			product2Id: product.product2Id,
			productName: product.productName,
			productCode: product.productCode,
			listPrice: product.listPrice,
			unitPrice: product.listPrice
		}));
	}

	updateLine(key, updater) {
		this.lines = this.lines.map((line) => {
			if (line.key !== key) {
				return line;
			}
			const next = updater(line);
			if (next.state === STATE.SAVED) {
				next.state = STATE.MODIFIED;
			}
			return next;
		});
	}

	// ---------------------------------------------------------------- footer

	get headerChangeCount() {
		return Object.keys(this.header).filter((field) => this.header[field] !== this.originalHeader[field]).length;
	}

	get quoteChangeCount() {
		const lineChanges = this.lines.filter((line) => line.state !== STATE.SAVED).length;
		return lineChanges + this.deletedLineIds.length + this.headerChangeCount;
	}

	get unsavedChangeCount() {
		return this.quoteChangeCount + this.poChangeCount;
	}

	get unsavedChangesLabel() {
		const count = this.unsavedChangeCount;
		if (!count) {
			return 'No unsaved changes';
		}
		return count === 1 ? '1 unsaved change' : `${count} unsaved changes`;
	}

	get saveDisabled() {
		return !this.view || this.isSaving || this.isLoading || this.unsavedChangeCount === 0;
	}

	get calculateDisabled() {
		return !this.view || this.isSaving || this.isLoading || this.unsavedChangeCount > 0;
	}

	get calculateTitle() {
		return this.unsavedChangeCount > 0 ? 'Save All before calculating pricing' : 'Calculate Pricing';
	}

	/**
	 * @description Quote_SCR_CalculatePricing loads the Quote from this Id, then prices parts (Oracle),
	 *              labor and travel (Rate List), and shipping.
	 */
	get pricingFlowInputs() {
		return [
			{
				name: 'recordId',
				type: 'SObject',
				value: {
					Id: this.quoteId
				}
			}
		];
	}

	get pricingFlowName() {
		return CALCULATE_PRICING_FLOW;
	}

	/**
	 * @description Field Service mobile cannot render lightning-flow. It shows "invalid parameter value"
	 *              and the flow never starts. Phone and tablet run the autolaunched flow through Apex.
	 */
	get runsPricingInApex() {
		return FORM_FACTOR !== 'Large';
	}

	get showEmbeddedFlow() {
		return this.showPricingFlow && !this.runsPricingInApex;
	}

	get pricingResultClass() {
		return this.pricingResultIsError
			? 'slds-text-color_error slds-p-vertical_x-small'
			: 'slds-text-color_success slds-p-vertical_x-small';
	}

	handleCancel() {
		this.dispatchEvent(new CloseActionScreenEvent());
	}

	async handleCalculatePricing() {
		this.pricingResultMessage = undefined;
		this.pricingResultIsError = false;
		this.showPricingFlow = true;
		if (!this.runsPricingInApex) {
			return;
		}
		this.pricingRunning = true;
		try {
			const result = await calculatePricing({ quoteId: this.quoteId });
			await this.reloadFromServer();
			this.pricingResultMessage = result?.message;
			this.pricingResultIsError = result?.status !== 'Priced';
		} catch (error) {
			this.pricingResultMessage = this.reduceError(error, NOT_SYNCED_MESSAGE);
			this.pricingResultIsError = true;
		} finally {
			this.pricingRunning = false;
		}
	}

	handleClosePricingFlow() {
		this.showPricingFlow = false;
		this.pricingRunning = false;
		this.pricingResultMessage = undefined;
	}

	async handlePricingFlowStatus(event) {
		if (event.detail.status === 'FINISHED' || event.detail.status === 'FINISHED_SCREEN') {
			this.showPricingFlow = false;
			try {
				await this.reloadFromServer();
			} catch (error) {
				this.toast('Quote not refreshed', this.reduceError(error, NOT_SYNCED_MESSAGE), 'error');
			}
		}
	}

	async handleSaveAll() {
		const invalid = this.validateLines();
		if (invalid) {
			this.toast('Fix the highlighted line', invalid, 'error');
			return;
		}
		this.isSaving = true;
		try {
			if (this.quoteChangeCount > 0) {
				const payload = {
					...this.header,
					lines: this.lines
						.filter((line) => line.state !== STATE.SAVED)
						.map((line) => ({
							id: line.id,
							lineType: line.lineType,
							product2Id: line.product2Id,
							quantity: line.quantity,
							rate: line.rate,
							travelType: line.travelType,
							expenseType: line.expenseType,
							unitPrice: line.unitPrice,
							discount: line.discount,
							description: line.description,
							isManualPrice: line.isManualPrice
						})),
					deletedLineIds: this.deletedLineIds
				};
				const view = await saveQuote({ quoteId: this.quoteId, payloadJson: JSON.stringify(payload) });
				this.applyServerView(view);
			}
			if (this.poChangeCount > 0) {
				await this.savePoFields();
				// The PO flows may change the quote (Status): read it back from the server when it is reachable.
				try {
					await this.reloadFromServer();
				} catch (e) {
					await this.refreshQuote();
				}
			} else {
				await this.refreshQuote();
			}
			this.toast('Quote saved', 'All changes were saved.', 'success');
		} catch (error) {
			this.toast('Quote not saved', this.reduceError(error, NOT_SYNCED_MESSAGE), 'error');
		} finally {
			this.isSaving = false;
		}
	}

	/**
	 * @description GW-5898: saves Awaiting PO and Purchase Order through LDS. The quote flows then set the
	 *              follow-up date, or accept the quote when a PO is entered, so Save All reloads the quote
	 *              (refreshQuote) afterwards.
	 */
	async savePoFields() {
		await updateRecord({
			fields: {
				[QUOTE_ID_FIELD.fieldApiName]: this.recordId,
				[AWAITING_PO_FIELD.fieldApiName]: this.poHeader.awaitingPO,
				[PURCHASE_ORDER_FIELD.fieldApiName]: this.poHeader.purchaseOrder
			}
		});
		this.originalPoHeader = { ...this.poHeader };
	}

	/**
	 * @description Line checks before Save All (the only validation; Apex does not repeat it).
	 * @return {string|undefined} First error, opening the offending line
	 */
	validateLines() {
		for (const line of this.lines) {
			if (line.state === STATE.SAVED) {
				continue;
			}
			let message;
			if (!line.quantity || line.quantity <= 0) {
				message = 'Quantity must be greater than zero.';
			} else if (line.lineType === LINE_TYPE.LABOR && !line.rate) {
				message = 'Rate is required for Labor lines.';
			} else if (line.lineType === LINE_TYPE.TRAVEL && !line.travelType) {
				message = 'Travel Type is required for Travel lines.';
			} else if (line.lineType === LINE_TYPE.TRAVEL && line.travelType === TRAVEL_TYPE_ACTUAL && !line.rate) {
				message = 'Rate is required for Actual Travel.';
			} else if (line.lineType === LINE_TYPE.PARTS && !line.id && !line.product2Id) {
				message = 'Select a product for each Parts line.';
			} else if (line.lineType === LINE_TYPE.EXPENSE && !line.expenseType) {
				message = 'Expense Type is required for Expense lines.';
			}
			if (message) {
				this.activeTab = Object.keys(TAB_LINE_TYPES).find((tab) => TAB_LINE_TYPES[tab].includes(line.lineType));
				this.editingKey = line.key;
				return message;
			}
		}
		return undefined;
	}

	// ---------------------------------------------------------------- utils

	formatCurrency(value) {
		if (value === null || value === undefined) {
			return '';
		}
		try {
			return new Intl.NumberFormat(undefined, {
				style: 'currency',
				currency: this.h.currencyIsoCode || 'USD'
			}).format(value);
		} catch (e) {
			return String(value);
		}
	}

	toast(title, message, variant) {
		this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
	}

	/**
	 * @param {*} error Apex, LDS or GraphQL error
	 * @param {string} fallback Message when the error has none (Field Service mobile, quote not synced)
	 * @return {string} Message to show
	 */
	reduceError(error, fallback = 'Something went wrong. Close the editor and try again.') {
		if (Array.isArray(error?.body)) {
			const messages = error.body.map((e) => e?.message).filter(Boolean);
			return messages.length ? messages.join(', ') : fallback;
		}
		return error?.body?.message || error?.message || fallback;
	}
}