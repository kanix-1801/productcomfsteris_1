/**
 * @description Work Order debrief LWC (woDebriefIMSchildWO) for Field Service technicians.
 * @author Uptima Development Team
 */
import { LightningElement, api, track, wire } from 'lwc';
import { gql, graphql, refreshGraphQL } from 'lightning/uiGraphQLApi';
import {
	updateRecord,
	createRecord,
	deleteRecord,
	getRecord,
	notifyRecordUpdateAvailable,
	createContentDocumentAndVersion
} from 'lightning/uiRecordApi';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';
import { getObjectInfo, getObjectInfos, getPicklistValues } from 'lightning/uiObjectInfoApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import LightningAlert from 'lightning/alert';
import LightningPrompt from 'lightning/prompt';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getBarcodeScanner } from 'lightning/mobileCapabilities';
import USER_ID from '@salesforce/user/Id';
import saveLaborLine from '@salesforce/apex/WoDebriefIMSchildWOController.saveLaborLine';
import getTrayPlanners from '@salesforce/apex/WoDebriefIMSchildWOController.getTrayPlanners';
import getDepartmentsForAccount from '@salesforce/apex/WoDebriefIMSchildWOController.getDepartmentsForAccount';
import listMobileDevicePictures from '@salesforce/apex/WoDebriefIMSchildWOController.listMobileDevicePictures';
import getMobileDevicePictureData from '@salesforce/apex/WoDebriefIMSchildWOController.getMobileDevicePictureData';
import saveMobileDevicePictureWithDetails from '@salesforce/apex/WoDebriefIMSchildWOController.saveMobileDevicePictureWithDetails';
import deleteMobileDevicePicture from '@salesforce/apex/WoDebriefIMSchildWOController.deleteMobileDevicePicture';
import getCompletionCheck from '@salesforce/apex/WoDebriefIMSchildWOController.getCompletionCheck';
import completeChildWorkOrder from '@salesforce/apex/WoDebriefIMSchildWOController.completeChildWorkOrder';
import WOLI_OBJECT from '@salesforce/schema/WorkOrderLineItem';
import CONTENT_DOCUMENT_OBJECT from '@salesforce/schema/ContentDocument';
import CONTENT_VERSION_OBJECT from '@salesforce/schema/ContentVersion';
import CONTENT_DOCUMENT_LINK_OBJECT from '@salesforce/schema/ContentDocumentLink';
import WOLI_WORKORDERID from '@salesforce/schema/WorkOrderLineItem.WorkOrderId';
import WOLI_LINETYPE from '@salesforce/schema/WorkOrderLineItem.LineType__c';
import WOLI_ASSIGNED_RES from '@salesforce/schema/WorkOrderLineItem.AssignedResource__c';
import WOLI_WORKTYPE from '@salesforce/schema/WorkOrderLineItem.WorkTypeId';
import WOLI_STARTDATE from '@salesforce/schema/WorkOrderLineItem.StartDate';
import WOLI_ENDDATE from '@salesforce/schema/WorkOrderLineItem.EndDate';
import WOLI_DURATION from '@salesforce/schema/WorkOrderLineItem.Duration';
import WOLI_PRODUCT_CODE from '@salesforce/schema/WorkOrderLineItem.ProductCode__c';
import WOLI_REPAIRCODE from '@salesforce/schema/WorkOrderLineItem.RepairCode__c';
import WOLI_UNIT_QTY from '@salesforce/schema/WorkOrderLineItem.UnitQty__c';
import WOLI_BILLING_TYPE from '@salesforce/schema/WorkOrderLineItem.BillingType__c';
import WOLI_DISCOUNT from '@salesforce/schema/WorkOrderLineItem.Discount';
import WOLI_PRODUCT_DESCRIPTION from '@salesforce/schema/WorkOrderLineItem.ProductDescription__c';
import WOLI_INSTRUMENT from '@salesforce/schema/WorkOrderLineItem.Instrument__c';
import WOLI_DEVICE_TYPE from '@salesforce/schema/WorkOrderLineItem.DeviceType__c';
import WOLI_REPAIR_LEVEL from '@salesforce/schema/WorkOrderLineItem.RepairLevel__c';
import WOLI_MODEL from '@salesforce/schema/WorkOrderLineItem.Model__c';
import WOLI_SERIAL_NUMBER from '@salesforce/schema/WorkOrderLineItem.SerialNumber__c';
import WOLI_DEPARTMENT from '@salesforce/schema/WorkOrderLineItem.Department__c';
import WOLI_SEND_TO_REPAIR_CENTER from '@salesforce/schema/WorkOrderLineItem.SendToRepairCenter__c';
import WOLI_REPORTED_PROBLEM from '@salesforce/schema/WorkOrderLineItem.ReportedProblem__c';
import WOLI_ADDITIONAL_SERVICES from '@salesforce/schema/WorkOrderLineItem.AdditionalServices__c';
import WOLI_INSULATION from '@salesforce/schema/WorkOrderLineItem.InsulationPowderCoating__c';
import WOLI_REPLACED_WITH_IXCHANGE from '@salesforce/schema/WorkOrderLineItem.ReplacedWithIXchange__c';
import WOLI_PARTS_SOURCE from '@salesforce/schema/WorkOrderLineItem.PartsSource__c';
import WOLI_DESCRIPTION from '@salesforce/schema/WorkOrderLineItem.Description';
import WOLI_PRODUCT_ITEM from '@salesforce/schema/WorkOrderLineItem.ProductItem__c';
import WOLI_PRODUCT from '@salesforce/schema/WorkOrderLineItem.Product__c';
import WOLI_PART_DESCRIPTION from '@salesforce/schema/WorkOrderLineItem.PartDescription__c';
import WOLI_ALLOWED_UNIT from '@salesforce/schema/WorkOrderLineItem.AllowedUnit__c';
import WOLI_RETURNABLE from '@salesforce/schema/WorkOrderLineItem.Returnable__c';
import WOLI_USAGES_EXCEPTION from '@salesforce/schema/WorkOrderLineItem.UsagesException__c';
import WOLI_QUANTITY from '@salesforce/schema/WorkOrderLineItem.Quantity';
import WOLI_PRICEBOOK_ENTRY from '@salesforce/schema/WorkOrderLineItem.PricebookEntryId';
import WOLI_RECORD_TYPE from '@salesforce/schema/WorkOrderLineItem.RecordTypeId';
import WO_TOTAL_SERVICED_INSTRUMENTS from '@salesforce/schema/WorkOrder.TotalServicedInstruments__c';
import WO_STATUS from '@salesforce/schema/WorkOrder.Status';
import WOLI_LINE_STATUS from '@salesforce/schema/WorkOrderLineItem.Status';

const PARTS_SOURCE_TRUNK = 'TrunkStock';
const PARTS_SOURCE_CUSTOMER = 'Customer Part';
const PARTS_SOURCE_ON_ORDER = 'On Order';
const PARTS_SOURCE_INVENTORY_ISSUE = 'Inventory Issue';
const WO_STATUS_IN_PROGRESS = 'In Progress';
const WO_CLOSED_STATUSES = new Set(['Completed', 'Closed', 'Canceled', 'Cannot Complete']);
const WOLI_STATUS_CANCELED = 'Canceled';
const WOLI_STATUS_COMPLETED = 'Completed';
const WOLI_STATUS_IN_PROGRESS = 'In Progress';
const HIGHLIGHT_BILLING_TYPES = new Set(['Courtesy', 'Warranty', 'SVC Warranty']);
const REPAIR_CENTER_SERVICE_TEXT = 'forward to national repair center for service';
const OBR_PRODUCT_CODE_PATTERN = /OBR/i;
const MOBILE_DEVICE_PICTURE_TITLE = 'Mobile Device Picture';
/** Matches WoDebriefIMSchildWOController.MICROSCOPE_PICTURE_TITLE. Listed and counted like a Mobile Device Picture. */
const MICROSCOPE_PICTURE_TITLE = 'Microscope Picture';
/** Matches WoDebriefIMSchildWOController.REQUIRED_PICTURES_PER_LINE. */
const REQUIRED_PICTURES_PER_LINE = 2;
/** Matches WoDebriefIMSchildWOController.MOBILE_DEVICE_PICTURE_MARKER. The server counts files with this description. */
const MOBILE_DEVICE_PICTURE_MARKER = 'MobileDevicePicture';
/** Matches WoDebriefIMSchildWOController.PICTURE_DETAILS_SEPARATOR. */
const PICTURE_DETAILS_SEPARATOR = '|';
/** The details travel in the 1000 character file description when the picture is saved offline. */
const PICTURE_COMMENT_MAX_LENGTH = 800;
const PICTURE_CATEGORY_OPTIONS = [
	{ label: 'Beyond Repair', value: 'Beyond Repair' },
	{ label: 'Care and Handling', value: 'Care and Handling' },
	{ label: 'Extensive Repair', value: 'Extensive Repair' },
	{ label: 'Technical Excellence', value: 'Technical Excellence' }
];
const BEFORE_AFTER_OPTIONS = [
	{ label: 'Before', value: 'Before' },
	{ label: 'After', value: 'After' }
];
const INSULATION_POWDER_COATING_OPTIONS = [
	'Black', 'Blue', 'Light Blue', 'Navy Blue', 'Green', 'Yellow', 'Orange',
	'Light Gray', 'Purple', 'Salmon Orange', 'Lavender', 'Brown', 'Red'
].map(value => ({ label: value, value }));

import PRODUCT2_PRODUCT_TYPE from '@salesforce/schema/Product2.ProductType__c';

import PC_OBJECT from '@salesforce/schema/ProductConsumed';
import PC_WORKORDER from '@salesforce/schema/ProductConsumed.WorkOrderId';
import PC_PRODUCTITEM from '@salesforce/schema/ProductConsumed.ProductItemId';
import PC_QUANTITY from '@salesforce/schema/ProductConsumed.QuantityConsumed';
import PC_DESCRIPTION from '@salesforce/schema/ProductConsumed.Description';
import PC_RETURNABLE from '@salesforce/schema/ProductConsumed.Returnable__c';
import PC_SERVICE_RESOURCE from '@salesforce/schema/ProductConsumed.ServiceResource__c';
import PC_WORKORDER_LINE_ITEM from '@salesforce/schema/ProductConsumed.WorkOrderLineItemId';

const PARTS_CONSUMED_RELATED_LIST_ID = 'ProductsConsumed';
const PARTS_CONSUMED_RELATED_LIST_FIELDS = [
	'ProductConsumed.Id',
	'ProductConsumed.QuantityConsumed',
	'ProductConsumed.Description',
	'ProductConsumed.ProductItemId',
	'ProductConsumed.Product2Id',
	`ProductConsumed.${PC_RETURNABLE.fieldApiName}`,
	`ProductConsumed.${PC_SERVICE_RESOURCE.fieldApiName}`,
	'ProductConsumed.WorkOrderLineItemId'
];

const PRODUCT_BY_CODE_QUERY = gql`
	query FindProductByCode($productCode: String) {
		uiapi {
			query {
				Product2(
					where: {
						and: [
							{ ProductCode: { eq: $productCode } }
							{ IsActive: { eq: true } }
						]
					}
					first: 5
				) {
					edges {
						node {
							Id
							ProductCode { value }
							Name { value }
							Description { value }
							IsReturnable__c { value }
						}
					}
				}
			}
		}
	}
`;

const PRODUCT_BY_CODE_TYPE_QUERY = gql`
	query FindProductByCodeAndType($productCode: String, $productType: Picklist) {
		uiapi {
			query {
				Product2(
					where: {
						and: [
							{ ProductCode: { eq: $productCode } }
							{ ProductType__c: { eq: $productType } }
							{ IsActive: { eq: true } }
						]
					}
					first: 5
				) {
					edges {
						node {
							Id
							ProductCode { value }
							Name { value }
							Description { value }
							IsReturnable__c { value }
						}
					}
				}
			}
		}
	}
`;

const PART_PRODUCT_BY_CODE_QUERY = gql`
	query FindPartProductByCode($productCode: String) {
		uiapi {
			query {
				Product2(
					where: {
						and: [
							{ ProductCode: { eq: $productCode } }
							{ ProductType__c: { eq: "Part" } }
						]
					}
					first: 1
				) {
					edges {
						node {
							Id
							ProductCode { value }
							Name { value }
							Description { value }
						}
					}
				}
			}
		}
	}
`;

const PRICEBOOK_ENTRY_QUERY = gql`
	query GetPricebookEntryForDeviceType($pricebook2Id: ID, $product2Id: ID) {
		uiapi {
			query {
				PricebookEntry(
					where: {
						and: [
							{ Pricebook2Id: { eq: $pricebook2Id } }
							{ Product2Id: { eq: $product2Id } }
							{ IsActive: { eq: true } }
						]
					}
					first: 20
				) {
					edges {
						node {
							Id
							CurrencyIsoCode { value }
						}
					}
				}
			}
		}
	}
`;

const SERVICE_CODES_QUERY = gql`
	query GetServiceCodesForDeviceType(
		$likePattern: String,
		$itemNumberLike: String,
		$beyondRepairLike: String,
		$beyondRepairItemNumberLike: String
	) {
		uiapi {
			query {
				Product2(
					where: {
						and: [
							{ ProductType__c: { eq: "Service Code" } }
							{ IsActive: { eq: true } }
							{
								or: [
									{ ProductCode: { like: $likePattern } }
									{ ProductCode: { like: $itemNumberLike } }
									{ BaseServiceCode__c: { like: $likePattern } }
									{ ProductCode: { like: $beyondRepairLike } }
									{ ProductCode: { like: $beyondRepairItemNumberLike } }
									{ BaseServiceCode__c: { like: $beyondRepairLike } }
								]
							}
						]
					}
					first: 200
				) {
					edges {
						node {
							Id
							ProductCode { value }
							Name { value }
							Description { value }
						}
					}
				}
			}
		}
	}
`;

const CHILD_ACCESS_QUERY = gql`
	query GetWorkOrderChildAccess($workOrderId: ID) {
		uiapi {
			query {
				WorkOrder(
					where: { Id: { eq: $workOrderId } }
					first: 1
				) {
					edges {
						node {
							Id
							WorkOrderNumber { value }
							ParentWorkOrderId {
								value
								displayValue
							}
							ParentWorkOrder {
								WorkOrderNumber { value }
							}
						}
					}
				}
			}
		}
	}
`;

const WORK_ORDER_QUERY = gql`
	query GetWorkOrderDebriefIMSChildWO($workOrderId: ID) {
		uiapi {
			query {
				WorkOrder(
					where: { Id: { eq: $workOrderId } }
					first: 1
				) {
					edges {
						node {
							Id
							WorkOrderNumber { value }
							Status { value }
							Account {
								Id
								Name { value }
							}
							Asset {
								Id
								Name { value }
								SerialNumber { value }
								Department__c {
									value
									displayValue
								}
							}
							ParentWorkOrderId {
								value
								displayValue
							}
							ParentWorkOrder {
								WorkOrderNumber { value }
							}
							TotalServicedInstruments__c { value }
							CurrencyIsoCode { value }
							Pricebook2Id { value }
							WorkTypeId { value }
							WorkType {
								Id
								Name { value }
							}
							WorkOrderLineItems(first: 200) {
								edges {
									node {
										Id
										LineItemNumber { value }
										Status { value }
										LineType__c { value }
										WorkTypeId { value }
										WorkType {
											Id
											Name { value }
										}
										StartDate { value }
										EndDate { value }
										Duration { value }
										UnitQty__c { value }
										BillingType__c { value }
										Discount { value }
										Description { value }
										AssignedResource__c { value }
										AssignedResource__r {
											Id
											Name { value }
										}
										Instrument__c { value }
										Instrument__r {
											Id
											ProductCode { value }
											Name { value }
											Description { value }
											BaseServiceCode__c { value }
											ServiceCode__c { value }
										}
										DeviceType__c { value }
										RepairLevel__c { value }
										Model__c { value }
										Quantity { value }
										PricebookEntryId { value }
										Product2Id { value }
										Product2 {
											Id
											ProductCode { value }
											Name { value }
											BaseServiceCode__c { value }
										}
										ProductCode__c { value }
										ProductDescription__c { value }
										ProductItem__c { value }
										Product__c { value }
										PartDescription__c { value }
										AllowedUnit__c { value }
										Returnable__c { value }
										UsagesException__c { value }
										RepairCode__c { value }
										PartsSource__c { value }
										RepairCode__r {
											Id
											ProductCode { value }
											Description { value }
											Name { value }
											ServiceCode__c { value }
										}
									}
								}
							}
							ProductsConsumed(first: 200) {
								edges {
									node {
										Id
										QuantityConsumed { value }
										Description { value }
										ProductItemId { value }
										Product2Id { value }
										Returnable__c { value }
										ServiceResource__c { value }
										WorkOrderLineItemId { value }
										WorkOrderLineItem {
											PartsSource__c { value }
										}
										ProductItem {
											Id
											ProductName { value }
										}
										Product2 {
											Id
											Name { value }
											IsReturnable__c { value }
										}
									}
								}
							}
						}
					}
				}
			}
		}
	}
`;

const REPAIR_CENTER_LINES_QUERY = gql`
	query GetRepairCenterLineFields($workOrderId: ID) {
		uiapi {
			query {
				WorkOrderLineItem(
					where: { WorkOrderId: { eq: $workOrderId } }
					first: 200
				) {
					edges {
						node {
							Id
							SerialNumber__c { value }
							Model__c { value }
							Department__c { value }
							ReportedProblem__c { value }
							AdditionalServices__c { value }
							InsulationPowderCoating__c { value }
							SendToRepairCenter__c { value }
							ReplacedWithIXchange__c { value }
						}
					}
				}
			}
		}
	}
`;

const CURRENT_USER_SERVICE_RESOURCE_QUERY = gql`
	query GetCurrentUserServiceResource($userId: ID) {
		uiapi {
			query {
				ServiceResource(
					where: {
						and: [
							{ RelatedRecordId: { eq: $userId } }
							{ IsActive: { eq: true } }
						]
					}
					first: 1
				) {
					edges {
						node {
							Id
							Name { value }
						}
					}
				}
			}
		}
	}
`;

const SERVICE_RESOURCE_NAMES_QUERY = gql`
	query GetServiceResourceNames($resourceIds: [ID]) {
		uiapi {
			query {
				ServiceResource(
					where: { Id: { in: $resourceIds } }
					first: 50
				) {
					edges {
						node {
							Id
							Name { value }
						}
					}
				}
			}
		}
	}
`;

const TAB_DEFS = [
	{ key: 'Time', label: 'Time', addLabel: '+ Add Time Line', type: null, canAdd: true, schema: 'time' },
	{
		key: 'Instrument',
		label: 'Instrument',
		addLabel: '+ Add Instrument Line',
		type: 'Instrument',
		canAdd: true,
		schema: 'instrument'
	},
	{ key: 'Parts', label: 'Parts', addLabel: '+ Add Parts Line', type: 'Parts', canAdd: true, schema: 'parts' }
];

const TIME_LINE_TYPES = new Set(['Travel', 'Labor']);
const BEYOND_REPAIR_PATTERN = /beyond\s*repair/i;
const SERVICE_CODE_PRODUCT_TYPE = 'Service Code';
const SERVICE_ASSET_PRODUCT_TYPE = 'Service Asset';
const PART_PRODUCT_TYPE = 'Part';
const INSTRUMENT_LINE_TYPE = 'Instrument';
const PRODUCT_SERVICED_LINE_TYPE = 'Product Serviced';
const INSTRUMENT_TAB_LINE_TYPES = new Set([INSTRUMENT_LINE_TYPE, PRODUCT_SERVICED_LINE_TYPE]);
const PRODUCT_SERVICED_RECORD_TYPE = 'ProductServiced';

const LINE_TYPE_TO_SCHEMA = {
	Travel: 'travel',
	Labor: 'labor',
	Instrument: 'instrument',
	[PRODUCT_SERVICED_LINE_TYPE]: 'instrument',
	Parts: 'parts'
};

const TIME_LINE_TYPE_OPTIONS = [
	{ label: 'Travel', value: 'Travel' },
	{ label: 'Labor', value: 'Labor' }
];

const PARTS_SOURCE_OPTIONS = [
	{ label: 'Trunk', value: PARTS_SOURCE_TRUNK },
	{ label: 'Customer Part', value: PARTS_SOURCE_CUSTOMER },
	{ label: 'On Order', value: PARTS_SOURCE_ON_ORDER },
	{ label: 'Inventory Issue', value: PARTS_SOURCE_INVENTORY_ISSUE }
];

/**
 * @description Keeps Part's Source options in debrief display order.
 * @param {Array<{label: String, value: String}>} options Picklist options
 * @return {Array<{label: String, value: String}>}
 */
function sortPartsSourceOptions(options) {
	const order = new Map(PARTS_SOURCE_OPTIONS.map((option, index) => [option.value, index]));
	return [...(options ?? [])].sort((a, b) => {
		const aIndex = order.has(a.value) ? order.get(a.value) : Number.MAX_SAFE_INTEGER;
		const bIndex = order.has(b.value) ? order.get(b.value) : Number.MAX_SAFE_INTEGER;
		if (aIndex !== bIndex) return aIndex - bIndex;
		return (a.label || '').localeCompare(b.label || '');
	});
}

const BILLING_TYPE_BILLABLE = 'Billable';
const BILLING_TYPE_COURTESY = 'Courtesy';
const BILLING_TYPE_WARRANTY = 'Warranty';
const BILLING_TYPE_NON_BILLABLE = 'Non-Billable';
const BILLING_TYPE_OPTIONS = [
	{ label: 'Contract', value: 'Contract' },
	{ label: 'Warranty', value: 'Warranty' },
	{ label: 'SVC Warranty', value: 'SVC Warranty' },
	{ label: 'Billable', value: BILLING_TYPE_BILLABLE },
	{ label: 'Courtesy', value: BILLING_TYPE_COURTESY },
	{ label: 'Non-Billable', value: BILLING_TYPE_NON_BILLABLE }
];

const TYPE_TO_DEF = {
	Travel: { key: 'Time', type: 'Travel', schema: 'travel' },
	Labor: { key: 'Time', type: 'Labor', schema: 'labor' },
	Instrument: { key: 'Instrument', type: 'Instrument', schema: 'instrument' },
	[PRODUCT_SERVICED_LINE_TYPE]: { key: 'Instrument', type: PRODUCT_SERVICED_LINE_TYPE, schema: 'instrument' },
	Parts: { key: 'Parts', type: 'Parts', schema: 'parts' }
};

const TAB_KEY_TO_DEF = TAB_DEFS.reduce((acc, d) => {
	acc[d.key] = d;
	return acc;
}, {});

const EMPTY_ADD_FORM_VISIBILITY = () =>
	TAB_DEFS.filter(d => d.canAdd).reduce((acc, d) => { acc[d.key] = false; return acc; }, {});

const EMPTY_TAB_SEARCH_TERMS = () =>
	TAB_DEFS.reduce((acc, d) => { acc[d.key] = ''; return acc; }, {});

let _tempIdSeq = 0;

/**
 * @description WoDebriefIMSchildWO Lightning Web Component.
 * @author Uptima Development Team
 */
export default class WoDebriefIMSchildWO extends LightningElement {
	@api recordId;

	graphqlResult;
	repairCenterGraphqlResult;
	childAccessGraphqlResult;
	partsListResult;

	_workOrder = null;
	_accessWorkOrder = null;
	_serverLines = [];
	_serverPartsFromGraphql = [];
	_serverPartsFromRelatedList = [];
	_serverPartsConsumed = [];
	_serverProductsRequired = [];
	_serverExpenses = [];
	_pendingEdits = {};
	_pendingDeletes = {};
	_pendingAdds = [];
	editStateMap = {};
	_mobilePicturesByRecordId = {};
	_unsavedPicturesByRecordId = {};
	_mobilePictureRequest = 0;
	_savingPicture = false;
	mobilePictureVersion = 0;
	showPictureDetails = false;
	pictureDetailsDraft = { category: '', beforeAfter: '', comment: '' };
	pictureDetailsError = '';
	_pendingPictureCapture = null;
	pictureCategoryOptions = PICTURE_CATEGORY_OPTIONS;
	beforeAfterOptions = BEFORE_AFTER_OPTIONS;
	pictureCommentMaxLength = PICTURE_COMMENT_MAX_LENGTH;
	showPictureReview = false;
	reviewPictureUrl = '';
	reviewPictureLoading = false;
	reviewPicture = null;
	_pictureDataPromises = {};
	showMicroscopeCamera = false;
	_microscopeTarget = null;

	_repairCodeNameById = {};
	_repairCodeProductCodeById = {};
	_repairCodeDescriptionById = {};
	_repairCodeLookupId;
	_baseServiceCodeByProduct2Id = {};
	_repairCodeOptionsByProduct2Id = {};
	_repairCodeLoadingByProduct2Id = {};
	_repairCodeLoadTokenByProduct2Id = {};
	_repairCodeLoadCounter = 0;
	@track repairCodeUiVersion = 0;
	_laborProductLabelById = {};
	_laborPartDescriptionById = {};
	_laborPartProductCodeById = {};
	_product2IdByPartProductCode = {};
	_laborProductLookupId;
	_locationIdByServiceResourceId = {};
	_serviceResourceLocationLookupId;
	_productItemLookupId;
	_product2LookupId;
	_serviceCodeQueryProduct2Id;
	_pbeQueryProduct2Id;
	_pricebookEntryIdByProduct2Id = {};
	_product2IdByProductItemId = {};
	_isReturnableByProductItemId = {};
	_productItemNameByProductItemId = {};
	_productNameByProduct2Id = {};
	_productCodeByProduct2Id = {};
	_partDescriptionByProduct2Id = {};
	_isReturnableByProduct2Id = {};
	_partsSourceByWoliId = {};
	_serviceResourceNameById = {};
	_serviceResourceIdsForLookup;
	_productMetaById = {};
	@track productMetaVersion = 0;

	_currentUserServiceResourceId = null;
	_currentUserServiceResourceName = '';
	/** @description Default WorkOrderLineItem record type for picklist wires. */
	woliDefaultRecordTypeId;
	_productServicedRecordTypeId = null;
	/** @description PartsSource__c picklist options from the WOLI field. */
	partsSourcePicklistOptions = [];
	/** @description BillingType__c picklist options from the WOLI field. */
	billingTypePicklistOptions = [];
	trayPlannerRows = [];
	showTrayPlanner = false;
	/** @description Header status shown before the Work Order update returns. */
	@track _pendingWorkOrderStatus;
	/** @description Status to put back if the new instrument line is removed before save. */
	_statusBeforeInProgress;
	/** @description Last status sent to the Work Order, so the same write is not sent twice. */
	_queuedWorkOrderStatus;
	/** @description Keeps the header on In Progress until the server refresh shows it. */
	_holdInProgressStatus = false;
	_statusWriteChain = Promise.resolve();
	_accountDepartmentOptions = [];
	_insulationPicklistOptions = [];
	_repairCenterByLineId = {};
	@track repairCenterUiVersion = 0;

	tabSearchTerms = EMPTY_TAB_SEARCH_TERMS();
	showAddForm = EMPTY_ADD_FORM_VISIBILITY();
	addFormState = {};
	editErrors = {};
	addErrors = {};
	_saving = false;
	_completingWorkOrder = false;
	activeTab = 'Time';

	isOffline = !navigator.onLine;
	_onlineHandler = () => { this.isOffline = false; };
	_offlineHandler = () => { this.isOffline = true; };
	/**
	 * @description Lifecycle hook invoked when the component is inserted into the DOM.
	 */
	connectedCallback() {
		window.addEventListener('online', this._onlineHandler);
		window.addEventListener('offline', this._offlineHandler);
		this.addFormState = this._emptyAddFormState();
	}

	/**
	 * @description Lifecycle hook invoked when the component is removed from the DOM.
	 */
	disconnectedCallback() {
		window.removeEventListener('online', this._onlineHandler);
		window.removeEventListener('offline', this._offlineHandler);
	}

	/**
	 * @description Tray Planner rows for the Work Order asset.
	 */
	@wire(getTrayPlanners, { assetId: '$trayPlannerAssetId' })
	wiredTrayPlanners({ data }) {
		this.trayPlannerRows = Array.isArray(data) ? data : [];
	}

	/**
	 * @description Departments on the Work Order account for the repair-center form.
	 */
	@wire(getDepartmentsForAccount, { accountId: '$repairCenterAccountId' })
	wiredDepartments({ data }) {
		this._accountDepartmentOptions = (data || [])
			.filter(row => row?.id)
			.map(row => ({ label: row.name || row.id, value: row.id }));
	}

	/**
	 * @description Insulation / Powder Coating values from the work order line field.
	 */
	@wire(getPicklistValues, {
		recordTypeId: '$woliDefaultRecordTypeId',
		fieldApiName: WOLI_INSULATION
	})
	wiredInsulationPicklist({ data }) {
		if (data?.values?.length) {
			this._insulationPicklistOptions = data.values.map(({ label, value }) => ({ label, value }));
		}
	}

	/**
	 * @description Saved repair-center values. Kept off the main query so a field-access
	 *              error does not blank the rest of the debrief.
	 */
	@wire(graphql, { query: REPAIR_CENTER_LINES_QUERY, variables: '$queryVariables' })
	wiredRepairCenterLines(result) {
		this.repairCenterGraphqlResult = result;
		const data = result?.data;
		const edges = data?.uiapi?.query?.WorkOrderLineItem?.edges ?? [];
		if (!data) return;
		const byId = {};
		for (const edge of edges) {
			const node = edge?.node;
			if (!node?.Id) continue;
			byId[node.Id] = {
				serialNumber: node.SerialNumber__c?.value ?? '',
				model: node.Model__c?.value ?? '',
				departmentId: node.Department__c?.value ?? null,
				reportedProblem: node.ReportedProblem__c?.value ?? '',
				additionalServices: !!node.AdditionalServices__c?.value,
				insulationPowderCoating: node.InsulationPowderCoating__c?.value ?? '',
				sendToRepairCenter: !!node.SendToRepairCenter__c?.value,
				replacedWithIXchange: !!node.ReplacedWithIXchange__c?.value
			};
		}
		this._repairCenterByLineId = byId;
		this.repairCenterUiVersion += 1;
	}

	/**
	 * @description File object metadata, needed to save pictures while the device is offline.
	 */
	@wire(getObjectInfos, {
		objectApiNames: [CONTENT_DOCUMENT_OBJECT, CONTENT_VERSION_OBJECT, CONTENT_DOCUMENT_LINK_OBJECT]
	})
	fileObjectInfos;

	/**
	 * @description Same parent lookup Site Visit uses. Kept separate so the debrief query cannot skip the check.
	 */
	@wire(graphql, {
		query: CHILD_ACCESS_QUERY,
		variables: '$queryVariables'
	})
	wiredChildAccess(result) {
		this.childAccessGraphqlResult = result;
		if (result.data) {
			const woEdge = result.data.uiapi.query.WorkOrder.edges[0];
			if (woEdge) {
				this._accessWorkOrder = woEdge.node;
			}
		}
	}

	@wire(graphql, { query: WORK_ORDER_QUERY, variables: '$queryVariables' })
	wiredData(result) {
		this.graphqlResult = result;
		if (result.data) {
			const woEdge = result.data.uiapi.query.WorkOrder.edges[0];
			if (woEdge) {
				this._workOrder = this._workOrderFromWire(woEdge.node);
				this._serverLines = (woEdge.node.WorkOrderLineItems?.edges ?? []).map(e => e.node);
				this._serverPartsFromGraphql = (woEdge.node.ProductsConsumed?.edges ?? []).map(e => e.node);
				this._seedRepairCodeCache(this._serverLines);
				this._seedPartsSourceCacheFromLines(this._serverLines);
				this._seedProductItemNameCacheFromWoliLines(this._serverLines);
				this._seedLaborProductLabelCache(this._serverLines);
				this._seedInstrumentProductMetaCache(this._serverLines);
				this._prefetchInstrumentServiceCodes(this._serverLines);
				this._seedReturnableCacheFromParts(this._serverPartsFromGraphql);
				this._seedProductItemNameCacheFromParts(this._serverPartsFromGraphql);
				this._refreshServiceResourceNameLookups(this._serverPartsFromGraphql);
				this._rebuildServerPartsConsumed();
				this._defaultAddFormWorkTypeFromHeader();
				this._loadMobileDevicePictures();
			}
		}
	}

	/**
	 * @description Wire adapter: Service Codes whose Item Number matches the Device Type base.
	 */
	@wire(graphql, { query: SERVICE_CODES_QUERY, variables: '$serviceCodeQueryVariables' })
	wiredServiceCodesForDeviceType(result) {
		const product2Id = this._serviceCodeQueryProduct2Id;
		if (!product2Id) return;
		if (result?.errors) {
			this._setRepairCodesForProduct(
				product2Id,
				this._baseServiceCodeByProduct2Id[product2Id] || '',
				[]
			);
			return;
		}
		if (!result?.data) return;
		const edges = result.data?.uiapi?.query?.Product2?.edges ?? [];
		const options = this._cacheServiceCodeNodes(edges.map(edge => edge?.node));
		this._setRepairCodesForProduct(
			product2Id,
			this._baseServiceCodeByProduct2Id[product2Id] || '',
			options
		);
	}

	/**
	 * @description Wire adapter: Pricebook Entry for the selected Device Type.
	 */
	@wire(graphql, { query: PRICEBOOK_ENTRY_QUERY, variables: '$pricebookEntryQueryVariables' })
	wiredPricebookEntryForDeviceType(result) {
		const product2Id = this._pbeQueryProduct2Id;
		if (!product2Id || !result?.data) return;
		const edges = result.data?.uiapi?.query?.PricebookEntry?.edges ?? [];
		const currencyIso = this._workOrder?.CurrencyIsoCode?.value;
		const match = currencyIso
			? edges.find((edge) => edge?.node?.CurrencyIsoCode?.value === currencyIso) ?? edges[0]
			: edges[0];
		if (!match?.node?.Id) return;
		this._pricebookEntryIdByProduct2Id = {
			...this._pricebookEntryIdByProduct2Id,
			[product2Id]: match.node.Id
		};
	}

	/**
	 * @description Wire: WorkOrderLineItem object info for PartsSource__c picklist values.
	 */
	@wire(getObjectInfo, { objectApiName: WOLI_OBJECT })
	wiredWoliObjectInfo({ data, error }) {
		if (error) {
			// eslint-disable-next-line no-console
			console.error('woDebriefIMSchildWO getObjectInfo WorkOrderLineItem failed', error);
			return;
		}
		if (data?.defaultRecordTypeId) {
			this.woliDefaultRecordTypeId = data.defaultRecordTypeId;
		}
		const infos = data?.recordTypeInfos ? Object.values(data.recordTypeInfos) : [];
		const productServiced = infos.find(rt =>
			rt?.available
			&& (
				rt.developerName === PRODUCT_SERVICED_RECORD_TYPE
				|| rt.name === PRODUCT_SERVICED_LINE_TYPE
			)
		);
		this._productServicedRecordTypeId = productServiced?.recordTypeId ?? null;
	}

	@wire(getPicklistValues, {
		recordTypeId: '$woliDefaultRecordTypeId',
		fieldApiName: WOLI_PARTS_SOURCE
	})
	wiredPartsSourcePicklist({ data, error }) {
		if (error) {
			// eslint-disable-next-line no-console
			console.error('woDebriefIMSchildWO getPicklistValues PartsSource__c failed', error);
			return;
		}
		if (data?.values) {
			this.partsSourcePicklistOptions = sortPartsSourceOptions(
				data.values.map(({ label, value }) => ({ label, value }))
			);
		}
	}

	@wire(getPicklistValues, {
		recordTypeId: '$woliDefaultRecordTypeId',
		fieldApiName: WOLI_BILLING_TYPE
	})
	wiredBillingTypePicklist({ data, error }) {
		if (error) {
			// eslint-disable-next-line no-console
			console.error('woDebriefIMSchildWO getPicklistValues BillingType__c failed', error);
			return;
		}
		if (data?.values) {
			this.billingTypePicklistOptions = data.values.map(({ label, value }) => ({ label, value }));
		}
	}

	/**
	 * @description Wire adapter handler: Parts Related.
	 */
	@wire(getRelatedListRecords, {
		parentRecordId: '$recordId',
		relatedListId: PARTS_CONSUMED_RELATED_LIST_ID,
		fields: PARTS_CONSUMED_RELATED_LIST_FIELDS,
		pageSize: 200
	})
	wiredPartsRelated(result) {
		this.partsListResult = result;
		if (result.data) {
			this._serverPartsFromRelatedList = (result.data.records ?? []).map(r => this._normalizePartFromLds(r));
			this._seedProductItemNameCacheFromParts(this._serverPartsFromRelatedList);
			this._refreshServiceResourceNameLookups(this._serverPartsFromRelatedList);
			this._rebuildServerPartsConsumed();
		}
	}

	/**
	 * @description Wire adapter handler: Current User Service Resource.
	 */
	@wire(graphql, { query: CURRENT_USER_SERVICE_RESOURCE_QUERY, variables: '$currentUserQueryVariables' })
	wiredCurrentUserServiceResource(result) {
		const edge = result.data?.uiapi?.query?.ServiceResource?.edges?.[0];
		if (!edge) return;
		this._currentUserServiceResourceId = edge.node.Id;
		this._currentUserServiceResourceName = edge.node.Name?.value ?? '';
		if (this._currentUserServiceResourceId && this._currentUserServiceResourceName) {
			this._cacheServiceResourceName(
				this._currentUserServiceResourceId,
				this._currentUserServiceResourceName
			);
		}
		if (!this.addFormState.assignedResourceId && this._currentUserServiceResourceId) {
			this.addFormState = { ...this.addFormState, assignedResourceId: this._currentUserServiceResourceId };
		}
	}

	/**
	 * @description Wire adapter handler: Service Resource Location.
	 */
	@wire(getRecord, { recordId: '$_serviceResourceLocationLookupId', fields: ['ServiceResource.LocationId', 'ServiceResource.Name'] })
	wiredServiceResourceLocation({ data }) {
		if (!data) return;
		const srId = data.id;
		const locationId = data.fields?.LocationId?.value;
		const name = data.fields?.Name?.value;
		if (srId && locationId) {
			this._locationIdByServiceResourceId = { ...this._locationIdByServiceResourceId, [srId]: locationId };
		}
		if (srId && name) {
			this._cacheServiceResourceName(srId, name);
		}
	}

	/**
	 * @description Wire adapter handler: Service Resource Names.
	 */
	@wire(graphql, { query: SERVICE_RESOURCE_NAMES_QUERY, variables: '$serviceResourceQueryVariables' })
	wiredServiceResourceNames(result) {
		if (!result.data) return;
		for (const edge of result.data.uiapi.query.ServiceResource?.edges ?? []) {
			const id = edge.node.Id;
			const name = edge.node.Name?.value;
			if (id && name) this._cacheServiceResourceName(id, name);
		}
	}

	/**
	 * @description Wire adapter handler: Product Item.
	 */
	@wire(getRecord, {
		recordId: '$_productItemLookupId',
		fields: [
			'ProductItem.Product2Id',
			'ProductItem.ProductName',
			'ProductItem.Product2.IsReturnable__c',
			'ProductItem.Product2.ProductCode',
			'ProductItem.Product2.Description'
		]
	})
	wiredProductItem({ data }) {
		if (!data) return;
		const piId = data.id;
		const product2Id = data.fields?.Product2Id?.value;
		const productName = data.fields?.ProductName?.value;
		const product2Fields = data.fields?.Product2?.value?.fields;
		const isReturnable = product2Fields?.IsReturnable__c?.value;
		const productCode = product2Fields?.ProductCode?.value;
		const partDescription = product2Fields?.Description?.value;
		if (piId && product2Id) {
			this._product2IdByProductItemId = { ...this._product2IdByProductItemId, [piId]: product2Id };
		}
		if (piId && productName) {
			this._productItemNameByProductItemId = { ...this._productItemNameByProductItemId, [piId]: productName };
		}
		if (product2Id && productName) {
			this._productNameByProduct2Id = { ...this._productNameByProduct2Id, [product2Id]: productName };
		}
		if (product2Id && productCode != null) {
			this._productCodeByProduct2Id = { ...this._productCodeByProduct2Id, [product2Id]: productCode };
		}
		if (product2Id && partDescription != null) {
			this._partDescriptionByProduct2Id = { ...this._partDescriptionByProduct2Id, [product2Id]: partDescription };
		}
		if (product2Id && isReturnable !== undefined && isReturnable !== null) {
			this._isReturnableByProduct2Id = { ...this._isReturnableByProduct2Id, [product2Id]: isReturnable };
		}
		if (piId && isReturnable !== undefined && isReturnable !== null) {
			this._isReturnableByProductItemId = { ...this._isReturnableByProductItemId, [piId]: isReturnable };
			this._syncReturnableForProductItem(piId, isReturnable);
		}
		if (piId && (productCode != null || partDescription != null)) {
			this._syncProductDetailsForProductItem(piId, { productCode, partDescription });
		}
		this._seedProductItemNameCacheFromWoliLines(this._serverLines);
	}

	/**
	 * @description Wire adapter handler: Product2 details (Customer Stock).
	 */
	@wire(getRecord, {
		recordId: '$_product2LookupId',
		fields: [
			'Product2.Name',
			'Product2.ProductCode',
			'Product2.Description',
			'Product2.IsReturnable__c',
			'Product2.ServiceCode__c',
			'Product2.BaseServiceCode__c'
		]
	})
	wiredProduct2Details({ data }) {
		if (!data) return;
		const product2Id = data.id;
		const name = data.fields?.Name?.value;
		const serviceCode = data.fields?.ServiceCode__c?.value;
		const baseServiceCode = (data.fields?.BaseServiceCode__c?.value ?? '').trim();
		this._cacheProductMeta(product2Id, { name, serviceCode });
		this._applyProductDetails(product2Id, {
			name,
			productCode: data.fields?.ProductCode?.value,
			partDescription: data.fields?.Description?.value,
			isReturnable: data.fields?.IsReturnable__c?.value
		});
		this._baseServiceCodeByProduct2Id = {
			...this._baseServiceCodeByProduct2Id,
			[product2Id]: baseServiceCode
		};
		if (this._serviceCodeQueryProduct2Id === product2Id) {
			const loadedForBase = this._repairCodeLoadingByProduct2Id[product2Id]
				? this._loadedServiceCodesForBase(baseServiceCode)
				: null;
			if (!baseServiceCode) {
				this._setRepairCodesForProduct(product2Id, '', []);
			} else if (loadedForBase) {
				this._setRepairCodesForProduct(product2Id, baseServiceCode, loadedForBase);
			} else {
				this._serviceCodeQueryProduct2Id = product2Id;
				this.repairCodeUiVersion += 1;
			}
		}
	}

	/**
	 * @description Wire adapter handler: Repair Code Details.
	 */
	@wire(getRecord, {
		recordId: '$_repairCodeLookupId',
		fields: [
			'Product2.Name',
			'Product2.ProductCode',
			'Product2.Description',
			'Product2.ServiceCode__c'
		]
	})
	wiredRepairCodeDetails({ data }) {
		if (!data) return;
		const id = data.id;
		const name = data.fields?.Name?.value;
		const productCode = data.fields?.ProductCode?.value;
		const description = data.fields?.Description?.value;
		const serviceCode = data.fields?.ServiceCode__c?.value;
		this._cacheProductMeta(id, { name, serviceCode });
		this._cacheRepairCodeDetails(id, { name, productCode, description });
		this._syncRepairCodeDetailsForProduct(id, productCode, description);
	}

	/**
	 * @description Wire adapter handler: Labor Product Details.
	 */
	@wire(getRecord, {
		recordId: '$_laborProductLookupId',
		fields: ['Product2.Name', 'Product2.ProductCode', 'Product2.Description']
	})
	wiredLaborProductDetails({ data }) {
		if (!data) return;
		const id = data.id;
		const name = data.fields?.Name?.value ?? '';
		const productCode = data.fields?.ProductCode?.value ?? '';
		const description = data.fields?.Description?.value ?? '';
		const label = this._formatLaborProductLabel(productCode, name, id);
		if (label && this._laborProductLabelById[id] !== label) {
			this._laborProductLabelById = { ...this._laborProductLabelById, [id]: label };
		}
		this._cacheLaborPartDetails(id, productCode, description);
		this._syncLaborProductDetails(id, productCode, description);
	}

	/**
	 * @description Query Variables.
	 */
	get queryVariables() {
		return { workOrderId: this.recordId };
	}

	/**
	 * @description GraphQL variables for Device Type Service Codes (ProductCode prefix match).
	 */
	get serviceCodeQueryVariables() {
		void this.repairCodeUiVersion;
		const product2Id = this._serviceCodeQueryProduct2Id;
		const base = product2Id ? this._baseServiceCodeByProduct2Id[product2Id] : '';
		if (!product2Id || !base) return undefined;
		return this._serviceCodeLikePatterns(base);
	}

	/**
	 * @description GraphQL variables for the Device Type pricebook entry.
	 */
	get pricebookEntryQueryVariables() {
		const product2Id = this._pbeQueryProduct2Id;
		const pricebook2Id = this._workOrder?.Pricebook2Id?.value;
		if (!product2Id || !pricebook2Id) return undefined;
		return { pricebook2Id, product2Id };
	}
	/**
	 * @description Current User Query Variables.
	 */
	get currentUserQueryVariables() { return { userId: USER_ID }; }
	/**
	 * @description Service Resource Query Variables.
	 */
	get serviceResourceQueryVariables() {
		return this._serviceResourceIdsForLookup?.length
			? { resourceIds: this._serviceResourceIdsForLookup }
			: undefined;
	}

	/**
	 * @description Is Loading.
	 */
	get isLoading() {
		const accessLoading = !this.childAccessGraphqlResult?.data && !this.childAccessGraphqlResult?.errors;
		const woLoading = this.showChildDebrief
			&& !this.graphqlResult?.data
			&& !this.graphqlResult?.errors;
		return accessLoading || woLoading;
	}

	/**
	 * @description Has Error.
	 */
	get hasError() {
		return !!this.childAccessGraphqlResult?.errors || !!this.graphqlResult?.errors;
	}
	/**
	 * @description Has Work Order.
	 */
	get hasWorkOrder() { return !!this._workOrder; }

	/**
	 * @description Inverse of Site Visit isChildWorkOrder: this screen is only for a work order that has a parent.
	 */
	get isChildWorkOrder() {
		return !!this._accessWorkOrder?.ParentWorkOrderId?.value;
	}

	/**
	 * @description Child review opens only when the access query found a parent, same shape as Site Visit isChildWorkOrder.
	 */
	get showChildDebrief() {
		return this.isChildWorkOrder;
	}

	/**
	 * @description Site visit (no parent) cannot continue. Same shape as Site Visit showReview.
	 */
	get isSiteVisitWorkOrder() {
		return !!this._accessWorkOrder && !this.isChildWorkOrder;
	}

	/**
	 * @description Message shown when the opened work order is the site visit.
	 */
	get childDebriefBlockedMessage() {
		const woNumber = this._accessWorkOrder?.WorkOrderNumber?.value;
		return woNumber
			? `Only a child work order can access this screen. Work order ${woNumber} has no parent. Use Work Order Review - IMS Site Visit.`
			: 'Only a child work order can access this screen. Open the child work order.';
	}

	get showTrayPlannerModal() {
		return this.showChildDebrief && this.showTrayPlanner;
	}
	/**
	 * @description Show No Data.
	 */
	get showNoData() {
		return this.showChildDebrief
			&& !this.isLoading
			&& !this.hasError
			&& !this.hasWorkOrder;
	}

	/**
	 * @description Error Message.
	 */
	get errorMessage() {
		return JSON.stringify(this.childAccessGraphqlResult?.errors || this.graphqlResult?.errors);
	}

	/**
	 * @description Wo Status.
	 */
	get woStatus() {
		return this._pendingWorkOrderStatus || this._workOrder?.Status?.value || '';
	}
	/**
	 * @description Wo Account Name.
	 */
	get woAccountName() { return this._workOrder?.Account?.Name?.value ?? ''; }
	/**
	 * @description Wo Asset Name.
	 */
	get woAssetName() {
		return this._workOrder?.Asset?.Name?.value ?? '';
	}
	/**
	 * @description Department options for the repair-center form, including the asset department.
	 */
	get departmentOptions() {
		const options = [...this._accountDepartmentOptions];
		const departmentId = this._assetDepartmentId();
		if (departmentId && !options.some(option => option.value === departmentId)) {
			options.unshift({
				label: this._assetDepartmentName() || 'Asset department',
				value: departmentId
			});
		}
		return options;
	}

	/**
	 * @description Wo Number.
	 */
	get woNumber() { return this._workOrder?.WorkOrderNumber?.value ?? ''; }
	/**
	 * @description Asset Id used to load Tray Planner records.
	 */
	get trayPlannerAssetId() {
		return this._workOrder?.Asset?.Id || undefined;
	}
	/**
	 * @description Account Id used to load departments for the repair-center form.
	 */
	get repairCenterAccountId() {
		return this._workOrder?.Account?.Id || undefined;
	}
	/**
	 * @description Insulation / Powder Coating options for the repair-center form.
	 */
	get insulationPowderCoatingOptions() {
		return this._insulationPicklistOptions.length
			? this._insulationPicklistOptions
			: INSULATION_POWDER_COATING_OPTIONS;
	}
	/**
	 * @description True when the add form should collect beyond-repair details.
	 */
	get addFormShowRepairCenterFields() {
		void this.repairCodeUiVersion;
		return this._showsObrDetailFields(this.addFormState?.serviceCodeId);
	}
	/**
	 * @description True when Additional Services is checked on the add form.
	 */
	get addFormShowInsulation() {
		return this.addFormShowRepairCenterFields && !!this.addFormState?.additionalServices;
	}
	/**
	 * @description GW-6191 - True when the add form Service Code is beyond repair (not Forward to National Repair Center).
	 */
	get addFormShowReplacedWithIXchange() {
		void this.repairCodeUiVersion;
		return this._showsReplacedWithIXchange(this.addFormState?.serviceCodeId, null);
	}
	/**
	 * @description Pictures chosen on a new repair-center line before it is saved.
	 */
	/**
	 * @description True when the Work Order asset has Tray Planner records.
	 */
	get hasTrayPlannerRecords() {
		return this.trayPlannerRows.length > 0;
	}

	/**
	 * @description GW-375 - Mobile Device Pictures saved on the child work order.
	 */
	get trayPictures() {
		void this.mobilePictureVersion;
		return this._savedAndUnsavedPictures(this.recordId).map(picture => this._pictureView(picture));
	}

	/**
	 * @description GW-375 - True when the child work order has at least one Mobile Device Picture.
	 */
	get hasTrayPictures() {
		return this.trayPictures.length > 0;
	}

	/**
	 * @description GW-375 - Live count of tray Mobile Device Pictures.
	 */
	get trayPictureCountLabel() {
		return this._pictureCountLabel(this.trayPictures.length);
	}

	/**
	 * @description GW-375 - Pictures captured on the instrument add form before the line is created.
	 */
	get addFormMobilePictures() {
		void this.mobilePictureVersion;
		return (this.addFormState?.mobilePictures || []).map(picture => this._pictureView(picture));
	}

	/**
	 * @description GW-375 - True when the instrument add form has pictures waiting to be saved.
	 */
	get hasAddFormMobilePictures() {
		return this.addFormMobilePictures.length > 0;
	}

	/**
	 * @description GW-375 - Live count of pictures on the instrument add form.
	 */
	get addFormMobilePictureCountLabel() {
		return this._pictureCountLabel(this.addFormMobilePictures.length);
	}
	/**
	 * @description Has Pending Changes.
	 */
	get hasPendingChanges() {
		return Object.keys(this._pendingEdits).length > 0 ||
			Object.keys(this._pendingDeletes).length > 0 ||
			this._pendingAdds.length > 0 ||
			this._pendingWorkOrderStatus !== undefined ||
			this._hasUnsavedPictures() ||
			this._instrumentLineIdsReadyToComplete().length > 0 ||
			this._totalServicedInstrumentsNeedsSave();
	}

	/**
	 * @description Save All Disabled.
	 */
	get saveAllDisabled() { return !this.hasPendingChanges || this._saving; }
	/**
	 * @description Cancel Disabled.
	 */
	get cancelDisabled() { return this._saving; }
	/**
	 * @description GW-312 - Complete Work Order is off while saving, completing, or once the work order is finished.
	 */
	get completeWorkOrderDisabled() {
		return this._saving || this._completingWorkOrder
			|| WO_CLOSED_STATUSES.has(this._workOrder?.Status?.value);
	}
	/**
	 * @description Tabs.
	 */
	get tabs() {
		void this.repairCodeUiVersion;
		void this.productMetaVersion;
		void this.mobilePictureVersion;
		return TAB_DEFS.map(def => ({
			key: def.key,
			label: def.label,
			addLabel: def.addLabel,
			canAdd: def.canAdd,
			schema: def.schema,
			isActive: this.activeTab === def.key,
			showAddForm: !!this.showAddForm[def.key],
			addError: this.addErrors[def.key] ?? '',
			lines: this._buildLinesFor(def)
		}));
	}

	/**
	 * @description Active Tab Model.
	 */
	get activeTabModel() { return this.tabs.find(t => t.isActive) ?? this.tabs[0]; }
	/**
	 * @description Active Tab Search Term.
	 */
	get activeTabSearchTerm() { return this.tabSearchTerms[this.activeTab] ?? ''; }
	/**
	 * @description Active Tab Search Placeholder.
	 */
	get activeTabSearchPlaceholder() {
		const schema = this.activeTabModel?.schema;
		if (schema === 'parts') return 'Search product, unit qty, or description…';
		if (schema === 'time') return 'Search line type, resource, or dates…';
		if (schema === 'instrument') return 'Search device type, service code, or repair level…';
		return 'Search lines…';
	}

	/**
	 * @description Active Tab Has No Search Results.
	 */
	get activeTabHasNoSearchResults() {
		const term = (this.activeTabSearchTerm ?? '').trim();
		return !!term && (this.activeTabModel?.lines?.length ?? 0) === 0;
	}

	/**
	 * @description Is Active Tab Parts.
	 */
	get isActiveTabParts() { return this.activeTabModel?.schema === 'parts'; }
	/**
	 * @description Is Active Tab Time.
	 */
	get isActiveTabTime() { return this.activeTabModel?.schema === 'time'; }
	/**
	 * @description Is Active Tab Instrument.
	 */
	get isActiveTabInstrument() { return this.activeTabModel?.schema === 'instrument'; }
	/**
	 * @description Read-only sum of Quantity on Instrument lines, including unsaved edits.
	 */
	get totalServicedInstrumentsValue() {
		return this._sumServicedInstrumentQuantities();
	}
	/**
	 * @description True when selected Repair Code is Beyond Repair (add form).
	 */
	get addFormIsBeyondRepair() {
		return this._isBeyondRepairRepairCode(this.addFormState?.repairCodeId);
	}
	/**
	 * @description True when Service Code cannot be picked yet (no Device Type).
	 */
	get addFormServiceCodeDisabled() {
		return !this.addFormState?.deviceTypeId;
	}
	/**
	 * @description Device Type–filtered Service Code combobox UI for the add form.
	 */
	get addFormServiceCodeUi() {
		void this.repairCodeUiVersion;
		return this._serviceCodeComboboxUiForDeviceType(
			this.addFormState?.deviceTypeId,
			this.addFormState?.serviceCodeId
		);
	}
	get addFormServiceCodeOptions() {
		return this.addFormServiceCodeUi.serviceCodeOptions;
	}
	get addFormShowServiceCodeCombobox() {
		return this.addFormServiceCodeUi.showServiceCodeCombobox;
	}
	get addFormServiceCodePlaceholder() {
		return this.addFormServiceCodeUi.serviceCodeComboboxPlaceholder;
	}
	get addFormServiceCodeStatusMessage() {
		return this.addFormServiceCodeUi.serviceCodeStatusMessage;
	}
	/**
	 * @description Repair Level display for the Instrument add form.
	 */
	get addFormRepairLevel() {
		return this.addFormState?.repairLevel || '—';
	}
	/**
	 * @description Time Line Type Options.
	 */
	get timeLineTypeOptions() { return TIME_LINE_TYPE_OPTIONS; }
	/**
	 * @description Add Form Is Travel Line.
	 */
	get addFormIsTravelLine() { return this.addFormState.lineType === 'Travel'; }
	/**
	 * @description Add Form Is Labor Line.
	 */
	get addFormIsLaborLine() { return this.addFormState.lineType === 'Labor'; }
	/**
	 * @description Add Form Has Time Line Type.
	 */
	get addFormHasTimeLineType() { return !!this.addFormState.lineType; }
	/**
	 * @description Parts Source Options.
	 */
	get partsSourceOptions() {
		return this.partsSourcePicklistOptions.length
			? this.partsSourcePicklistOptions
			: PARTS_SOURCE_OPTIONS;
	}
	/**
	 * @description Billing Type picklist options.
	 */
	get billingTypeOptions() {
		return this.billingTypePicklistOptions.length
			? this.billingTypePicklistOptions
			: BILLING_TYPE_OPTIONS;
	}
	/**
	 * @description Add Form Is Trunk Stock.
	 */
	get addFormIsTrunkStock() { return this.addFormState.partsSource === PARTS_SOURCE_TRUNK; }
	/**
	 * @description Add Form Is Customer Stock.
	 */
	get addFormIsCustomerStock() { return this.addFormState.partsSource === PARTS_SOURCE_CUSTOMER; }
	/**
	 * @description Add Form Product Code.
	 */
	get addFormProductCode() { return this.addFormState.productCode || ''; }
	/**
	 * @description Add Form Part Description.
	 */
	get addFormPartDescription() { return this.addFormState.partDescription || ''; }
	/**
	 * @description Add Form Returnable Label.
	 */
	get addFormReturnableLabel() {
		if (this.addFormIsCustomerStock) {
			return this._fmtReturnable(
				this._resolveReturnableForProduct2(this.addFormState.product2Id)
				?? this.addFormState.returnable
			);
		}
		return this._fmtReturnable(this._resolveReturnableForProductItem(this.addFormState.productItemId));
	}

	/**
	 * @description Add Form Allowed Unit Label.
	 */
	get addFormAllowedUnitLabel() {
		return this._fmtReturnable(this.addFormState.allowedUnit);
	}

	/**
	 * @description Add Form Duration Label.
	 */
	get addFormDurationLabel() {
		return this._fmtDurationLabel(
			this._computeDurationHours(this.addFormState.startDate, this.addFormState.endDate)
		);
	}

	/**
	 * @description Formatted List Price for Time add form (custom ListPrice__c).
	 */
	get addFormListPriceLabel() {
		return this._fmtOptionalMoney(this.addFormState.listPrice);
	}

	/**
	 * @description Formatted Unit Price for Time add form (custom UnitPrice__c).
	 */
	get addFormUnitPriceLabel() {
		return this._fmtOptionalMoney(this.addFormState.unitPrice);
	}

	/**
	 * @description Formatted Total Price for Time add form (custom TotalPrice__c).
	 */
	get addFormTotalPriceLabel() {
		return this._fmtOptionalMoney(this.addFormState.totalPrice);
	}

	/**
	 * @description Computed Add Total Price.
	 */
	get computedAddTotalPrice() {
		const u = Number(this.addFormState.unitPrice) || 0;
		const q = Number(this.addFormState.quantity) || 0;
		return (u * q).toFixed(2);
	}

	/**
	 * @description Add Form Product Description.
	 */
	get addFormProductDescription() {
		return this._resolveLaborProductDescription(
			this.addFormState.product2Id,
			this.addFormState.productDescription
		);
	}

	/**
	 * @description Add Form Repair Code Loading.
	 */
	get addFormRepairCodeLoading() {
		const product2Id = this.addFormState.product2Id;
		void this.repairCodeUiVersion;
		return !!(product2Id && this._repairCodeLoadingByProduct2Id[product2Id]);
	}

	/**
	 * @description Add Form Repair Code Options.
	 */
	get addFormRepairCodeOptions() {
		void this.repairCodeUiVersion;
		return this._repairCodeOptionsForProduct(this.addFormState.product2Id);
	}

	/**
	 * @description Add Form Repair Code Combobox Placeholder.
	 */
	get addFormRepairCodeComboboxPlaceholder() {
		void this.repairCodeUiVersion;
		return this._repairCodeComboboxPlaceholderForProduct(this.addFormState.product2Id);
	}

	/**
	 * @description Add Form Show Repair Code Combobox.
	 */
	get addFormShowRepairCodeCombobox() {
		const product2Id = this.addFormState.product2Id;
		void this.repairCodeUiVersion;
		if (!product2Id || this._repairCodeLoadingByProduct2Id[product2Id]) return false;
		return (this._repairCodeOptionsForProduct(product2Id) ?? []).length > 0;
	}

	/**
	 * @description Add Form Product Item Filter.
	 */
	get addFormProductItemFilter() {
		return this._productItemFilterForResource(this.addFormState.assignedResourceId);
	}

	/**
	 * @description Add Form Product Item Scan Disabled.
	 */
	get addFormProductItemScanDisabled() {
		return !this.addFormState.assignedResourceId;
	}

	/**
	 * @description Resource Picker Filter.
	 */
	get resourcePickerFilter() {
		return { criteria: [{ fieldPath: 'IsActive', operator: 'eq', value: true }] };
	}

	/**
	 * @description Resource Picker Display Info.
	 */
	get resourcePickerDisplayInfo() { return { primaryField: 'Name' }; }
	/**
	 * @description Resource Picker Matching Info.
	 */
	get resourcePickerMatchingInfo() { return { primaryField: { fieldPath: 'Name' } }; }
	/**
	 * @description Labor Product Picker Filter.
	 */
	get laborProductPickerFilter() {
		return {
			criteria: [{
				fieldPath: PRODUCT2_PRODUCT_TYPE.fieldApiName,
				operator: 'eq',
				value: PART_PRODUCT_TYPE
			}],
			filterLogic: '1'
		};
	}

	/**
	 * @description Labor Product Picker Display Info.
	 */
	get laborProductPickerDisplayInfo() {
		return { primaryField: 'ProductCode', additionalFields: ['Name'] };
	}

	/**
	 * @description Labor Product Picker Matching Info.
	 */
	get laborProductPickerMatchingInfo() {
		return {
			primaryField: { fieldPath: 'ProductCode' },
			additionalFields: [{ fieldPath: 'Name' }]
		};
	}

	/**
	 * @description Repair Code Product Picker Filter (Service Code products).
	 */
	get serviceCodeProductPickerFilter() {
		return {
			criteria: [{
				fieldPath: PRODUCT2_PRODUCT_TYPE.fieldApiName,
				operator: 'eq',
				value: SERVICE_CODE_PRODUCT_TYPE
			}],
			filterLogic: '1'
		};
	}

	/**
	 * @description Device Type picker shows the Product Name.
	 */
	get deviceTypePickerDisplayInfo() {
		return { primaryField: 'Name' };
	}

	/**
	 * @description Device Type search matches Product Name, and Product Code as a secondary match.
	 */
	get deviceTypePickerMatchingInfo() {
		return {
			primaryField: { fieldPath: 'Name' },
			additionalFields: [{ fieldPath: 'ProductCode' }]
		};
	}

	/**
	 * @description Device Type picker: Service Asset products whose Item Number contains DT.
	 */
	get deviceTypePickerFilter() {
		return {
			criteria: [
				{ fieldPath: 'IsActive', operator: 'eq', value: true },
				{
					fieldPath: PRODUCT2_PRODUCT_TYPE.fieldApiName,
					operator: 'eq',
					value: SERVICE_ASSET_PRODUCT_TYPE
				},
				{ fieldPath: 'ProductCode', operator: 'like', value: '%DT.%' }
			],
			filterLogic: '1 AND 2 AND 3'
		};
	}

	/**
	 * @description Calibration Asset Picker Filter.
	 */
	get calibrationAssetPickerFilter() {
		return {
			criteria: [
				{
					fieldPath: ASSET_INTERNAL_CATEGORY.fieldApiName,
					operator: 'eq',
					value: CALIBRATION_DEVICE_CATEGORY
				},
				{
					fieldPath: ASSET_TYPE.fieldApiName,
					operator: 'eq',
					value: STERIS_ASSET_TYPE
				}
			],
			filterLogic: '1 AND 2'
		};
	}

	/**
	 * @description Product Item Picker Display Info.
	 */
	get productItemPickerDisplayInfo() { return { primaryField: 'ProductName' }; }
	/**
	 * @description Product Item Picker Matching Info.
	 */
	get productItemPickerMatchingInfo() { return { primaryField: { fieldPath: 'ProductName' } }; }
	/**
	 * @description Product Picker Display Info.
	 */
	get productPickerDisplayInfo() { return { primaryField: 'ProductCode', additionalFields: ['Name'] }; }
	/**
	 * @description Product Picker Matching Info.
	 */
	get productPickerMatchingInfo() {
		return {
			primaryField: { fieldPath: 'ProductCode' },
			additionalFields: [{ fieldPath: 'Name' }]
		};
	}
	/**
	 * @description Product Picker Filter for active products only.
	 */
	get productPickerFilter() {
		return { criteria: [{ fieldPath: 'IsActive', operator: 'eq', value: true }] };
	}
	/**
	 * @description Opens the read-only Tray Planner list.
	 */
	handleShowTrayPlanner() {
		this.showTrayPlanner = true;
	}

	/**
	 * @description Closes the Tray Planner list.
	 */
	handleCloseTrayPlanner() {
		this.showTrayPlanner = false;
	}

	/**
	 * @description Handle Tab Select.
	 */
	handleTabSelect(e) { this.activeTab = e.currentTarget.dataset.tab; }
	/**
	 * @description Handle Tab Search Change.
	 */
	handleTabSearchChange(e) {
		this.tabSearchTerms = { ...this.tabSearchTerms, [this.activeTab]: e.detail.value ?? '' };
	}

	/**
	 * @description Handle Edit Toggle.
	 */
	handleEditToggle(e) {
		const id = e.currentTarget.dataset.id;
		const cur = this.editStateMap[id];
		const becomingEdit = !(cur?.isEditing);
		if (!becomingEdit) {
			this._finalizeInstrumentStatus(id);
		}
		this.editStateMap = { ...this.editStateMap, [id]: { isEditing: becomingEdit } };
		const errs = { ...this.editErrors };
		delete errs[id];
		this.editErrors = errs;
		if (becomingEdit) {
			const product2Id = this._laborProduct2IdForLine(id);
			if (product2Id) this._ensureRepairCodesForProduct(product2Id);
			const deviceTypeId = this._instrumentDeviceTypeIdForLine(id);
			if (deviceTypeId) this._ensureRepairCodesForProduct(deviceTypeId);
			this._defaultDepartmentOnEdit(id);
		}
	}

	/**
	 * @description Handle Edit Close.
	 */
	handleEditClose(e) {
		const id = e.currentTarget.dataset.id;
		this._finalizeInstrumentStatus(id);
		this.editStateMap = { ...this.editStateMap, [id]: { isEditing: false } };
		const errs = { ...this.editErrors };
		delete errs[id];
		this.editErrors = errs;
	}

	/**
	 * @description Selects a Service Code from the scrollable instrument list.
	 */
	handleServiceCodeSelect(event) {
		event.stopPropagation();
		const value = event.currentTarget.dataset.value;
		const lineId = event.currentTarget.dataset.id;
		if (lineId) {
			this._stageEdit(lineId, 'serviceCodeId', value);
			this._stageServiceCodeSelection(lineId, value);
			return;
		}
		const next = { ...this.addFormState, serviceCodeId: value };
		this._applyServiceCodeSelection(next, value);
		this.addFormState = next;
	}

	/**
	 * @description GW-375 - Compresses a mobile-device photo and saves or stages it.
	 */
	async handleMobilePictureSelected(event) {
		const input = event.currentTarget;
		const file = input.files && input.files[0];
		const scope = input.dataset.scope;
		const lineId = input.dataset.id;
		input.value = '';
		if (!file || this._savingPicture) {
			return;
		}
		this._savingPicture = true;
		try {
			const localPicture = await this._fileToMobilePicture(file);
			this._pendingPictureCapture = { scope, lineId, localPicture };
			this.pictureDetailsDraft = { category: '', beforeAfter: '', comment: '' };
			this.pictureDetailsError = '';
			this.showPictureDetails = true;
		} catch (error) {
			this._toast('Picture was not saved', this._errorMessage(error), 'error');
		} finally {
			this._savingPicture = false;
		}
	}

	get pictureDetailsPreviewUrl() {
		return this._pendingPictureCapture?.localPicture?.previewUrl || '';
	}

	get showPictureMarkup() {
		return this._pendingPictureCapture?.localPicture?.title === MICROSCOPE_PICTURE_TITLE;
	}

	/**
	 * @description GW-6340 - Opens the microscopic camera for the work order or an instrument line.
	 */
	handleOpenMicroscopeCamera(event) {
		if (this._savingPicture) {
			return;
		}
		this._microscopeTarget = {
			scope: event.currentTarget.dataset.scope,
			lineId: event.currentTarget.dataset.id
		};
		this.showMicroscopeCamera = true;
	}

	/**
	 * @description GW-6340 - Closes the microscopic camera. A picture still waiting for its details stays open.
	 */
	handleCloseMicroscopeCamera() {
		this.showMicroscopeCamera = false;
		this._microscopeTarget = null;
	}

	/**
	 * @description GW-6340 - Asks for Category, Before/After, and comment of a microscopic camera picture.
	 *              The camera stays open behind the details so the next picture is one tap away.
	 */
	async handleMicroscopePhotoCaptured(event) {
		const target = this._microscopeTarget;
		const dataUrl = event.detail?.dataUrl;
		if (!target || !dataUrl || this.showPictureDetails || this._savingPicture) {
			return;
		}
		this._savingPicture = true;
		try {
			const localPicture = await this._dataUrlToMicroscopePicture(dataUrl);
			this._pendingPictureCapture = { scope: target.scope, lineId: target.lineId, localPicture };
			this.pictureDetailsDraft = { category: '', beforeAfter: '', comment: '' };
			this.pictureDetailsError = '';
			this.showPictureDetails = true;
		} catch (error) {
			this._toast('Picture was not saved', this._errorMessage(error), 'error');
		} finally {
			this._savingPicture = false;
		}
	}

	/**
	 * @description GW-6340 - Marks up a microscopic camera picture with the camera's markup tools.
	 */
	async handlePictureMarkup() {
		const camera = this.refs.microscopeCamera;
		const previewUrl = this.pictureDetailsPreviewUrl;
		if (!camera || !previewUrl) {
			return;
		}
		this.showPictureDetails = false;
		const opened = await camera.openMarkup(previewUrl);
		if (!opened) {
			this._toast('Markup is not available', 'You can still save the picture without markup.', 'warning');
			this.showPictureDetails = true;
		}
	}

	/**
	 * @description GW-6340 - Replaces the waiting picture with its marked-up copy.
	 */
	async handleMicroscopeMarkupSaved(event) {
		const pending = this._pendingPictureCapture;
		const dataUrl = event.detail?.dataUrl;
		if (pending?.localPicture && dataUrl) {
			try {
				const markedUp = await this._compressImageDataUrl(dataUrl);
				this._pendingPictureCapture = {
					...pending,
					localPicture: { ...pending.localPicture, previewUrl: markedUp, base64Data: markedUp }
				};
			} catch (error) {
				this._toast('Markup was not kept', this._errorMessage(error), 'warning');
			}
		}
		this.showPictureDetails = !!this._pendingPictureCapture;
	}

	handleMicroscopeMarkupCancelled() {
		this.showPictureDetails = !!this._pendingPictureCapture;
	}

	/**
	 * @description GW-375 - Keeps the Category, Before/After, and comment of a new picture.
	 */
	handlePictureDetailChange(event) {
		const field = event.currentTarget.dataset.field;
		this.pictureDetailsDraft = { ...this.pictureDetailsDraft, [field]: event.detail.value || '' };
		this.pictureDetailsError = '';
	}

	/**
	 * @description GW-375 - Drops a new picture without saving it.
	 */
	handlePictureDetailsCancel() {
		this.showPictureDetails = false;
		this._pendingPictureCapture = null;
		this.pictureDetailsError = '';
	}

	/**
	 * @description GW-375 - Saves a new picture after Category and Before/After are chosen.
	 */
	async handlePictureDetailsConfirm() {
		const pending = this._pendingPictureCapture;
		if (!pending?.localPicture) {
			this.handlePictureDetailsCancel();
			return;
		}
		const { category, beforeAfter, comment } = this.pictureDetailsDraft;
		if (!category || !beforeAfter) {
			this.pictureDetailsError = 'Select a Category and Before/After.';
			return;
		}
		const localPicture = {
			...pending.localPicture,
			category,
			beforeAfter,
			comment: String(comment || '').trim().substring(0, PICTURE_COMMENT_MAX_LENGTH)
		};
		this.showPictureDetails = false;
		this._pendingPictureCapture = null;
		if (this._savingPicture) {
			return;
		}
		this._savingPicture = true;
		try {
			await this._placeMobilePicture(pending.scope, pending.lineId, localPicture);
		} catch (error) {
			this._toast('Picture was not saved', this._errorMessage(error), 'error');
		} finally {
			this._savingPicture = false;
		}
	}

	/**
	 * @description GW-375 - Stages a picture on a new line, or saves it on a saved line or the work order.
	 * @param {string} scope tray, add, or line
	 * @param {string} lineId Line or temp Id
	 * @param {Object} localPicture Picture with its details
	 */
	async _placeMobilePicture(scope, lineId, localPicture) {
		if (scope === 'add') {
			this.addFormState = {
				...this.addFormState,
				mobilePictures: [...(this.addFormState.mobilePictures || []), localPicture]
			};
			this.mobilePictureVersion += 1;
			return;
		}
		if (scope === 'line' && !this._isSalesforceWoliId(lineId)) {
			this._pendingAdds = this._pendingAdds.map(add => (
				add._tempId === lineId
					? { ...add, mobilePictures: [...(add.mobilePictures || []), localPicture] }
					: add
			));
			this.mobilePictureVersion += 1;
			return;
		}
		const primaryRecordId = scope === 'tray' ? this.recordId : lineId;
		if (!primaryRecordId) {
			this._toast('Picture was not saved', 'Open the work order again, then take the picture.', 'error');
			return;
		}
		if (await this._saveMobilePictureOrKeep(primaryRecordId, localPicture)) {
			const completed = scope === 'line' ? await this._completeReadyInstrumentLines() : [];
			this._toast(
				'Picture saved',
				completed.length ? 'Mobile Device Picture saved. The line is Completed.' : 'Mobile Device Picture saved.',
				'success'
			);
		}
	}

	/**
	 * @description GW-375 - Opens a Mobile Device Picture for review.
	 */
	async handleReviewPicture(event) {
		const scope = event.currentTarget.dataset.scope;
		const lineId = event.currentTarget.dataset.lineId;
		const key = event.currentTarget.dataset.key;
		const picture = this._findMobilePicture(scope, lineId, key);
		if (!picture) {
			return;
		}
		const view = this._pictureView(picture);
		this.reviewPicture = {
			...view,
			scope,
			lineId: lineId || null,
			contentVersionId: picture.contentVersionId || null
		};
		this.showPictureReview = true;
		if (view.previewUrl && view.previewUrl.startsWith('data:')) {
			this.reviewPictureUrl = view.previewUrl;
			this.reviewPictureLoading = false;
			return;
		}
		this.reviewPictureUrl = '';
		this.reviewPictureLoading = true;
		try {
			const dataUrl = await this._loadSavedPicturePreview(picture.contentVersionId);
			if (this.reviewPicture?.contentVersionId === picture.contentVersionId && dataUrl) {
				this.reviewPictureUrl = dataUrl;
			}
		} catch (error) {
			this._toast('Picture', this._errorMessage(error), 'error');
		} finally {
			if (this.reviewPicture?.contentVersionId === picture.contentVersionId) {
				this.reviewPictureLoading = false;
			}
		}
	}

	/**
	 * @description GW-375 - Closes the picture review.
	 */
	get reviewPictureTitle() {
		return this.reviewPicture?.title || MOBILE_DEVICE_PICTURE_TITLE;
	}

	handleClosePictureReview() {
		this.showPictureReview = false;
		this.reviewPicture = null;
		this.reviewPictureUrl = '';
		this.reviewPictureLoading = false;
	}

	/**
	 * @description GW-375 - Deletes the picture shown in the review dialog.
	 */
	async handleDeleteReviewedPicture() {
		if (!this.reviewPicture) {
			return;
		}
		const deleted = await this._deleteMobilePicture(
			this.reviewPicture.scope,
			this.reviewPicture.lineId,
			this.reviewPicture.key
		);
		if (deleted) {
			this.handleClosePictureReview();
		}
	}

	/**
	 * @description GW-375 - Deletes a Mobile Device Picture from a thumbnail.
	 */
	async handleDeletePicture(event) {
		event.stopPropagation();
		await this._deleteMobilePicture(
			event.currentTarget.dataset.scope,
			event.currentTarget.dataset.lineId,
			event.currentTarget.dataset.key
		);
	}

	/**
	 * @description Handle Edit Field Change.
	 */
	handleEditFieldChange(e) {
		const id = e.currentTarget.dataset.id;
		const field = e.currentTarget.dataset.field;
		const value = e.detail.checked !== undefined ? e.detail.checked : e.detail.value;
		this._stageEdit(id, field, value);
		if (field === 'billingType') {
			this._stageEdit(id, 'discount', this._discountForBillingType(value));
		}
		if (field === 'serviceCodeId') {
			this._stageServiceCodeSelection(id, value);
		}
		if (field === 'additionalServices' && !value) {
			this._stageEdit(id, 'insulationPowderCoating', []);
		}
		if (field === 'canceled') {
			this._stageEdit(id, 'status', value ? WOLI_STATUS_CANCELED : 'New');
		}
		if (field === 'lineType') {
			if (value === 'Travel') {
				this._stageEdit(id, 'product2Id', null);
				this._stageEdit(id, 'repairCodeId', null);
				this._stageEdit(id, 'productCode', '');
				this._stageEdit(id, 'laborPartProductCode', '');
				this._stageEdit(id, 'productDescription', '');
			} else if (value === 'Labor') {
				this._stageEdit(id, 'startDate', null);
				this._stageEdit(id, 'endDate', null);
				this._stageEdit(id, 'durationHours', null);
			}
			const schema = LINE_TYPE_TO_SCHEMA[value];
			if (schema) {
				this._stageEdit(id, '_schema', schema);
				this._stageEdit(id, '_lineType', value);
				this._stageEdit(id, 'lineType', value);
			}
			if (value === 'Travel' || value === 'Labor') {
				this._stageEdit(id, 'billingType', BILLING_TYPE_NON_BILLABLE);
				this._stageEdit(id, 'discount', 0);
			}
		}
		if (field === 'partsSource') {
			this._applyPartsSourceChangeToEdit(id, value);
		}
		if (field === 'startDate' || field === 'endDate' || field === 'durationHours') {
			this._syncTimeFieldsOnEdit(id, field);
		}
	}

	/**
	 * @description Handle Delete.
	 */
	handleDelete(e) {
		const id = e.currentTarget.dataset.id;
		if (this._pendingAdds.some(a => a._tempId === id)) {
			this._pendingAdds = this._pendingAdds.filter(a => a._tempId !== id);
			this._syncWorkOrderInProgress();
			return;
		}
		this._pendingDeletes = { ...this._pendingDeletes, [id]: true };
		const edits = { ...this._pendingEdits };
		delete edits[id];
		this._pendingEdits = edits;
		this._syncWorkOrderInProgress();
	}

	/**
	 * @description Handle Add Toggle.
	 */
	handleAddToggle(e) {
		const tab = e.currentTarget.dataset.tab || this.activeTab;
		this.showAddForm = { ...EMPTY_ADD_FORM_VISIBILITY(), [tab]: true };
		this.addFormState = this._emptyAddFormState();
		if (tab === 'Time') {
			this.addFormState = {
				...this.addFormState,
				billingType: BILLING_TYPE_NON_BILLABLE,
				discount: 0
			};
		}
		this.addErrors = {};
		if (this.addFormState.assignedResourceId) {
			this._onResourceSelected(this.addFormState.assignedResourceId);
		}
	}

	/**
	 * @description Clones an Instrument line with the same Device Type and a blank Service Code and Quantity.
	 */
	handleAddServiceCode(e) {
		const lineId = e.currentTarget.dataset.id;
		const source = this._instrumentCloneSource(lineId);
		if (!source?.deviceTypeId) {
			this.editStateMap = { ...this.editStateMap, [lineId]: { isEditing: true } };
			this.editErrors = {
				...this.editErrors,
				[lineId]: 'Device Type is required to add a service code.'
			};
			return;
		}

		_tempIdSeq += 1;
		const tempId = `_new_${_tempIdSeq}`;
		const billingType = this._normalizeBillingType(source.billingType);
		this._pendingAdds = [
			...this._pendingAdds,
			{
				_tempId: tempId,
				_lineType: INSTRUMENT_LINE_TYPE,
				_schema: 'instrument',
				_entity: 'WorkOrderLineItem',
				deviceTypeId: source.deviceTypeId,
				deviceType: source.deviceType
					|| this._productCodeByProduct2Id[source.deviceTypeId]
					|| '',
				serviceCodeId: null,
				repairLevel: '',
				quantity: '',
				billingType,
				discount: this._discountForBillingType(billingType),
				status: WOLI_STATUS_IN_PROGRESS
			}
		];
		this._ensureRepairCodesForProduct(source.deviceTypeId);
		this._syncWorkOrderInProgress();
		this.editStateMap = {
			...this.editStateMap,
			[tempId]: { isEditing: true }
		};
	}

	/**
	 * @description Handle Add Field Change.
	 */
	handleAddFieldChange(e) {
		const field = e.currentTarget.dataset.field;
		const value = e.detail.checked !== undefined ? e.detail.checked : e.detail.value;
		const next = { ...this.addFormState, [field]: value };
		if (field === 'billingType') {
			next.discount = this._discountForBillingType(value);
		}
		if (field === 'serviceCodeId') {
			this._applyServiceCodeSelection(next, value);
		}
		if (field === 'additionalServices' && !value) {
			next.insulationPowderCoating = [];
		}
		if (field === 'canceled') {
			next.status = value ? WOLI_STATUS_CANCELED : 'New';
		}
		if (field === 'lineType') {
			next.repairCodeId = null;
			next.productCode = '';
			next.productDescription = '';
			next.laborPartProductCode = '';
			next.product2Id = null;
			if (value !== 'Travel') {
				next.startDate = '';
				next.endDate = '';
				next.durationHours = '';
			}
			if (value === 'Travel' || value === 'Labor') {
				next.workTypeId = next.workTypeId || this._headerWorkTypeId();
				next.billingType = BILLING_TYPE_NON_BILLABLE;
				next.discount = 0;
			}
		}
		if (field === 'partsSource') {
			next.allowedUnit = null;
			next.returnable = null;
			next.productCode = '';
			next.partDescription = '';
			if (value === PARTS_SOURCE_TRUNK) {
				next.product2Id = null;
				if (next.productItemId) {
					const linkedProduct2Id = this._product2IdByProductItemId[next.productItemId];
					next.returnable = this._resolveReturnableForProductItem(next.productItemId);
					next.productCode = linkedProduct2Id
						? (this._productCodeByProduct2Id[linkedProduct2Id] ?? '')
						: '';
					next.partDescription = linkedProduct2Id
						? (this._partDescriptionByProduct2Id[linkedProduct2Id] ?? '')
						: '';
					this.addFormState = next;
					this._onProductItemSelected(next.productItemId, { isAddForm: true });
					return;
				}
			} else if (value === PARTS_SOURCE_CUSTOMER) {
				next.productItemId = null;
			}
		}
		if (field === 'repairCodeId') {
			next.productCode = value ? (this._resolveProductCodeForRepairCode(value) ?? '') : '';
			if (value) this._repairCodeLookupId = value;
		}
		if (field === 'startDate' || field === 'endDate' || field === 'durationHours') {
			this.addFormState = this._syncTimeFieldsOnState(next, field);
			return;
		}
		this.addFormState = next;
	}

	/**
	 * @description Handle Product Item Barcode Scan.
	 */
	async handleProductItemBarcodeScan(e) {
		const editId = e.currentTarget.dataset.id || null;
		const isAddForm = e.currentTarget.dataset.mode === 'add';
		const resourceId = isAddForm
			? this.addFormState.assignedResourceId
			: (this.editStateMap[editId]?.assignedResourceId
				?? this._pendingEdits[editId]?.assignedResourceId
				?? this._resourceIdForEditLine(editId));
		if (!resourceId) {
			this._toast('Select a Resource', 'Choose an Assigned Resource before scanning.', 'warning');
			return;
		}

		const productCode = await this._captureProductCode();
		if (!productCode) return;

		try {
			const match = await this._findProductItemByProductCode(productCode, resourceId);
			if (match?.locationId) {
				this._locationIdByServiceResourceId = {
					...this._locationIdByServiceResourceId,
					[resourceId]: match.locationId
				};
			}
			if (!match?.productItemId) {
				this._toast(
					'No match',
					match?.locationId
						? `No in-stock Product Item found for Product Code "${productCode}" at this resource location.`
						: 'The selected Resource has no Location for trunk stock.',
					'warning'
				);
				return;
			}
			if (match.matchCount > 1) {
				this._toast(
					'Multiple matches',
					`Multiple Product Items matched "${productCode}". The highest-quantity item was selected.`,
					'info'
				);
			}
			this._applyScannedProductItem(match, { editId, isAddForm });
		} catch (error) {
			this._toast(
				'Scan lookup failed',
				this._apexErrorMessage(error) || 'Unable to find Product Item for scanned code.',
				'error'
			);
		}
	}

	/**
	 * @description Handle Product barcode scan (Customer Stock Product2 by Product Code).
	 */
	async handleProductBarcodeScan(e) {
		const editId = e.currentTarget.dataset.id || null;
		const isAddForm = e.currentTarget.dataset.mode === 'add';

		const productCode = await this._captureProductCode();
		if (!productCode) return;

		try {
			const match = await this._findProductByProductCode(productCode);
			if (!match?.product2Id) {
				this._toast(
					'No match',
					`No active Product found for Product Code "${productCode}".`,
					'warning'
				);
				return;
			}
			if (match.matchCount > 1) {
				this._toast(
					'Multiple matches',
					`Multiple Products matched "${productCode}". The most recently modified product was selected.`,
					'info'
				);
			}
			this._applyScannedProduct(match, { editId, isAddForm });
		} catch (error) {
			this._toast(
				'Scan lookup failed',
				this._apexErrorMessage(error) || 'Unable to find Product for scanned code.',
				'error'
			);
		}
	}

	/**
	 * @description Internal helper: Capture a barcode value (camera scan with prompt fallback).
	 * @param {object} [options]
	 * @param {string} [options.instructionText]
	 * @param {string} [options.successText]
	 * @param {string} [options.promptLabel]
	 * @param {string} [options.promptMessage]
	 * @return {Promise<string|null>}
	 */
	async _captureProductCode(options = {}) {
		const instructionText = options.instructionText || 'Scan product barcode';
		const successText = options.successText || 'Scan complete';
		const promptLabel = options.promptLabel || 'Product Code';
		const promptMessage = options.promptMessage
			|| 'Camera scan is unavailable. Enter the Product Code from the barcode.';
		const scanner = getBarcodeScanner();
		if (scanner && scanner.isAvailable()) {
			try {
				let first;
				if (typeof scanner.scan === 'function') {
					const results = await scanner.scan({
						instructionText,
						successText
					});
					first = Array.isArray(results) ? results[0] : results;
				} else if (typeof scanner.beginCapture === 'function') {
					first = await scanner.beginCapture({
						instructionText,
						successText
					});
				}
				const value = (typeof first === 'string' ? first : (first?.value ?? '')).trim();
				return value || null;
			} catch (error) {
				if (error?.code === 'userDismissedScanner') return null;
				this._toast(
					'Barcode scanner',
					error?.message || 'Unable to open the barcode scanner.',
					'error'
				);
				return null;
			} finally {
				try {
					if (typeof scanner.dismiss === 'function') scanner.dismiss();
					else if (typeof scanner.endCapture === 'function') scanner.endCapture();
				} catch (e) {
					// ignore dismiss errors
				}
			}
		}

		return new Promise((resolve) => {
			LightningPrompt.open({
				label: promptLabel,
				message: promptMessage,
				defaultValue: ''
			}).then((value) => {
				const code = (value ?? '').trim();
				resolve(code || null);
			}).catch(() => resolve(null));
		});
	}

	/**
	 * @description Handle Instrument-tab barcode scan for all fields except Service Code.
	 */
	async handleInstrumentFieldBarcodeScan(e) {
		const field = e.currentTarget.dataset.field;
		const label = e.currentTarget.dataset.label || 'value';
		const editId = e.currentTarget.dataset.id || null;
		const isAddForm = e.currentTarget.dataset.mode === 'add';
		if (!field) return;

		const scanned = await this._captureProductCode({
			instructionText: `Scan ${label}`,
			promptLabel: label,
			promptMessage: `Camera scan is unavailable. Enter the ${label} from the barcode.`
		});
		if (!scanned) return;

		if (field === 'deviceTypeId') {
			await this._applyScannedInstrumentLookup(field, scanned, { editId, isAddForm });
			return;
		}
		this._applyScannedInstrumentText(field, scanned, { editId, isAddForm });
	}

	/**
	 * @description Apply a scanned Product Code to Instrument or Repair Code lookups.
	 * @param {string} field instrumentId or repairCodeId
	 * @param {string} productCode Scanned code
	 * @param {{ editId: string|null, isAddForm: boolean }} options
	 */
	async _applyScannedInstrumentLookup(field, productCode, options = {}) {
		const { editId = null, isAddForm = false } = options;
		const isInstrument = field === 'instrumentId';
		const isDeviceType = field === 'deviceTypeId';
		const productType = isDeviceType
			? SERVICE_ASSET_PRODUCT_TYPE
			: (isInstrument ? PART_PRODUCT_TYPE : SERVICE_CODE_PRODUCT_TYPE);
		const fieldLabel = isDeviceType ? 'Device Type' : (isInstrument ? 'Instrument' : 'Repair Code');
		try {
			const match = await this._findProductByProductCode(productCode, productType);
			if (!match?.product2Id) {
				this._toast(
					'No match',
					`No ${fieldLabel} found for "${productCode}".`,
					'warning'
				);
				return;
			}
			if (match.matchCount > 1) {
				this._toast(
					'Multiple matches',
					`Multiple ${fieldLabel} records matched "${productCode}". The most recently modified was selected.`,
					'info'
				);
			}
			const recordId = match.product2Id;
			this._cacheProductMeta(recordId, { name: match.productName });
			if (match.productCode) {
				this._repairCodeProductCodeById = {
					...this._repairCodeProductCodeById,
					[recordId]: match.productCode
				};
			}
			this._loadProductMeta(recordId);
			if (isAddForm) {
				const next = { ...this.addFormState, [field]: recordId };
				if (isDeviceType) {
					this._applyDeviceTypeSelection(next, recordId, match.productCode);
					this.addFormState = next;
					this._toast(`${fieldLabel} selected`, match.productName || match.productCode || recordId, 'success');
					return;
				}
				if (!isInstrument) {
					next.productCode = this._resolveProductCodeForRepairCode(recordId) ?? match.productCode ?? '';
					this._repairCodeLookupId = recordId;
				}
				this.addFormState = next;
				this._toast(`${fieldLabel} selected`, match.productName || match.productCode || recordId, 'success');
				return;
			}
			if (editId) {
				this._stageEdit(editId, field, recordId);
				if (isDeviceType) {
					this._stageDeviceTypeSelection(editId, recordId, match.productCode);
					this._toast(`${fieldLabel} selected`, match.productName || match.productCode || recordId, 'success');
					return;
				}
				if (!isInstrument) {
					this._stageEdit(
						editId,
						'productCode',
						this._resolveProductCodeForRepairCode(recordId) ?? match.productCode ?? ''
					);
					this._repairCodeLookupId = recordId;
				}
				this._toast(`${fieldLabel} selected`, match.productName || match.productCode || recordId, 'success');
			}
		} catch (error) {
			this._toast(
				'Scan lookup failed',
				this._apexErrorMessage(error) || `Unable to find ${fieldLabel} for scanned code.`,
				'error'
			);
		}
	}

	/**
	 * @description Apply a scanned barcode value to an Instrument-tab text field.
	 * @param {string} field Field name
	 * @param {string} value Scanned value
	 * @param {{ editId: string|null, isAddForm: boolean }} options
	 */
	_applyScannedInstrumentText(field, value, options = {}) {
		const { editId = null, isAddForm = false } = options;
		if (isAddForm) {
			this.addFormState = { ...this.addFormState, [field]: value };
			return;
		}
		if (editId) {
			this._stageEdit(editId, field, value);
		}
	}

	/**
	 * @description Handle Lookup Change.
	 */
	handleLookupChange(e) {
		const id = e.currentTarget.dataset.id;
		const tab = e.currentTarget.dataset.tab;
		const field = e.currentTarget.dataset.field;
		const recordId = e.detail.recordId ?? null;

		if (id) {
			this._stageEdit(id, field, recordId);
			if (field === 'assignedResourceId') this._onResourceSelected(recordId, id);
			if (field === 'productItemId') {
				if (recordId) this._stageEdit(id, 'partsSource', PARTS_SOURCE_TRUNK);
				this._onProductItemSelected(recordId, { editId: id });
			}
			if (field === 'product2Id') {
				const schema = this._pendingEdits[id]?._schema
					?? this._pendingAdds.find(a => a._tempId === id)?._schema
					?? this._schemaForLineType(
						this._serverLines.find(l => l.Id === id)?.LineType__c?.value
					);
				if (schema === 'parts') {
					if (recordId) {
						this._stageEdit(id, 'partsSource', PARTS_SOURCE_CUSTOMER);
						this._product2LookupId = recordId;
					}
					this._evaluateAllowedUnitForProduct(recordId, { editId: id });
				} else {
					this._stageEdit(id, 'repairCodeId', null);
					this._stageEdit(id, 'productCode', '');
					this._onLaborProductSelected(recordId);
				}
			}
			if (field === 'repairCodeId' && recordId) {
				this._repairCodeLookupId = recordId;
				this._loadProductMeta(recordId);
			}
			if (field === 'instrumentId' && recordId) {
				this._loadProductMeta(recordId);
			}
			if (field === 'deviceTypeId') {
				this._stageDeviceTypeSelection(id, recordId);
			}
			if (field === 'serviceCodeId') {
				this._stageServiceCodeSelection(id, recordId);
			}
			if (field === 'instrumentId') {
				// keep repair code when instrument changes
			}
		} else if (tab) {
			const next = { ...this.addFormState, [field]: recordId };
			if (field === 'assignedResourceId') {
				this._onResourceSelected(recordId);
				next.productItemId = null;
				next.product2Id = null;
				next.productCode = '';
				next.partDescription = '';
				next.returnable = null;
				next.allowedUnit = null;
			}
			if (field === 'productItemId') {
				const linkedProduct2Id = recordId
					? (this._product2IdByProductItemId[recordId] ?? null)
					: null;
				next.product2Id = null;
				if (recordId) next.partsSource = PARTS_SOURCE_TRUNK;
				next.returnable = recordId
					? (this._resolveReturnableForProductItem(recordId) ?? null)
					: null;
				next.productCode = linkedProduct2Id
					? (this._productCodeByProduct2Id[linkedProduct2Id] ?? '')
					: '';
				next.partDescription = linkedProduct2Id
					? (this._partDescriptionByProduct2Id[linkedProduct2Id] ?? '')
					: '';
				next.allowedUnit = null;
				this._onProductItemSelected(recordId, { isAddForm: true });
			}
			if (field === 'product2Id') {
				if (tab === 'Parts' || this.isActiveTabParts) {
					next.productItemId = null;
					if (recordId) next.partsSource = PARTS_SOURCE_CUSTOMER;
					next.returnable = recordId
						? (this._resolveReturnableForProduct2(recordId) ?? null)
						: null;
					next.productCode = recordId
						? (this._productCodeByProduct2Id[recordId] ?? '')
						: '';
					next.partDescription = recordId
						? (this._partDescriptionByProduct2Id[recordId] ?? '')
						: '';
					next.allowedUnit = null;
					if (recordId) this._product2LookupId = recordId;
					this.addFormState = next;
					this._evaluateAllowedUnitForProduct(recordId, { isAddForm: true });
					return;
				}
				next.repairCodeId = null;
				next.productCode = '';
				next.laborPartProductCode = recordId
					? (this._laborPartProductCodeById[recordId] ?? '')
					: '';
				next.productDescription = recordId
					? (this._laborPartDescriptionById[recordId] ?? '')
					: '';
				this.addFormState = next;
				this._onLaborProductSelected(recordId);
				return;
			}
			if (field === 'repairCodeId') {
				next.productCode = recordId ? (this._resolveProductCodeForRepairCode(recordId) ?? '') : '';
				if (recordId) {
					this._repairCodeLookupId = recordId;
					this._loadProductMeta(recordId);
				}
			}
			if (field === 'instrumentId' && recordId) {
				this._loadProductMeta(recordId);
			}
			if (field === 'deviceTypeId') {
				this._applyDeviceTypeSelection(next, recordId);
			}
			if (field === 'serviceCodeId') {
				this._applyServiceCodeSelection(next, recordId);
			}
			this.addFormState = next;
		}

		if (field === 'repairCodeId' && recordId) {
			this._repairCodeLookupId = recordId;
			this._loadProductMeta(recordId);
		}
	}

	/**
	 * @description Handle Add Confirm.
	 */
	async handleAddConfirm(e) {
		const tab = e.currentTarget.dataset.tab || this.activeTab;
		const def = TAB_KEY_TO_DEF[tab];
		const schema = def?.schema ?? 'generic';
		let payload = { ...this.addFormState };
		if (schema === 'parts_consumed') {
			payload.assignedResourceId = this._resolveAssignedResourceId(payload.assignedResourceId);
			payload.product2Id = payload.product2Id || this._product2IdByProductItemId[payload.productItemId] || null;
			payload.returnable = this._resolveReturnableForProductItem(payload.productItemId);
		}
		if (schema === 'parts') {
			payload.assignedResourceId = this._resolveAssignedResourceId(payload.assignedResourceId);
			const isTrunk = payload.partsSource === PARTS_SOURCE_TRUNK;
			const isCustomer = payload.partsSource === PARTS_SOURCE_CUSTOMER;
			if (isTrunk) {
				payload.product2Id = null;
				payload.returnable = this._resolveReturnableForProductItem(payload.productItemId);
				if (payload.productItemId) {
					await this._evaluateAllowedUnitForProductItem(payload.productItemId, { isAddForm: true });
					payload = {
						...payload,
						allowedUnit: this.addFormState.allowedUnit,
						returnable: this.addFormState.returnable
							?? this._resolveReturnableForProductItem(payload.productItemId)
					};
				}
			} else if (isCustomer) {
				payload.productItemId = null;
				payload.returnable = this._resolveReturnableForProduct2(payload.product2Id)
					?? payload.returnable;
				if (payload.product2Id) {
					await this._evaluateAllowedUnitForProduct(payload.product2Id, { isAddForm: true });
					payload = {
						...payload,
						allowedUnit: this.addFormState.allowedUnit,
						returnable: this.addFormState.returnable
							?? this._resolveReturnableForProduct2(payload.product2Id)
					};
				}
			}
		}
		if (schema === 'time') {
			payload.assignedResourceId = this._resolveAssignedResourceId(payload.assignedResourceId);
			if (payload.lineType === 'Labor') {
				payload.productCode = this._resolveProductCodeForRepairCode(payload.repairCodeId) ?? '';
				payload.productDescription = this._resolveLaborProductDescription(
					payload.product2Id,
					payload.productDescription
				) ?? '';
			}
		}
		if (schema === 'labor') {
			payload.productCode = this._resolveProductCodeForRepairCode(payload.repairCodeId) ?? '';
			payload.productDescription = this._resolveLaborProductDescription(
				payload.product2Id,
				payload.productDescription
			) ?? '';
		}
		if (schema === 'instrument') {
			if (this._showsObrDetailFields(payload.serviceCodeId) && !payload.departmentId) {
				payload.departmentId = this._assetDepartmentId();
			}
			payload.status = payload.canceled || payload.status === WOLI_STATUS_CANCELED
				? WOLI_STATUS_CANCELED
				: WOLI_STATUS_IN_PROGRESS;
		}
		const errMsg = this._validateForSchema(schema, payload);
		if (errMsg) {
			this.addErrors = { ...this.addErrors, [tab]: errMsg };
			return;
		}

		_tempIdSeq += 1;
		const resolvedSchema = schema === 'time'
			? (LINE_TYPE_TO_SCHEMA[payload.lineType] ?? null)
			: schema;
		const resolvedLineType = schema === 'time' ? payload.lineType : (def?.type ?? tab);
		if (schema === 'time' && !resolvedSchema) {
			this.addErrors = { ...this.addErrors, [tab]: 'Line Type is required.' };
			return;
		}
		const baseAdd = {
			_tempId: `_new_${_tempIdSeq}`,
			_lineType: resolvedLineType,
			_schema: resolvedSchema ?? schema
		};
		let newAdd;

		if (schema === 'parts_consumed') {
			newAdd = {
				...baseAdd,
				_entity: 'ProductConsumed',
				assignedResourceId: payload.assignedResourceId,
				productItemId: payload.productItemId,
				product2Id: payload.product2Id,
				returnable: payload.returnable,
				quantityConsumed: Number(payload.quantityConsumed),
				description: payload.description ?? '',
				partsSource: payload.partsSource ?? '',
				workOrderLineItemId: null
			};
		} else if (schema === 'parts') {
			const isTrunk = payload.partsSource === PARTS_SOURCE_TRUNK;
			newAdd = {
				...baseAdd,
				_entity: 'WorkOrderLineItem',
				_lineType: 'Parts',
				assignedResourceId: payload.assignedResourceId,
				assignedResourceName: this._assignedResourceNameForId(payload.assignedResourceId),
				partsSource: payload.partsSource ?? PARTS_SOURCE_TRUNK,
				productItemId: isTrunk ? (payload.productItemId ?? null) : null,
				product2Id: isTrunk ? null : (payload.product2Id ?? null),
				productCode: payload.productCode ?? '',
				partDescription: payload.partDescription ?? '',
				quantity: Number(payload.partsQuantity),
				partsQuantity: Number(payload.partsQuantity),
				description: payload.description ?? '',
				usagesException: !!payload.usagesException,
				allowedUnit: payload.allowedUnit ?? null,
				billingType: this._normalizeBillingType(payload.billingType),
				discount: this._discountForBillingType(payload.billingType)
			};
		} else if (schema === 'required_product') {
			newAdd = {
				...baseAdd,
				_entity: 'ProductRequired',
				product2Id: payload.product2Id,
				quantityRequired: Number(payload.quantityRequired),
				returnable: payload.returnable ?? ''
			};
		} else if (schema === 'expense') {
			const total = this._computeTotalPrice(payload.unitPrice, payload.quantity);
			newAdd = {
				...baseAdd,
				_entity: 'Expense',
				expenseType: payload.expenseType,
				description: payload.description ?? '',
				quantity: Number(payload.quantity),
				unitPrice: Number(payload.unitPrice) || 0,
				totalPrice: total
			};
		} else if (resolvedSchema === 'travel') {
			newAdd = {
				...baseAdd,
				_entity: 'WorkOrderLineItem',
				lineType: payload.lineType,
				assignedResourceId: payload.assignedResourceId,
				assignedResourceName: this._assignedResourceNameForId(payload.assignedResourceId),
				workTypeId: payload.workTypeId || this._headerWorkTypeId() || null,
				startDate: payload.startDate || null,
				endDate: payload.endDate || null,
				billingType: BILLING_TYPE_NON_BILLABLE,
				discount: 0
			};
		} else if (resolvedSchema === 'labor') {
			newAdd = {
				...baseAdd,
				_entity: 'WorkOrderLineItem',
				lineType: payload.lineType,
				assignedResourceId: payload.assignedResourceId,
				assignedResourceName: this._assignedResourceNameForId(payload.assignedResourceId),
				workTypeId: payload.workTypeId || this._headerWorkTypeId() || null,
				quantity: Number(payload.quantity),
				billingType: BILLING_TYPE_NON_BILLABLE,
				discount: 0
			};
		} else if (schema === 'instrument') {
			newAdd = {
				...baseAdd,
				_entity: 'WorkOrderLineItem',
				_lineType: INSTRUMENT_LINE_TYPE,
				deviceTypeId: payload.deviceTypeId ?? null,
				deviceType: payload.deviceType
					|| this._productCodeByProduct2Id[payload.deviceTypeId]
					|| '',
				serviceCodeId: payload.serviceCodeId ?? null,
				repairLevel: payload.repairLevel
					|| this._repairLevelFromServiceCodeId(payload.serviceCodeId),
				quantity: Number(payload.quantity),
				billingType: this._normalizeBillingType(payload.billingType),
				discount: this._discountForBillingType(payload.billingType),
				serialNumber: payload.serialNumber ?? '',
				model: payload.model ?? '',
				departmentId: payload.departmentId ?? null,
				reportedProblem: payload.reportedProblem ?? '',
				additionalServices: !!payload.additionalServices,
				insulationPowderCoating: payload.insulationPowderCoating || [],
				replacedWithIXchange: !!payload.replacedWithIXchange,
				pictures: payload.pictures || [],
				mobilePictures: payload.mobilePictures || [],
				status: payload.status,
				canceled: payload.status === WOLI_STATUS_CANCELED
			};
		} else if (schema === 'calibration') {
			newAdd = {
				...baseAdd,
				_entity: 'WorkOrderLineItem',
				assignedResourceId: payload.assignedResourceId,
				assignedResourceName: this._assignedResourceNameForId(payload.assignedResourceId),
				assetId: payload.assetId
			};
		}

		this._pendingAdds = [...this._pendingAdds, newAdd];
		this._syncWorkOrderInProgress();
		this._closeAddForm(tab);
	}

	/**
	 * @description Handle Add Cancel.
	 */
	handleAddCancel(e) {
		this._closeAddForm(e.currentTarget.dataset.tab);
	}

	/**
	 * @description Internal helper: Close Add Form.
	 */
	_closeAddForm(tab) {
		const key = tab || this.activeTab;
		this.showAddForm = EMPTY_ADD_FORM_VISIBILITY();
		this.addFormState = this._emptyAddFormState();
		if (key) {
			const errs = { ...this.addErrors };
			delete errs[key];
			this.addErrors = errs;
		} else {
			this.addErrors = {};
		}
	}

	/**
	 * @description Handle Save All.
	 */
	async handleSaveAll() {
		if (!this.showChildDebrief) {
			return;
		}
		if (this._saving) return;
		const confirmed = await LightningConfirm.open({
			message: 'Save all changes to Salesforce?',
			variant: 'headerless',
			label: 'Confirm Save'
		});
		if (!confirmed) return;

		let hasValidationError = false;
		this._finalizeInstrumentStatuses();
		for (const [id, edit] of Object.entries(this._pendingEdits)) {
			const err = this._validateForSchema(edit._schema ?? 'generic', edit);
			if (err) {
				this.editErrors = { ...this.editErrors, [id]: err };
				hasValidationError = true;
			}
		}
		for (const a of this._pendingAdds) {
			const err = this._validateForSchema(a._schema ?? 'generic', a);
			if (err) {
				this.addErrors = {
					...this.addErrors,
					[TYPE_TO_DEF[a._lineType]?.key ?? a._lineType]: err
				};
				hasValidationError = true;
			}
		}
		if (hasValidationError) {
			this._toast('Validation Error', 'Fix highlighted errors before saving.', 'error');
			return;
		}

		this._saving = true;
		const pendingDeletes = { ...this._pendingDeletes };
		const pendingEdits = { ...this._pendingEdits };
		const pendingAdds = [...this._pendingAdds];
		const failedDeletes = {};
		const failedEdits = {};
		const failedAdds = [];
		let failedWorkOrderHeader = false;
		let savedInstrumentAdd = false;
		const okIds = [];

		for (const id of Object.keys(pendingDeletes)) {
			try {
				await deleteRecord(id);
				okIds.push(id);
				if (this._serverExpenses.some(e => e.Id === id)) this._applyExpenseDelete(id);
				else if (this._serverPartsConsumed.some(p => p.Id === id)) this._applyPartsConsumedDelete(id);
				else if (this._serverProductsRequired.some(p => p.Id === id)) this._applyProductRequiredDelete(id);
			} catch (err) {
				failedDeletes[id] = true;
			}
		}

		for (const [id, edit] of Object.entries(pendingEdits)) {
			try {
				if (edit._schema === 'parts_consumed') {
					await this._savePartsConsumedEdit(id, edit);
					okIds.push(id);
				} else if (edit._schema === 'labor') {
					const savedId = await this._saveLaborLineViaApex(id, edit);
					if (savedId) okIds.push(savedId);
				} else {
					const fields = this._buildUpdateFields(id, edit);
					if (edit._schema === 'instrument') {
						Object.assign(fields, await this._instrumentProductPersistFields(edit));
					}
					if (edit._schema === 'parts' || edit._schema === 'instrument') {
						await this._applyCourtesyProductPersistFields(fields, edit);
					}
					await updateRecord({ fields });
					okIds.push(id);
					if (edit._schema === 'instrument') {
						this._rememberRepairCenterFields(id, fields);
						await this._saveStagedLinePictures(id, edit);
					}
				}
				if (edit._schema === 'parts_consumed' && edit.workOrderLineItemId) {
					okIds.push(edit.workOrderLineItemId);
				}
				this._applyLocalUpdate(id, edit);
			} catch (err) {
				failedEdits[id] = edit;
				this.editErrors = { ...this.editErrors, [id]: this._errorMessage(err) };
			}
		}

		for (const a of pendingAdds) {
			try {
				if (a._schema === 'parts_consumed') {
					const { pcId, woliId } = await this._savePartsConsumedAdd(a);
					okIds.push(pcId, woliId);
					this._applyLocalCreate(pcId, { ...a, workOrderLineItemId: woliId });
				} else if (a._schema === 'labor') {
					const savedId = await this._saveLaborLineViaApex(null, a);
					if (savedId) {
						okIds.push(savedId);
						this._applyLocalCreate(savedId, a);
					}
				} else {
					const { apiName, fields } = this._buildCreateFields(a);
					if (a._schema === 'instrument') {
						Object.assign(fields, await this._instrumentProductPersistFields(a));
					}
					if (a._schema === 'parts' || a._schema === 'instrument') {
						await this._applyCourtesyProductPersistFields(fields, a);
					}
					const result = await createRecord({ apiName, fields });
					if (result?.id) {
						okIds.push(result.id);
						this._applyLocalCreate(result.id, a);
						if (a._schema === 'instrument') {
							savedInstrumentAdd = true;
							this._rememberRepairCenterFields(result.id, fields);
							await this._saveStagedLinePictures(result.id, a);
						}
					}
				}
			} catch (err) {
				failedAdds.push(a);
				this.editErrors = { ...this.editErrors, [a._tempId]: this._errorMessage(err) };
			}
		}

		await this._retryUnsavedPictures();

		const instrumentsValue = this._instrumentTotalForPersist(failedDeletes, failedEdits, failedAdds);
		if (this._shouldPersistTotalServicedInstruments(instrumentsValue)) {
			try {
				await updateRecord({
					fields: {
						Id: this.recordId,
						[WO_TOTAL_SERVICED_INSTRUMENTS.fieldApiName]: instrumentsValue
					}
				});
				if (this._workOrder) {
					this._workOrder = {
						...this._workOrder,
						TotalServicedInstruments__c: { value: instrumentsValue }
					};
				}
			} catch (err) {
				failedWorkOrderHeader = true;
				this._toast('Header Save Failed', this._errorMessage(err), 'error');
			}
		}

		if (savedInstrumentAdd) {
			this._statusBeforeInProgress = undefined;
			const statusNeedsSave = this._pendingWorkOrderStatus === WO_STATUS_IN_PROGRESS
				|| this._shouldMoveWorkOrderToInProgress(this._workOrder?.Status?.value);
			if (statusNeedsSave) {
				try {
					await updateRecord({
						fields: {
							Id: this.recordId,
							[WO_STATUS.fieldApiName]: WO_STATUS_IN_PROGRESS
						}
					});
					this._applyLocalWorkOrderStatus(WO_STATUS_IN_PROGRESS);
					this._pendingWorkOrderStatus = undefined;
					this._queuedWorkOrderStatus = WO_STATUS_IN_PROGRESS;
					this._holdInProgressStatus = true;
				} catch (err) {
					failedWorkOrderHeader = true;
					this._toast('Header Save Failed', this._errorMessage(err), 'error');
				}
			}
		}

		try {
			notifyRecordUpdateAvailable([{ recordId: this.recordId }, ...okIds.map(id => ({ recordId: id }))]);
		} catch (e) { /* swallow */ }
		try { await refreshGraphQL(this.graphqlResult); } catch (e) { /* swallow */ }
		try { await refreshGraphQL(this.repairCenterGraphqlResult); } catch (e) { /* swallow */ }

		this._pendingDeletes = failedDeletes;
		this._pendingEdits = failedEdits;
		this._pendingAdds = failedAdds;
		okIds.push(...await this._completeReadyInstrumentLines());
		this.editStateMap = {};
		this.showAddForm = EMPTY_ADD_FORM_VISIBILITY();
		this.addFormState = this._emptyAddFormState();
		this._saving = false;

		const anyFailed = (failedWorkOrderHeader ? 1 : 0) +
			Object.keys(failedDeletes).length +
			Object.keys(failedEdits).length +
			failedAdds.length;
		if (anyFailed === 0) {
			this._toast('Saved', `${okIds.length} change(s) saved.`, 'success');
		} else {
			const detail = this._firstSaveErrorMessage(failedEdits, failedAdds);
			this._toast('Partial Save', detail ? `${anyFailed} change(s) failed: ${detail}` : `${anyFailed} change(s) failed.`, 'warning');
		}
	}

	/**
	 * @description Handle Discard All.
	 */
	async handleDiscardAll() {
		if (!this.hasPendingChanges) {
			this.dispatchEvent(new CloseActionScreenEvent());
			return;
		}
		const confirmed = await LightningConfirm.open({
			message: 'Discard all unsaved changes?',
			variant: 'headerless',
			label: 'Confirm Discard'
		});
		if (!confirmed) return;
		this._unsavedPicturesByRecordId = {};
		this.mobilePictureVersion += 1;
		this._resetDraft();
	}

	/**
	 * @description Internal helper: Build Lines For.
	 */
	_buildLinesFor(def) {
		if (def.schema === 'parts_consumed') return this._filterLinesBySearch(this._buildPartsLines(def), def.key);
		if (def.schema === 'required_product') return this._filterLinesBySearch(this._buildRequiredLines(def), def.key);
		if (def.schema === 'expense') return this._filterLinesBySearch(this._buildExpenseLines(def), def.key);
		if (def.schema === 'time') return this._filterLinesBySearch(this._buildTimeLines(def), def.key);

		const matches = def.schema === 'instrument'
			? l => INSTRUMENT_TAB_LINE_TYPES.has(l.LineType__c?.value)
			: l => l.LineType__c?.value === def.type;
		const buildExisting = this._modelBuilderForSchema(def.schema);
		const buildAdd = this._addModelBuilderForSchema(def.schema);

		const existing = this._serverLines
			.filter(l => !this._pendingDeletes[l.Id])
			.filter(matches)
			.map(l => buildExisting.call(this, l, this._pendingEdits[l.Id], this.editStateMap[l.Id] ?? {}));

		const adds = this._pendingAdds
			.filter(a => a._schema === def.schema)
			.map(a => buildAdd.call(this, a, this.editStateMap[a._tempId] ?? {}));

		const merged = [...existing, ...adds];
		if (def.schema === 'labor') {
			merged.sort((a, b) => (a.lineNumber || '').localeCompare(b.lineNumber || ''));
		} else {
			merged.sort((a, b) => {
				const aMs = a.startDateMs ?? Number.POSITIVE_INFINITY;
				const bMs = b.startDateMs ?? Number.POSITIVE_INFINITY;
				if (aMs !== bMs) return aMs - bMs;
				return (a.lineNumber || '').localeCompare(b.lineNumber || '');
			});
		}
		return this._filterLinesBySearch(merged, def.key);
	}

	/**
	 * @description Internal helper: Build Time Lines.
	 */
	_buildTimeLines(def) {
		const existing = this._serverLines
			.filter(l => !this._pendingDeletes[l.Id])
			.filter(l => TIME_LINE_TYPES.has(l.LineType__c?.value))
			.map(l => {
				const edit = this._pendingEdits[l.Id];
				const lineType = edit?.lineType ?? l.LineType__c?.value;
				const schema = LINE_TYPE_TO_SCHEMA[lineType] ?? 'travel';
				return this._modelBuilderForSchema(schema).call(
					this,
					l,
					edit,
					this.editStateMap[l.Id] ?? {}
				);
			});

		const adds = this._pendingAdds
			.filter(a => a._schema === 'travel' || a._schema === 'labor')
			.map(a => {
				const schema = a._schema === 'labor' || a.lineType === 'Labor' ? 'labor' : 'travel';
				return this._addModelBuilderForSchema(schema).call(
					this,
					a,
					this.editStateMap[a._tempId] ?? {}
				);
			});

		const merged = [...existing, ...adds];
		merged.sort((a, b) => {
			const aMs = a.startDateMs ?? Number.POSITIVE_INFINITY;
			const bMs = b.startDateMs ?? Number.POSITIVE_INFINITY;
			if (aMs !== bMs) return aMs - bMs;
			return (a.lineNumber || '').localeCompare(b.lineNumber || '');
		});
		return merged;
	}

	/**
	 * @description Internal helper: Build Parts Lines.
	 */
	_buildPartsLines(def) {
		const buildExisting = (p, edit, state) => this._buildPartsLineModel(p, edit, state, false);
		const existing = this._serverPartsConsumed
			.filter(p => !this._pendingDeletes[p.Id])
			.map(p => buildExisting(p, this._pendingEdits[p.Id], this.editStateMap[p.Id] ?? {}));
		const adds = this._pendingAdds
			.filter(a => a._schema === def.schema)
			.map(a => this._buildPartsAddModel(a, this.editStateMap[a._tempId] ?? {}));
		return [...existing, ...adds];
	}

	/**
	 * @description Internal helper: Build Required Lines.
	 */
	_buildRequiredLines(def) {
		const existing = this._serverProductsRequired
			.filter(p => !this._pendingDeletes[p.Id])
			.map(p => this._buildRequiredLineModel(p, this._pendingEdits[p.Id], this.editStateMap[p.Id] ?? {}));
		const adds = this._pendingAdds
			.filter(a => a._schema === def.schema)
			.map(a => this._buildRequiredAddModel(a, this.editStateMap[a._tempId] ?? {}));
		return [...existing, ...adds];
	}

	/**
	 * @description Internal helper: Build Expense Lines.
	 */
	_buildExpenseLines(def) {
		const existing = this._serverExpenses
			.filter(e => !this._pendingDeletes[e.Id])
			.map(e => this._buildExpenseLineModel(e, this._pendingEdits[e.Id], this.editStateMap[e.Id] ?? {}));
		const adds = this._pendingAdds
			.filter(a => a._schema === def.schema)
			.map(a => this._buildExpenseAddModel(a, this.editStateMap[a._tempId] ?? {}));
		return [...existing, ...adds];
	}

	/**
	 * @description Internal helper: Filter Lines By Search.
	 */
	_filterLinesBySearch(lines, tabKey) {
		const term = (this.tabSearchTerms[tabKey] ?? '').trim().toLowerCase();
		const filtered = !term ? lines : lines.filter(line => this._lineMatchesSearch(line, term));
		return filtered.map(line => ({
			...line,
			cardClass: this._lineCardClass(line)
		}));
	}

	/**
	 * @description Internal helper: Line Matches Search.
	 */
	_lineMatchesSearch(line, term) {
		const haystack = [
			line.title, line.metaLine, line.lineNumber, line.description,
			line.expenseType, line.partsSource, line.returnable, line.usagesException,
			line.assignedResourceName, line.productName, line.repairCodeProductCode,
			line.laborProductCode, line.laborProductName,
			line.lineType, line.deviceType, line.repairLevel, line.model,
			line.editServiceCode, line.editDeviceType,
			line.editRepairLevel, line.deviceType, line.quantity,
			line.billingType, line.editBillingType,
			line.returnableLabel, line.editReturnableLabel,
			line.assetSerialNumber, line.startDate, line.endDate, line.totalPrice
		].filter(v => v != null && v !== '').join(' ').toLowerCase();
		return haystack.includes(term);
	}

	/**
	 * @description Internal helper: Model Builder For Schema.
	 */
	_modelBuilderForSchema(schema) {
		if (schema === 'travel') return this._buildTravelLineModel;
		if (schema === 'labor') return this._buildLaborLineModel;
		if (schema === 'instrument') return this._buildInstrumentLineModel;
		if (schema === 'calibration') return this._buildCalibrationLineModel;
		if (schema === 'parts') return this._buildPartsWoliLineModel;
		return this._buildTravelLineModel;
	}

	/**
	 * @description Internal helper: Add Model Builder For Schema.
	 */
	_addModelBuilderForSchema(schema) {
		if (schema === 'travel') return this._buildTravelAddModel;
		if (schema === 'labor') return this._buildLaborAddModel;
		if (schema === 'instrument') return this._buildInstrumentAddModel;
		if (schema === 'calibration') return this._buildCalibrationAddModel;
		if (schema === 'parts') return this._buildPartsWoliAddModel;
		return this._buildTravelAddModel;
	}

	/**
	 * @description Internal helper: Build Parts Woli Line Model.
	 */
	_buildPartsWoliLineModel(l, edit, state) {
		const assignedResId = edit?.assignedResourceId
			?? this._resolveAssignedResourceId(l.AssignedResource__c?.value);
		const assignedResName = this._assignedResourceNameForId(assignedResId)
			|| l.AssignedResource__r?.Name?.value
			|| '';
		const partsSource = edit?.partsSource
			?? l.PartsSource__c?.value
			?? PARTS_SOURCE_TRUNK;
		const isTrunkStock = partsSource === PARTS_SOURCE_TRUNK;
		const isCustomerStock = partsSource === PARTS_SOURCE_CUSTOMER;
		const productItemId = edit?.productItemId ?? l.ProductItem__c?.value ?? null;
		const product2Id = edit?.product2Id ?? l.Product__c?.value ?? null;
		const linkedProduct2Id = product2Id
			|| (productItemId ? this._product2IdByProductItemId[productItemId] : null);
		const productCode = (edit?.productCode
			?? (linkedProduct2Id ? (this._productCodeByProduct2Id[linkedProduct2Id] ?? '') : ''))
			|| '';
		const partDescription = (edit?.partDescription
			?? l.PartDescription__c?.value
			?? (linkedProduct2Id ? (this._partDescriptionByProduct2Id[linkedProduct2Id] ?? '') : ''))
			|| '';
		const productItemName = this._productItemNameByProductItemId[productItemId] ?? '';
		const productName = this._productNameByProduct2Id[product2Id]
			?? productItemName
			?? productCode
			?? '';
		const quantity = edit?.partsQuantity ?? edit?.quantity ?? l.UnitQty__c?.value ?? 0;
		const description = edit?.description ?? l.Description?.value ?? '';
		const allowedUnit = edit?.allowedUnit ?? l.AllowedUnit__c?.value ?? false;
		const returnable = edit?.returnable
			?? l.Returnable__c?.value
			?? (isCustomerStock
				? this._resolveReturnableForProduct2(product2Id)
				: this._resolveReturnableForProductItem(productItemId));
		const returnableLabel = this._fmtReturnable(returnable);
		const usagesException = edit?.usagesException ?? l.UsagesException__c?.value ?? false;
		const billingType = this._resolveBillingType(edit, state, l.BillingType__c?.value);
		return {
			Id: l.Id,
			schema: 'parts',
			isPartsSchema: true,
			isPartsConsumedSchema: false,
			isTravelSchema: false,
			isLaborSchema: false,
			isCalibrationSchema: false,
			isRequiredProductSchema: false,
			isExpenseSchema: false,
			isTrunkStock,
			isCustomerStock,
			title: productName || 'Part',
			metaLine: this._fmtPartsWoliMeta(quantity, description, usagesException, billingType),
			productName,
			productItemId,
			product2Id,
			productCode,
			partDescription,
			partsSource,
			quantity,
			description,
			allowedUnit,
			returnable,
			returnableLabel,
			usagesException,
			billingType,
			assignedResourceId: assignedResId,
			assignedResourceName: assignedResName,
			productItemFilter: this._productItemFilterForResource(
				state.assignedResourceId ?? edit?.assignedResourceId ?? assignedResId
			),
			productItemScanDisabled: !(state.assignedResourceId ?? edit?.assignedResourceId ?? assignedResId),
			isEditing: state.isEditing ?? false,
			editAssignedResId: state.assignedResourceId ?? edit?.assignedResourceId ?? assignedResId,
			editPartsSource: state.partsSource ?? edit?.partsSource ?? partsSource,
			editProductItemId: state.productItemId ?? edit?.productItemId ?? productItemId,
			editProduct2Id: state.product2Id ?? edit?.product2Id ?? product2Id,
			editProductCode: state.productCode ?? edit?.productCode ?? productCode,
			editPartDescription: state.partDescription ?? edit?.partDescription ?? partDescription,
			editPartsQuantity: state.partsQuantity ?? edit?.partsQuantity ?? edit?.quantity ?? quantity,
			editDescription: state.description ?? edit?.description ?? description,
			editAllowedUnitLabel: this._fmtReturnable(allowedUnit),
			editReturnableLabel: returnableLabel,
			editUsagesException: state.usagesException ?? edit?.usagesException ?? usagesException,
			editBillingType: state.billingType ?? edit?.billingType ?? billingType,
			editError: this.editErrors[l.Id] ?? '',
			isDirty: !!edit,
			isNew: false
		};
	}

	/**
	 * @description Internal helper: Build Parts Woli Add Model.
	 */
	_buildPartsWoliAddModel(a, state) {
		const assignedResId = state.assignedResourceId ?? a.assignedResourceId;
		const partsSource = state.partsSource ?? a.partsSource ?? PARTS_SOURCE_TRUNK;
		const isTrunkStock = partsSource === PARTS_SOURCE_TRUNK;
		const isCustomerStock = partsSource === PARTS_SOURCE_CUSTOMER;
		const productItemId = state.productItemId ?? a.productItemId;
		const product2Id = state.product2Id ?? a.product2Id;
		const linkedProduct2Id = product2Id
			|| (productItemId ? this._product2IdByProductItemId[productItemId] : null);
		const productCode = (state.productCode
			?? a.productCode
			?? (linkedProduct2Id ? (this._productCodeByProduct2Id[linkedProduct2Id] ?? '') : ''))
			|| '';
		const partDescription = (state.partDescription
			?? a.partDescription
			?? (linkedProduct2Id ? (this._partDescriptionByProduct2Id[linkedProduct2Id] ?? '') : ''))
			|| '';
		const quantity = state.partsQuantity ?? a.partsQuantity ?? a.quantity;
		const description = state.description ?? a.description ?? '';
		const usagesException = state.usagesException ?? a.usagesException ?? false;
		const billingType = this._resolveBillingType(a, state);
		const allowedUnit = state.allowedUnit ?? a.allowedUnit ?? null;
		const returnable = state.returnable
			?? a.returnable
			?? (isCustomerStock
				? this._resolveReturnableForProduct2(product2Id)
				: this._resolveReturnableForProductItem(productItemId));
		const returnableLabel = this._fmtReturnable(returnable);
		const productItemName = this._productItemNameByProductItemId[productItemId] ?? '';
		const productName = this._productNameByProduct2Id[product2Id]
			?? productItemName
			?? productCode
			?? '';
		return {
			Id: a._tempId,
			schema: 'parts',
			isPartsSchema: true,
			isPartsConsumedSchema: false,
			isTravelSchema: false,
			isLaborSchema: false,
			isCalibrationSchema: false,
			isRequiredProductSchema: false,
			isExpenseSchema: false,
			isTrunkStock,
			isCustomerStock,
			title: productName || 'Part',
			metaLine: this._fmtPartsWoliMeta(quantity, description, usagesException, billingType),
			productName,
			productItemId,
			product2Id,
			productCode,
			partDescription,
			partsSource,
			quantity,
			description,
			allowedUnit,
			returnable,
			returnableLabel,
			usagesException,
			billingType,
			productItemFilter: this._productItemFilterForResource(assignedResId),
			productItemScanDisabled: !assignedResId,
			isEditing: state.isEditing ?? false,
			editAssignedResId: assignedResId,
			editPartsSource: partsSource,
			editProductItemId: productItemId,
			editProduct2Id: product2Id,
			editProductCode: productCode,
			editPartDescription: partDescription,
			editPartsQuantity: quantity,
			editDescription: description,
			editAllowedUnitLabel: this._fmtReturnable(allowedUnit),
			editReturnableLabel: returnableLabel,
			editUsagesException: usagesException,
			editBillingType: billingType,
			editError: this.editErrors[a._tempId] ?? '',
			isDirty: false,
			isNew: true
		};
	}

	/**
	 * @description Internal helper: Build Parts Line Model.
	 */
	_buildPartsLineModel(p, edit, state) {
		const productItemId = edit?.productItemId ?? p.ProductItemId?.value ?? null;
		const product2Id = edit?.product2Id ?? p.Product2Id?.value ?? null;
		const qty = edit?.quantityConsumed ?? p.QuantityConsumed?.value ?? 0;
		const desc = edit?.description ?? p.Description?.value ?? '';
		const partsSource = edit?.partsSource ?? this._partsSourceForPart(p);
		const workOrderLineItemId = edit?.workOrderLineItemId ?? p.WorkOrderLineItemId?.value ?? null;
		const productName = p.ProductItem?.ProductName?.value
			?? p.Product2?.Name?.value
			?? this._productItemNameByProductItemId[productItemId]
			?? '';
		const resourceId = edit?.assignedResourceId ?? p.ServiceResource__c?.value ?? null;
		const resourceName = this._assignedResourceNameForId(resourceId);
		const returnable = edit?.returnable ?? p.Returnable__c?.value ?? p.Product2?.IsReturnable__c?.value ?? null;
		const returnableLabel = this._fmtReturnable(returnable);
		return {
			Id: p.Id,
			schema: 'parts_consumed',
			isPartsConsumedSchema: true,
			isTravelSchema: false,
			isLaborSchema: false,
			isCalibrationSchema: false,
			isRequiredProductSchema: false,
			isExpenseSchema: false,
			title: productName || 'Part',
			metaLine: this._fmtPartsMeta(qty, desc, returnableLabel, partsSource),
			productName,
			quantityConsumed: qty,
			description: desc,
			partsSource,
			workOrderLineItemId,
			assignedResourceId: resourceId,
			assignedResourceName: resourceName,
			returnable,
			returnableLabel,
			productItemId,
			product2Id,
			productItemFilter: this._productItemFilterForResource(state.assignedResourceId ?? edit?.assignedResourceId ?? resourceId),
			isEditing: state.isEditing ?? false,
			editAssignedResId: state.assignedResourceId ?? edit?.assignedResourceId ?? resourceId,
			editProductItemId: state.productItemId ?? edit?.productItemId ?? productItemId,
			editQuantityConsumed: state.quantityConsumed ?? edit?.quantityConsumed ?? qty,
			editDescription: state.description ?? edit?.description ?? desc,
			editPartsSource: state.partsSource ?? edit?.partsSource ?? partsSource,
			editReturnableLabel: returnableLabel,
			editError: this.editErrors[p.Id] ?? '',
			isDirty: !!edit,
			isNew: false
		};
	}

	/**
	 * @description Internal helper: Build Parts Add Model.
	 */
	_buildPartsAddModel(a, state) {
		const productItemId = state.productItemId ?? a.productItemId;
		const product2Id = state.product2Id ?? a.product2Id;
		const qty = state.quantityConsumed ?? a.quantityConsumed;
		const desc = state.description ?? a.description;
		const partsSource = state.partsSource ?? a.partsSource;
		const resourceId = state.assignedResourceId ?? a.assignedResourceId;
		const returnable = a.returnable ?? this._resolveReturnableForProductItem(productItemId);
		const returnableLabel = this._fmtReturnable(returnable);
		const productName = this._productItemNameByProductItemId[productItemId] ?? '';
		return {
			Id: a._tempId,
			schema: 'parts_consumed',
			isPartsConsumedSchema: true,
			isTravelSchema: false,
			isLaborSchema: false,
			isCalibrationSchema: false,
			isRequiredProductSchema: false,
			isExpenseSchema: false,
			title: productName || 'Part',
			metaLine: this._fmtPartsMeta(qty, desc, returnableLabel, partsSource),
			productName,
			quantityConsumed: qty,
			description: desc,
			partsSource,
			returnable,
			returnableLabel,
			productItemId,
			product2Id,
			productItemFilter: this._productItemFilterForResource(resourceId),
			isEditing: state.isEditing ?? false,
			editAssignedResId: resourceId,
			editProductItemId: productItemId,
			editQuantityConsumed: qty,
			editDescription: desc,
			editPartsSource: partsSource,
			editReturnableLabel: returnableLabel,
			editError: this.editErrors[a._tempId] ?? '',
			isDirty: false,
			isNew: true
		};
	}

	/**
	 * @description Internal helper: Build Required Line Model.
	 */
	_buildRequiredLineModel(p, edit, state) {
		const product2Id = edit?.product2Id ?? p.Product2Id?.value ?? null;
		const qty = edit?.quantityRequired ?? p.QuantityRequired?.value ?? 0;
		const productName = p.Product2?.Name?.value ?? '';
		const returnable = p.Returnable__c?.value ?? '';
		return {
			Id: p.Id,
			schema: 'required_product',
			isPartsConsumedSchema: false,
			isTravelSchema: false,
			isLaborSchema: false,
			isCalibrationSchema: false,
			isRequiredProductSchema: true,
			isExpenseSchema: false,
			title: productName || 'Product',
			metaLine: this._fmtRequiredMeta(qty, returnable),
			productName,
			product2Id,
			quantityRequired: qty,
			returnable,
			isEditing: state.isEditing ?? false,
			editProduct2Id: state.product2Id ?? edit?.product2Id ?? product2Id,
			editQuantityRequired: state.quantityRequired ?? edit?.quantityRequired ?? qty,
			editReturnable: returnable,
			editError: this.editErrors[p.Id] ?? '',
			isDirty: !!edit,
			isNew: false
		};
	}

	/**
	 * @description Internal helper: Build Required Add Model.
	 */
	_buildRequiredAddModel(a, state) {
		const product2Id = state.product2Id ?? a.product2Id;
		const qty = state.quantityRequired ?? a.quantityRequired;
		return {
			Id: a._tempId,
			schema: 'required_product',
			isPartsConsumedSchema: false,
			isTravelSchema: false,
			isLaborSchema: false,
			isCalibrationSchema: false,
			isRequiredProductSchema: true,
			isExpenseSchema: false,
			title: 'New Required Product',
			metaLine: this._fmtRequiredMeta(qty, ''),
			product2Id,
			quantityRequired: qty,
			returnable: '',
			isEditing: state.isEditing ?? false,
			editProduct2Id: product2Id,
			editQuantityRequired: qty,
			editReturnable: '',
			editError: this.editErrors[a._tempId] ?? '',
			isDirty: false,
			isNew: true
		};
	}

	/**
	 * @description Internal helper: Build Expense Line Model.
	 */
	_buildExpenseLineModel(e, edit, state) {
		const expenseType = edit?.expenseType ?? e.ExpenseType?.value ?? '';
		const description = edit?.description ?? e.Description?.value ?? '';
		const quantity = edit?.quantity ?? e.Quantity?.value ?? 0;
		const unitPrice = edit?.unitPrice ?? e.UnitPrice?.value ?? 0;
		const totalPrice = this._fmtMoney(this._computeTotalPrice(unitPrice, quantity));
		return {
			Id: e.Id,
			schema: 'expense',
			isPartsConsumedSchema: false,
			isTravelSchema: false,
			isLaborSchema: false,
			isCalibrationSchema: false,
			isRequiredProductSchema: false,
			isExpenseSchema: true,
			title: expenseType || 'Unspecified Expense',
			metaLine: this._fmtExpenseMeta(description, quantity, unitPrice, totalPrice),
			expenseType,
			description,
			quantity,
			unitPrice,
			totalPrice,
			isEditing: state.isEditing ?? false,
			editExpenseType: state.expenseType ?? edit?.expenseType ?? expenseType,
			editDescription: state.description ?? edit?.description ?? description,
			editQuantity: state.quantity ?? edit?.quantity ?? quantity,
			editUnitPrice: state.unitPrice ?? edit?.unitPrice ?? unitPrice,
			editTotalPrice: this._fmtMoney(this._computeTotalPrice(
				state.unitPrice ?? edit?.unitPrice ?? unitPrice,
				state.quantity ?? edit?.quantity ?? quantity
			)),
			editError: this.editErrors[e.Id] ?? '',
			isDirty: !!edit,
			isNew: false
		};
	}

	/**
	 * @description Internal helper: Build Expense Add Model.
	 */
	_buildExpenseAddModel(a, state) {
		const expenseType = state.expenseType ?? a.expenseType;
		const description = state.description ?? a.description;
		const quantity = state.quantity ?? a.quantity;
		const unitPrice = state.unitPrice ?? a.unitPrice;
		const totalPrice = this._fmtMoney(this._computeTotalPrice(unitPrice, quantity));
		return {
			Id: a._tempId,
			schema: 'expense',
			isPartsConsumedSchema: false,
			isTravelSchema: false,
			isLaborSchema: false,
			isCalibrationSchema: false,
			isRequiredProductSchema: false,
			isExpenseSchema: true,
			title: expenseType || 'Unspecified Expense',
			metaLine: this._fmtExpenseMeta(description, quantity, unitPrice, totalPrice),
			expenseType,
			description,
			quantity,
			unitPrice,
			totalPrice,
			isEditing: state.isEditing ?? false,
			editExpenseType: expenseType,
			editDescription: description,
			editQuantity: quantity,
			editUnitPrice: unitPrice,
			editTotalPrice: totalPrice,
			editError: this.editErrors[a._tempId] ?? '',
			isDirty: false,
			isNew: true
		};
	}

	/**
	 * @description Internal helper: Build Travel Line Model.
	 */
	_buildTravelLineModel(l, edit, state) {
		const assignedResId = edit?.assignedResourceId
			?? this._resolveAssignedResourceId(l.AssignedResource__c?.value);
		const assignedResName = this._assignedResourceNameForId(assignedResId)
			|| l.AssignedResource__r?.Name?.value
			|| '';
		const startDate = edit?.startDate ?? l.StartDate?.value ?? '';
		const endDate = edit?.endDate ?? l.EndDate?.value ?? '';
		const lineType = edit?.lineType ?? l.LineType__c?.value ?? 'Travel';
		const workTypeId = edit?.workTypeId ?? l.WorkTypeId?.value ?? null;
		const listPrice = state.listPrice ?? edit?.listPrice ?? l.ListPrice__c?.value ?? null;
		const unitPrice = state.unitPrice ?? edit?.unitPrice ?? l.UnitPrice__c?.value ?? null;
		const totalPrice = state.totalPrice ?? edit?.totalPrice ?? l.TotalPrice__c?.value ?? null;
		const base = this._buildTimeLineBase({
			id: l.Id,
			schema: 'travel',
			lineType,
			assignedResId,
			assignedResName,
			workTypeId,
			startDate,
			endDate,
			lineNumber: l.LineItemNumber?.value ?? '',
			isDirty: !!edit,
			state,
			isNew: false,
			durationFromServer: l.Duration?.value ?? null,
			billingType: this._resolveBillingType(edit, state, l.BillingType__c?.value, BILLING_TYPE_NON_BILLABLE)
		});
		return {
			...base,
			editListPriceLabel: this._fmtOptionalMoney(listPrice),
			editUnitPriceLabel: this._fmtOptionalMoney(unitPrice),
			editTotalPriceLabel: this._fmtOptionalMoney(totalPrice)
		};
	}

	/**
	 * @description Internal helper: Build Travel Add Model.
	 */
	_buildTravelAddModel(a, state) {
		const assignedResId = state.assignedResourceId ?? a.assignedResourceId;
		const startDate = state.startDate ?? a.startDate;
		const endDate = state.endDate ?? a.endDate;
		const titleName = a.assignedResourceName || this._assignedResourceNameForId(assignedResId) || 'Resource pending…';
		const listPrice = state.listPrice ?? a.listPrice ?? null;
		const unitPrice = state.unitPrice ?? a.unitPrice ?? null;
		const totalPrice = state.totalPrice ?? a.totalPrice ?? null;
		const base = this._buildTimeLineBase({
			id: a._tempId,
			schema: 'travel',
			lineType: a._lineType || a.lineType || 'Travel',
			assignedResId,
			assignedResName: titleName,
			workTypeId: state.workTypeId ?? a.workTypeId ?? null,
			startDate,
			endDate,
			lineNumber: '',
			isDirty: false,
			state,
			isNew: true,
			billingType: this._resolveBillingType(a, state, undefined, BILLING_TYPE_NON_BILLABLE)
		});
		return {
			...base,
			editListPriceLabel: this._fmtOptionalMoney(listPrice),
			editUnitPriceLabel: this._fmtOptionalMoney(unitPrice),
			editTotalPriceLabel: this._fmtOptionalMoney(totalPrice)
		};
	}

	/**
	 * @description Internal helper: Build Labor Line Model.
	 */
	_buildLaborLineModel(l, edit, state) {
		const instrument = this._laborInstrumentNode(l);
		const product2Id = this._resolveLaborProduct2Id(l, edit);
		const productCode = instrument?.ProductCode?.value ?? '';
		const productName = instrument?.Name?.value ?? '';
		const repairCodeId = edit?.repairCodeId ?? l.RepairCode__c?.value ?? null;
		const repairCodeStr = this._resolveLaborProductCode(
			repairCodeId,
			edit?.productCode ?? l.RepairCode__r?.ProductCode?.value ?? l.ProductCode__c?.value
		);
		const productDescription = this._resolveLaborProductDescription(
			product2Id,
			edit?.productDescription ?? l.ProductDescription__c?.value ?? instrument?.Description?.value
		);
		const qty = edit?.quantity ?? l.UnitQty__c?.value ?? '';
		const billingType = this._resolveBillingType(edit, state, l.BillingType__c?.value, BILLING_TYPE_NON_BILLABLE);
		const editProduct2Id = state.product2Id ?? edit?.product2Id ?? product2Id;
		const editRepairCodeId = state.repairCodeId ?? edit?.repairCodeId ?? repairCodeId;
		const lineType = edit?.lineType ?? l.LineType__c?.value ?? 'Labor';
		const listPrice = state.listPrice ?? edit?.listPrice ?? l.ListPrice__c?.value ?? null;
		const unitPrice = state.unitPrice ?? edit?.unitPrice ?? l.UnitPrice__c?.value ?? null;
		const totalPrice = state.totalPrice ?? edit?.totalPrice ?? l.TotalPrice__c?.value ?? null;
		const editLineType = state.lineType ?? lineType;
		const assignedResId = edit?.assignedResourceId
			?? this._resolveAssignedResourceId(l.AssignedResource__c?.value);
		const assignedResName = this._assignedResourceNameForId(assignedResId)
			|| l.AssignedResource__r?.Name?.value
			|| '';
		const workTypeId = edit?.workTypeId ?? l.WorkTypeId?.value ?? null;
		const title = this._laborProductLabelForId(product2Id)
			|| this._formatLaborProductLabel(productCode, productName, product2Id)
			|| assignedResName
			|| 'Labor';
		return {
			Id: l.Id,
			lineNumber: l.LineItemNumber?.value ?? '',
			schema: 'labor',
			isPartsConsumedSchema: false,
			isTimeSchema: true,
			isLaborSchema: true,
			isTravelSchema: false,
			isCalibrationSchema: false,
			isRequiredProductSchema: false,
			isExpenseSchema: false,
			isTravelLine: editLineType === 'Travel',
			isLaborLine: editLineType === 'Labor',
			lineType: editLineType,
			title,
			metaLine: this._fmtChildWoTimeMeta(editLineType, repairCodeStr, productDescription, qty),
			assignedResourceId: assignedResId,
			assignedResourceName: assignedResName,
			workTypeId,
			product2Id,
			laborProductCode: productCode,
			laborProductName: productName,
			repairCodeId,
			repairCodeProductCode: repairCodeStr,
			productDescription,
			quantity: qty,
			billingType,
			isEditing: state.isEditing ?? false,
			editLineType,
			editWorkTypeId: state.workTypeId ?? edit?.workTypeId ?? workTypeId,
			editAssignedResId: state.assignedResourceId ?? assignedResId,
			editProduct2Id,
			editRepairCodeId,
			editProductDescription: state.productDescription ?? edit?.productDescription ?? productDescription,
			editQuantity: state.quantity ?? edit?.quantity ?? qty,
			editBillingType: state.billingType ?? edit?.billingType ?? billingType,
			...this._repairCodeComboboxUiForProduct(editProduct2Id),
			editListPriceLabel: this._fmtOptionalMoney(listPrice),
			editUnitPriceLabel: this._fmtOptionalMoney(unitPrice),
			editTotalPriceLabel: this._fmtOptionalMoney(totalPrice),
			editError: this.editErrors[l.Id] ?? '',
			isDirty: !!edit,
			isNew: false
		};
	}

	/**
	 * @description Internal helper: Build Labor Add Model.
	 */
	_buildLaborAddModel(a, state) {
		const product2Id = state.product2Id ?? a.product2Id;
		const repairCodeId = state.repairCodeId ?? a.repairCodeId;
		const repairCodeStr = this._resolveLaborProductCode(repairCodeId, a.productCode);
		const productDescription = this._resolveLaborProductDescription(product2Id, a.productDescription);
		const qty = state.quantity ?? a.quantity;
		const billingType = this._resolveBillingType(a, state, undefined, BILLING_TYPE_NON_BILLABLE);
		const assignedResId = state.assignedResourceId ?? a.assignedResourceId;
		const assignedResName = a.assignedResourceName
			|| this._assignedResourceNameForId(assignedResId)
			|| '';
		const workTypeId = state.workTypeId ?? a.workTypeId ?? null;
		const productLabel = this._laborProductLabelForId(product2Id)
			|| assignedResName
			|| 'Instrument pending…';
		const lineType      = a._lineType || a.lineType || 'Labor';
		const editLineType = state.lineType ?? lineType;
		return {
			Id: a._tempId,
			lineNumber: '',
			schema: 'labor',
			isPartsConsumedSchema: false,
			isTimeSchema: true,
			isLaborSchema: true,
			isTravelSchema: false,
			isCalibrationSchema: false,
			isRequiredProductSchema: false,
			isExpenseSchema: false,
			isTravelLine: editLineType === 'Travel',
			isLaborLine: editLineType === 'Labor',
			lineType: editLineType,
			title: productLabel,
			metaLine: this._fmtChildWoTimeMeta(editLineType, repairCodeStr, productDescription, qty),
			assignedResourceId: assignedResId,
			assignedResourceName: assignedResName,
			workTypeId,
			product2Id,
			repairCodeId,
			repairCodeProductCode: repairCodeStr,
			productDescription,
			quantity: qty,
			billingType,
			isEditing: state.isEditing ?? false,
			editLineType,
			editWorkTypeId: workTypeId,
			editAssignedResId: assignedResId,
			editProduct2Id: product2Id,
			editRepairCodeId: repairCodeId,
			editProductDescription: productDescription,
			editQuantity: qty,
			editBillingType: billingType,
			...this._repairCodeComboboxUiForProduct(product2Id),
			editListPriceLabel: this._fmtOptionalMoney(state.listPrice ?? a.listPrice ?? null),
			editUnitPriceLabel: this._fmtOptionalMoney(state.unitPrice ?? a.unitPrice ?? null),
			editTotalPriceLabel: this._fmtOptionalMoney(state.totalPrice ?? a.totalPrice ?? null),
			editError: this.editErrors[a._tempId] ?? '',
			isDirty: false,
			isNew: true
		};
	}

	/**
	 * @description Internal helper: Build Instrument Line Model.
	 */
	_buildInstrumentLineModel(l, edit, state) {
		const deviceTypeId = state.deviceTypeId
			?? edit?.deviceTypeId
			?? l.Product2Id?.value
			?? l.Product2?.Id
			?? null;
		const deviceType = state.deviceType
			?? edit?.deviceType
			?? l.DeviceType__c?.value
			?? l.Product2?.ProductCode?.value
			?? this._productCodeByProduct2Id[deviceTypeId]
			?? '';
		const repairLevel = state.repairLevel
			?? edit?.repairLevel
			?? l.RepairLevel__c?.value
			?? '';
		const quantity = state.quantity
			?? edit?.quantity
			?? l.Quantity?.value
			?? '';
		const serviceCodeId = state.serviceCodeId
			?? edit?.serviceCodeId
			?? this._savedServiceCodeId(deviceTypeId, repairLevel, this._repairCenterByLineId[l.Id])
			?? null;
		const billingType = this._resolveBillingType(edit, state, l.BillingType__c?.value);
		const productName = l.Product2?.Name?.value
			|| this._productNameByProduct2Id[deviceTypeId]
			|| '';
		void this.productMetaVersion;
		return {
			Id: l.Id,
			lineNumber: l.LineItemNumber?.value ?? '',
			schema: 'instrument',
			isPartsConsumedSchema: false,
			isTimeSchema: false,
			isInstrumentSchema: true,
			isLaborSchema: false,
			isTravelSchema: false,
			isCalibrationSchema: false,
			isRequiredProductSchema: false,
			isExpenseSchema: false,
			isTravelLine: false,
			isLaborLine: false,
			title: productName || deviceType || 'Instrument',
			metaLine: this._instrumentSummaryMeta({
				quantity,
				serviceCodeId,
				deviceTypeId,
				repairLevel,
				billingType
			}) || 'Instrument line',
			deviceTypeId,
			deviceType,
			serviceCodeId,
			repairLevel,
			quantity,
			billingType,
			...this._instrumentPresentation(edit?.status ?? l.Status?.value, {
				deviceTypeId,
				serviceCodeId,
				repairLevel,
				quantity,
				serialNumber: edit?.serialNumber ?? this._repairCenterByLineId[l.Id]?.serialNumber,
				model: edit?.model ?? l.Model__c?.value ?? this._repairCenterByLineId[l.Id]?.model,
				departmentId: edit?.departmentId ?? this._repairCenterByLineId[l.Id]?.departmentId,
				reportedProblem: edit?.reportedProblem ?? this._repairCenterByLineId[l.Id]?.reportedProblem,
				sendToRepairCenter: !!this._repairCenterByLineId[l.Id]?.sendToRepairCenter
			}),
			isEditing: state.isEditing ?? false,
			editDeviceTypeId: deviceTypeId,
			editDeviceType: deviceType,
			editServiceCodeId: serviceCodeId,
			editRepairLevel: repairLevel || '—',
			editQuantity: quantity,
			editBillingType: state.billingType ?? edit?.billingType ?? billingType,
			serviceCodePickerDisabled: !deviceTypeId,
			...this._serviceCodeComboboxUiForDeviceType(deviceTypeId, serviceCodeId),
			...this._repairCenterFieldModel(l.Id, serviceCodeId, edit, this._repairCenterByLineId[l.Id]),
			...this._mobilePictureModel(l.Id),
			editError: this.editErrors[l.Id] ?? '',
			isDirty: !!edit,
			isNew: false
		};
	}

	/**
	 * @description Internal helper: Build Instrument Add Model.
	 */
	_buildInstrumentAddModel(a, state) {
		const deviceTypeId = state.deviceTypeId ?? a.deviceTypeId ?? null;
		const deviceType = state.deviceType
			?? a.deviceType
			?? this._productCodeByProduct2Id[deviceTypeId]
			?? '';
		const serviceCodeId = state.serviceCodeId ?? a.serviceCodeId ?? null;
		const repairLevel = state.repairLevel
			?? a.repairLevel
			?? this._repairLevelFromServiceCodeId(serviceCodeId)
			?? '';
		const quantity = state.quantity ?? a.quantity ?? '';
		const billingType = this._resolveBillingType(a, state);
		const productName = this._productNameByProduct2Id[deviceTypeId] || '';
		void this.productMetaVersion;
		return {
			Id: a._tempId,
			lineNumber: '',
			schema: 'instrument',
			isPartsConsumedSchema: false,
			isTimeSchema: false,
			isInstrumentSchema: true,
			isLaborSchema: false,
			isTravelSchema: false,
			isCalibrationSchema: false,
			isRequiredProductSchema: false,
			isExpenseSchema: false,
			isTravelLine: false,
			isLaborLine: false,
			title: productName || deviceType || 'Instrument',
			metaLine: this._instrumentSummaryMeta({
				quantity,
				serviceCodeId,
				deviceTypeId,
				repairLevel,
				billingType
			}) || 'New instrument line',
			deviceTypeId,
			deviceType,
			serviceCodeId,
			repairLevel,
			quantity,
			billingType,
			...this._instrumentPresentation(a.status, {
				deviceTypeId,
				serviceCodeId,
				repairLevel,
				quantity,
				serialNumber: state.serialNumber ?? a.serialNumber,
				model: state.model ?? a.model,
				departmentId: state.departmentId ?? a.departmentId,
				reportedProblem: state.reportedProblem ?? a.reportedProblem,
				sendToRepairCenter: false
			}),
			isEditing: state.isEditing ?? false,
			editDeviceTypeId: deviceTypeId,
			editDeviceType: deviceType,
			editServiceCodeId: serviceCodeId,
			editRepairLevel: repairLevel || '—',
			editQuantity: quantity,
			editBillingType: billingType,
			serviceCodePickerDisabled: !deviceTypeId,
			...this._serviceCodeComboboxUiForDeviceType(deviceTypeId, serviceCodeId),
			...this._repairCenterFieldModel(a._tempId, serviceCodeId, { ...a, ...state }, null),
			...this._mobilePictureModel(a._tempId, a.mobilePictures),
			editError: this.editErrors[a._tempId] ?? '',
			isDirty: false,
			isNew: true
		};
	}

	/**
	 * @description Internal helper: Build Calibration Line Model.
	 */
	_buildCalibrationLineModel(l, edit, state) {
		const assignedResId = edit?.assignedResourceId ?? l.AssignedResource__c?.value ?? null;
		const assignedResName = l.AssignedResource__r?.Name?.value ?? '';
		const assetId = edit?.assetId ?? l.AssetId?.value ?? null;
		const assetSerial = l.Asset?.SerialNumber?.value ?? '';
		const base = this._buildTimeLineBase({
			id: l.Id,
			schema: 'calibration',
			assignedResId,
			assignedResName,
			startDate: '',
			endDate: '',
			lineNumber: l.LineItemNumber?.value ?? '',
			isDirty: !!edit,
			state,
			isNew: false
		});
		return {
			...base,
			isCalibrationSchema: true,
			metaLine: this._fmtCalibrationMeta(assetSerial),
			assetId,
			assetSerialNumber: assetSerial,
			editAssetId: state.assetId ?? edit?.assetId ?? assetId
		};
	}

	/**
	 * @description Internal helper: Build Calibration Add Model.
	 */
	_buildCalibrationAddModel(a, state) {
		const assignedResId = state.assignedResourceId ?? a.assignedResourceId;
		const assetId = state.assetId ?? a.assetId;
		const titleName = a.assignedResourceName || this._assignedResourceNameForId(assignedResId) || 'Resource pending…';
		const base = this._buildTimeLineBase({
			id: a._tempId,
			schema: 'calibration',
			assignedResId,
			assignedResName: titleName,
			startDate: '',
			endDate: '',
			lineNumber: '',
			isDirty: false,
			state,
			isNew: true
		});
		return {
			...base,
			isCalibrationSchema: true,
			metaLine: this._fmtCalibrationMeta(''),
			assetId,
			editAssetId: assetId
		};
	}

	_buildTimeLineBase({
		id,
		schema,
		lineType = '',
		assignedResId,
		assignedResName,
		workTypeId = null,
		startDate,
		endDate,
		lineNumber,
		isDirty,
		state,
		isNew,
		durationFromServer = null,
		billingType = BILLING_TYPE_NON_BILLABLE
	}) {
		const isTravel = schema === 'travel';
		const isLabor = schema === 'labor';
		const isTime = isTravel || isLabor;
		const flags = {
			isPartsConsumedSchema: false,
			isTravelSchema: isTravel,
			isLaborSchema: isLabor,
			isTimeSchema: isTime,
			isInstrumentSchema: false,
			isCalibrationSchema: schema === 'calibration',
			isRequiredProductSchema: false,
			isExpenseSchema: false
		};
		const editLineType = state.lineType ?? lineType;
		const effectiveStart = state.startDate ?? startDate ?? '';
		const effectiveEnd = state.endDate ?? endDate ?? '';
		const durationHours = state.durationHours != null && state.durationHours !== ''
			? Number(state.durationHours)
			: (this._computeDurationHours(effectiveStart, effectiveEnd) ?? durationFromServer);
		const effectiveLineType = editLineType || (isTravel ? 'Travel' : isLabor ? 'Labor' : '');
		const resolvedBillingType = BILLING_TYPE_NON_BILLABLE;
		return {
			Id: id,
			lineNumber,
			schema,
			...flags,
			title: assignedResName || 'Unassigned',
			metaLine: isTravel
				? this._fmtChildWoTimeMeta(effectiveLineType, '', '', '', startDate, endDate)
				: this._fmtTravelMeta(startDate, endDate),
			lineType: effectiveLineType,
			workTypeId,
			assignedResourceId: assignedResId,
			assignedResourceName: assignedResName,
			startDate,
			endDate,
			durationHours,
			billingType: resolvedBillingType,
			startDateMs: this._toMs(startDate),
			isEditing: state.isEditing ?? false,
			editLineType: effectiveLineType,
			isTravelLine: effectiveLineType === 'Travel',
			isLaborLine: effectiveLineType === 'Labor',
			editWorkTypeId: state.workTypeId ?? workTypeId ?? null,
			editAssignedResId: state.assignedResourceId ?? assignedResId,
			editStartDate: state.startDate ?? startDate ?? '',
			editEndDate: state.endDate ?? endDate ?? '',
			editDurationHours: durationHours ?? '',
			editDurationLabel: this._fmtDurationLabel(durationHours),
			editBillingType: resolvedBillingType,
			editError: this.editErrors[id] ?? '',
			isDirty,
			isNew
		};
	}

	/**
	 * @description Internal helper: Build Update Fields.
	 */
	_buildUpdateFields(id, edit) {
		const schema = edit._schema;
		if (schema === 'parts_consumed') {
			return {
				Id: id,
				[PC_QUANTITY.fieldApiName]: Number(edit.quantityConsumed) || 0,
				[PC_DESCRIPTION.fieldApiName]: edit.description ?? '',
				[PC_SERVICE_RESOURCE.fieldApiName]: edit.assignedResourceId,
				...(edit.returnable != null ? { [PC_RETURNABLE.fieldApiName]: edit.returnable } : {})
			};
		}
		if (schema === 'parts') {
			const partsSource = edit.partsSource ?? PARTS_SOURCE_TRUNK;
			const isTrunk = partsSource === PARTS_SOURCE_TRUNK;
			const qty = Number(edit.quantity ?? edit.partsQuantity) || 0;
			return {
				Id: id,
				[WOLI_ASSIGNED_RES.fieldApiName]: edit.assignedResourceId,
				[WOLI_PARTS_SOURCE.fieldApiName]: partsSource,
				[WOLI_PRODUCT_ITEM.fieldApiName]: isTrunk ? (edit.productItemId ?? null) : null,
				[WOLI_PRODUCT.fieldApiName]: isTrunk ? null : (edit.product2Id ?? null),
				[WOLI_PART_DESCRIPTION.fieldApiName]: edit.partDescription ?? '',
				[WOLI_UNIT_QTY.fieldApiName]: qty,
				[WOLI_QUANTITY.fieldApiName]: qty,
				[WOLI_DESCRIPTION.fieldApiName]: edit.description ?? '',
				[WOLI_USAGES_EXCEPTION.fieldApiName]: !!edit.usagesException,
				...(edit.allowedUnit != null
					? { [WOLI_ALLOWED_UNIT.fieldApiName]: !!edit.allowedUnit }
					: {}),
				...(edit.returnable != null
					? { [WOLI_RETURNABLE.fieldApiName]: !!edit.returnable }
					: {}),
				...this._buildBillingPersistFields(edit, true)
			};
		}
		if (schema === 'labor') {
			return {
				Id: id,
				[WOLI_LINETYPE.fieldApiName]: edit.lineType || 'Labor',
				[WOLI_ASSIGNED_RES.fieldApiName]: edit.assignedResourceId,
				[WOLI_WORKTYPE.fieldApiName]: edit.workTypeId || null,
				...this._buildLaborPersistFields(edit)
			};
		}
		if (schema === 'instrument') {
			return {
				Id: id,
				[WOLI_LINETYPE.fieldApiName]: INSTRUMENT_LINE_TYPE,
				...this._buildInstrumentPersistFields(edit),
				...this._buildBillingPersistFields(edit, true)
			};
		}
		if (schema === 'travel') {
			const durationHours = edit.durationHours != null && edit.durationHours !== ''
				? Number(edit.durationHours)
				: this._computeDurationHours(edit.startDate, edit.endDate);
			const durationFields = this._buildDurationFields(edit.startDate, edit.endDate);
			return {
				Id: id,
				[WOLI_LINETYPE.fieldApiName]: edit.lineType || 'Travel',
				[WOLI_ASSIGNED_RES.fieldApiName]: edit.assignedResourceId,
				[WOLI_WORKTYPE.fieldApiName]: edit.workTypeId || null,
				[WOLI_STARTDATE.fieldApiName]: edit.startDate || null,
				[WOLI_ENDDATE.fieldApiName]: edit.endDate || null,
				...durationFields,
				...(durationHours != null && !Number.isNaN(durationHours)
					? { [WOLI_UNIT_QTY.fieldApiName]: durationHours }
					: {}),
				...this._buildTimeBillingPersistFields()
			};
		}
		return { Id: id };
	}

	/**
	 * @description Internal helper: Build Create Fields.
	 */
	_buildCreateFields(a) {
		const schema = a._schema;
		if (schema === 'parts_consumed') {
			return this._buildProductConsumedCreateFields(a);
		}
		if (schema === 'parts') {
			const partsSource = a.partsSource ?? PARTS_SOURCE_TRUNK;
			const isTrunk = partsSource === PARTS_SOURCE_TRUNK;
			const qty = Number(a.quantity ?? a.partsQuantity) || 0;
			return {
				apiName: WOLI_OBJECT.objectApiName,
				fields: {
					[WOLI_WORKORDERID.fieldApiName]: this.recordId,
					[WOLI_LINETYPE.fieldApiName]: 'Parts',
					[WOLI_ASSIGNED_RES.fieldApiName]: a.assignedResourceId,
					[WOLI_PARTS_SOURCE.fieldApiName]: partsSource,
					[WOLI_PRODUCT_ITEM.fieldApiName]: isTrunk ? (a.productItemId ?? null) : null,
					[WOLI_PRODUCT.fieldApiName]: isTrunk ? null : (a.product2Id ?? null),
					[WOLI_PART_DESCRIPTION.fieldApiName]: a.partDescription ?? '',
					[WOLI_UNIT_QTY.fieldApiName]: qty,
					[WOLI_QUANTITY.fieldApiName]: qty,
					[WOLI_DESCRIPTION.fieldApiName]: a.description ?? '',
					[WOLI_USAGES_EXCEPTION.fieldApiName]: !!a.usagesException,
					...(a.allowedUnit != null
						? { [WOLI_ALLOWED_UNIT.fieldApiName]: !!a.allowedUnit }
						: {}),
					...(a.returnable != null
						? { [WOLI_RETURNABLE.fieldApiName]: !!a.returnable }
						: {}),
					...this._buildBillingPersistFields(a, true)
				}
			};
		}
		if (schema === 'labor') {
			return {
				apiName: WOLI_OBJECT.objectApiName,
				fields: {
					[WOLI_WORKORDERID.fieldApiName]: this.recordId,
					[WOLI_LINETYPE.fieldApiName]: a._lineType,
					[WOLI_ASSIGNED_RES.fieldApiName]: a.assignedResourceId,
					[WOLI_WORKTYPE.fieldApiName]: a.workTypeId || null,
					...this._buildLaborPersistFields(a)
				}
			};
		}
		if (schema === 'instrument') {
			return {
				apiName: WOLI_OBJECT.objectApiName,
				fields: {
					[WOLI_WORKORDERID.fieldApiName]: this.recordId,
					[WOLI_LINETYPE.fieldApiName]: INSTRUMENT_LINE_TYPE,
					...this._buildInstrumentPersistFields(a),
					...this._buildBillingPersistFields(a, true)
				}
			};
		}
		if (schema === 'travel') {
			const durationFields = this._buildDurationFields(a.startDate, a.endDate);
			const durationHours = a.durationHours != null && a.durationHours !== ''
				? Number(a.durationHours)
				: this._computeDurationHours(a.startDate, a.endDate);
			return {
				apiName: WOLI_OBJECT.objectApiName,
				fields: {
					[WOLI_WORKORDERID.fieldApiName]: this.recordId,
					[WOLI_LINETYPE.fieldApiName]: a._lineType,
					[WOLI_ASSIGNED_RES.fieldApiName]: a.assignedResourceId,
					[WOLI_WORKTYPE.fieldApiName]: a.workTypeId || null,
					[WOLI_STARTDATE.fieldApiName]: a.startDate || null,
					[WOLI_ENDDATE.fieldApiName]: a.endDate || null,
					...durationFields,
					...(durationHours != null && !Number.isNaN(durationHours)
						? { [WOLI_UNIT_QTY.fieldApiName]: durationHours }
						: {}),
					...this._buildTimeBillingPersistFields()
				}
			};
		}
		return { apiName: WOLI_OBJECT.objectApiName, fields: { [WOLI_WORKORDERID.fieldApiName]: this.recordId } };
	}

	/**
	 * @description Internal helper: Build Woli Parts Fields.
	 */
	_buildWoliPartsFields(partsSource, assignedResourceId) {
		return {
			[WOLI_WORKORDERID.fieldApiName]: this.recordId,
			[WOLI_LINETYPE.fieldApiName]: 'Parts',
			[WOLI_PARTS_SOURCE.fieldApiName]: partsSource ?? null,
			[WOLI_ASSIGNED_RES.fieldApiName]: assignedResourceId
		};
	}

	/**
	 * @description Internal helper: Build Product Consumed Create Fields.
	 */
	_buildProductConsumedCreateFields(a, workOrderLineItemId = null) {
		return {
			apiName: PC_OBJECT.objectApiName,
			fields: {
				[PC_WORKORDER.fieldApiName]: this.recordId,
				[PC_PRODUCTITEM.fieldApiName]: a.productItemId,
				[PC_QUANTITY.fieldApiName]: Number(a.quantityConsumed) || 0,
				[PC_DESCRIPTION.fieldApiName]: a.description ?? '',
				[PC_SERVICE_RESOURCE.fieldApiName]: a.assignedResourceId,
				...(workOrderLineItemId ? { [PC_WORKORDER_LINE_ITEM.fieldApiName]: workOrderLineItemId } : {}),
				...(a.returnable != null ? { [PC_RETURNABLE.fieldApiName]: a.returnable } : {})
			}
		};
	}

	/**
	 * @description Internal helper: Save Parts Consumed Add.
	 */
	async _savePartsConsumedAdd(a) {
		const woliResult = await createRecord({
			apiName: WOLI_OBJECT.objectApiName,
			fields: this._buildWoliPartsFields(a.partsSource, a.assignedResourceId)
		});
		const woliId = woliResult.id;
		const { apiName, fields } = this._buildProductConsumedCreateFields(a, woliId);
		const pcResult = await createRecord({ apiName, fields });
		this._cachePartsSource(woliId, a.partsSource ?? '');
		return { pcId: pcResult.id, woliId };
	}

	/**
	 * @description Internal helper: Save Parts Consumed Edit.
	 */
	async _savePartsConsumedEdit(pcId, edit) {
		await updateRecord({ fields: this._buildUpdateFields(pcId, edit) });

		let woliId = edit.workOrderLineItemId ?? null;
		const partsSource = edit.partsSource ?? null;

		if (woliId) {
			await updateRecord({
				fields: {
					Id: woliId,
					[WOLI_PARTS_SOURCE.fieldApiName]: partsSource,
					[WOLI_ASSIGNED_RES.fieldApiName]: edit.assignedResourceId
				}
			});
		} else {
			const woliResult = await createRecord({
				apiName: WOLI_OBJECT.objectApiName,
				fields: this._buildWoliPartsFields(partsSource, edit.assignedResourceId)
			});
			woliId = woliResult.id;
			await updateRecord({
				fields: {
					Id: pcId,
					[PC_WORKORDER_LINE_ITEM.fieldApiName]: woliId
				}
			});
			edit.workOrderLineItemId = woliId;
		}

		this._cachePartsSource(woliId, partsSource ?? '');
	}

	/**
	 * @description Internal helper: Parts Source For Part.
	 */
	_partsSourceForPart(p) {
		const woliId = p.WorkOrderLineItemId?.value ?? null;
		return p.WorkOrderLineItem?.PartsSource__c?.value
			?? (woliId ? this._partsSourceByWoliId[woliId] : null)
			?? '';
	}

	/**
	 * @description Internal helper: Seed Parts Source Cache From Lines.
	 */
	_seedPartsSourceCacheFromLines(lines) {
		const next = { ...this._partsSourceByWoliId };
		for (const line of lines ?? []) {
			const id = line.Id;
			if (!id) continue;
			next[id] = line.PartsSource__c?.value ?? '';
		}
		this._partsSourceByWoliId = next;
	}

	/**
	 * @description Internal helper: Cache Parts Source.
	 */
	_cachePartsSource(woliId, partsSource) {
		if (!woliId) return;
		this._partsSourceByWoliId = { ...this._partsSourceByWoliId, [woliId]: partsSource ?? '' };
	}

	/**
	 * @description Internal helper: Stage Edit.
	 */
	_stageEdit(id, field, value) {
		if (this._pendingAdds.some(a => a._tempId === id)) {
			this._pendingAdds = this._pendingAdds.map(a => {
				if (a._tempId !== id) return a;
				const next = { ...a, [field]: value };
				if (field === 'productItemId') {
					if (a._schema === 'parts') {
						if (value) next.product2Id = null;
						const linkedProduct2Id = value
							? (this._product2IdByProductItemId[value] ?? null)
							: null;
						next.returnable = value
							? (this._resolveReturnableForProductItem(value) ?? null)
							: null;
						next.productCode = linkedProduct2Id
							? (this._productCodeByProduct2Id[linkedProduct2Id] ?? '')
							: (value ? '' : (next.productCode ?? ''));
						next.partDescription = linkedProduct2Id
							? (this._partDescriptionByProduct2Id[linkedProduct2Id] ?? '')
							: (value ? '' : (next.partDescription ?? ''));
						if (value) {
							next.allowedUnit = null;
						}
					} else {
						next.product2Id = value
							? (this._product2IdByProductItemId[value] ?? null)
							: null;
						next.returnable = value
							? (this._resolveReturnableForProductItem(value) ?? null)
							: null;
						next.allowedUnit = null;
					}
				}
				if (field === 'partsQuantity') {
					next.quantity = value;
				}
				if (field === 'billingType') {
					next.discount = this._discountForBillingType(value);
				}
				if (field === 'repairCodeId') {
					next.productCode = value ? (this._resolveProductCodeForRepairCode(value) ?? '') : '';
					if (value) this._repairCodeLookupId = value;
				}
				if (field === 'product2Id' && a._schema === 'parts') {
					if (value) next.productItemId = null;
					next.returnable = value
						? (this._resolveReturnableForProduct2(value) ?? null)
						: null;
					next.productCode = value
						? (this._productCodeByProduct2Id[value] ?? '')
						: (next.productCode ?? '');
					next.partDescription = value
						? (this._partDescriptionByProduct2Id[value] ?? '')
						: (next.partDescription ?? '');
					if (value) {
						next.allowedUnit = null;
						this._product2LookupId = value;
					}
				}
				if (field === 'product2Id' && a._schema === 'labor') {
					next.repairCodeId = null;
					next.productCode = '';
					next.laborPartProductCode = value
						? (this._laborPartProductCodeById[value] ?? '')
						: '';
					next.productDescription = value
						? (this._laborPartDescriptionById[value] ?? '')
						: '';
					this._onLaborProductSelected(value);
				}
				if (field === 'lineType') {
					next._lineType = value;
					next._schema = LINE_TYPE_TO_SCHEMA[value] ?? next._schema;
					next.lineType = value;
					if (value === 'Travel') {
						next.product2Id = null;
						next.repairCodeId = null;
						next.productCode = '';
						next.laborPartProductCode = '';
						next.productDescription = '';
						next.quantity = '';
					} else if (value === 'Labor') {
						next.startDate = null;
						next.endDate = null;
					}
				}
				if (field === 'unitPrice' || field === 'quantity') {
					next.totalPrice = this._computeTotalPrice(
						field === 'unitPrice' ? value : next.unitPrice,
						field === 'quantity' ? value : next.quantity
					);
				}
				return next;
			});
			return;
		}

		const expense = this._serverExpenses.find(e => e.Id === id);
		if (expense) {
			let entry = this._mergeEdit(id, this._seedExpenseEditEntry(expense), field, value);
			if (field === 'unitPrice' || field === 'quantity') {
				entry.totalPrice = this._computeTotalPrice(entry.unitPrice, entry.quantity);
			}
			this._pendingEdits = { ...this._pendingEdits, [id]: entry };
			return;
		}
		const part = this._serverPartsConsumed.find(p => p.Id === id);
		if (part) {
			const entry = this._mergeEdit(id, this._seedPartsEditEntry(part), field, value);
			if (field === 'productItemId') {
				entry.product2Id = value ? (this._product2IdByProductItemId[value] ?? entry.product2Id) : null;
				entry.returnable = value ? (this._resolveReturnableForProductItem(value) ?? entry.returnable) : null;
			}
			this._pendingEdits = { ...this._pendingEdits, [id]: entry };
			return;
		}
		// fall through to WOLI line edits (including Parts)
		const required = this._serverProductsRequired.find(p => p.Id === id);
		if (required) {
			const entry = this._mergeEdit(id, this._seedRequiredEditEntry(required), field, value);
			this._pendingEdits = { ...this._pendingEdits, [id]: entry };
			return;
		}
		const line = this._serverLines.find(l => l.Id === id);
		if (!line) return;
		let entry = this._mergeEdit(id, this._seedEditEntry(line), field, value);
		if (field === 'productItemId') {
			if (value) entry.product2Id = null;
			entry.returnable = value ? (this._resolveReturnableForProductItem(value) ?? null) : null;
			const linkedProduct2Id = value ? (this._product2IdByProductItemId[value] ?? null) : null;
			entry.productCode = linkedProduct2Id
				? (this._productCodeByProduct2Id[linkedProduct2Id] ?? '')
				: (value ? '' : (entry.productCode ?? ''));
			entry.partDescription = linkedProduct2Id
				? (this._partDescriptionByProduct2Id[linkedProduct2Id] ?? '')
				: (value ? '' : (entry.partDescription ?? ''));
			if (value) {
				entry.allowedUnit = null;
			}
		}
		if (field === 'partsQuantity') {
			entry.quantity = value;
		}
		if (field === 'billingType') {
			entry.discount = this._discountForBillingType(value);
		}
		if (field === 'repairCodeId') {
			entry.productCode = value ? (this._resolveProductCodeForRepairCode(value) ?? entry.productCode ?? '') : '';
			if (value) this._repairCodeLookupId = value;
		}
		if (field === 'product2Id' && entry._schema === 'parts') {
			if (value) entry.productItemId = null;
			entry.returnable = value ? (this._resolveReturnableForProduct2(value) ?? null) : null;
			entry.productCode = value
				? (this._productCodeByProduct2Id[value] ?? '')
				: (entry.productCode ?? '');
			entry.partDescription = value
				? (this._partDescriptionByProduct2Id[value] ?? '')
				: (entry.partDescription ?? '');
			if (value) {
				entry.allowedUnit = null;
				this._product2LookupId = value;
			}
		}
		if (field === 'product2Id' && entry._schema === 'labor') {
			entry.repairCodeId = null;
			entry.productCode = '';
			entry.laborPartProductCode = value
				? (this._laborPartProductCodeById[value] ?? entry.laborPartProductCode ?? '')
				: '';
			entry.productDescription = value
				? (this._laborPartDescriptionById[value] ?? entry.productDescription ?? '')
				: '';
			this._onLaborProductSelected(value);
		}
		if (field === 'lineType') {
			entry._schema = LINE_TYPE_TO_SCHEMA[value] ?? entry._schema;
			entry._lineType = value;
			if (value === 'Travel') {
				entry.product2Id = null;
				entry.repairCodeId = null;
				entry.productCode = '';
				entry.laborPartProductCode = '';
				entry.productDescription = '';
				entry.quantity = '';
			} else if (value === 'Labor') {
				entry.startDate = null;
				entry.endDate = null;
			}
		}
		this._pendingEdits = { ...this._pendingEdits, [id]: entry };
	}

	/**
	 * @description Internal helper: Merge Edit.
	 */
	_mergeEdit(id, seed, field, value) {
		const existing = this._pendingEdits[id];
		return existing ? { ...existing, [field]: value } : { ...seed, [field]: value };
	}

	/**
	 * @description Internal helper: Seed Parts Edit Entry.
	 */
	_seedPartsEditEntry(p) {
		const productItemId = p.ProductItemId?.value ?? null;
		const product2Id = p.Product2Id?.value ?? null;
		return {
			_schema: 'parts_consumed',
			_entity: 'ProductConsumed',
			assignedResourceId: p.ServiceResource__c?.value ?? null,
			productItemId,
			product2Id,
			returnable: p.Returnable__c?.value ?? p.Product2?.IsReturnable__c?.value ?? null,
			quantityConsumed: p.QuantityConsumed?.value ?? 0,
			description: p.Description?.value ?? '',
			partsSource: this._partsSourceForPart(p),
			workOrderLineItemId: p.WorkOrderLineItemId?.value ?? null
		};
	}

	/**
	 * @description Internal helper: Seed Required Edit Entry.
	 */
	_seedRequiredEditEntry(p) {
		return {
			_schema: 'required_product',
			_entity: 'ProductRequired',
			product2Id: p.Product2Id?.value ?? null,
			quantityRequired: p.QuantityRequired?.value ?? 0,
			returnable: p.Returnable__c?.value ?? ''
		};
	}

	/**
	 * @description Internal helper: Seed Expense Edit Entry.
	 */
	_seedExpenseEditEntry(e) {
		return {
			_schema: 'expense',
			_entity: 'Expense',
			expenseType: e.ExpenseType?.value ?? '',
			description: e.Description?.value ?? '',
			quantity: e.Quantity?.value ?? 0,
			unitPrice: e.UnitPrice?.value ?? 0,
			totalPrice: e.TotalPrice?.value ?? e.Amount?.value ?? 0
		};
	}

	/**
	 * @description Internal helper: Seed Edit Entry.
	 */
	_seedEditEntry(line) {
		const lineType = line.LineType__c?.value ?? null;
		const schema = this._schemaForLineType(lineType);
		const base = {
			lineType,
			assignedResourceId: this._resolveAssignedResourceId(line.AssignedResource__c?.value),
			workTypeId: line.WorkTypeId?.value ?? null,
			startDate: line.StartDate?.value ?? '',
			endDate: line.EndDate?.value ?? '',
			billingType: this._normalizeBillingType(
				line.BillingType__c?.value,
				schema === 'labor' || schema === 'travel' ? BILLING_TYPE_NON_BILLABLE : BILLING_TYPE_BILLABLE
			),
			discount: this._discountForBillingType(line.BillingType__c?.value)
		};
		if (schema === 'labor') {
			return {
				_schema: 'labor',
				_entity: 'WorkOrderLineItem',
				_lineType: lineType,
				...base,
				quantity: line.UnitQty__c?.value ?? ''
			};
		}
		if (schema === 'instrument') {
			const deviceTypeId = line.Product2Id?.value ?? line.Product2?.Id ?? null;
			const repairLevel = line.RepairLevel__c?.value ?? '';
			return {
				_schema: 'instrument',
				_entity: 'WorkOrderLineItem',
				_lineType: INSTRUMENT_LINE_TYPE,
				deviceTypeId,
				deviceType: line.DeviceType__c?.value
					?? line.Product2?.ProductCode?.value
					?? '',
				serviceCodeId: this._savedServiceCodeId(deviceTypeId, repairLevel, this._repairCenterByLineId[line.Id]),
				repairLevel,
				quantity: line.Quantity?.value ?? '',
				status: line.Status?.value ?? 'New',
				sendToRepairCenter: !!this._repairCenterByLineId[line.Id]?.sendToRepairCenter,
				serialNumber: line.SerialNumber__c?.value ?? this._repairCenterByLineId[line.Id]?.serialNumber ?? '',
				model: line.Model__c?.value ?? this._repairCenterByLineId[line.Id]?.model ?? '',
				departmentId: this._repairCenterByLineId[line.Id]?.departmentId ?? null,
				reportedProblem: this._repairCenterByLineId[line.Id]?.reportedProblem ?? '',
				additionalServices: !!this._repairCenterByLineId[line.Id]?.additionalServices,
				insulationPowderCoating: this._insulationList(
					this._repairCenterByLineId[line.Id]?.insulationPowderCoating
				),
				replacedWithIXchange: !!this._repairCenterByLineId[line.Id]?.replacedWithIXchange,
				pictures: [],
				billingType: this._normalizeBillingType(line.BillingType__c?.value),
				discount: this._discountForBillingType(line.BillingType__c?.value)
			};
		}
		if (schema === 'calibration') {
			return {
				_schema: 'calibration',
				_entity: 'WorkOrderLineItem',
				assignedResourceId: this._resolveAssignedResourceId(line.AssignedResource__c?.value),
				assetId: line.AssetId?.value ?? null
			};
		}
		if (schema === 'parts') {
			const productItemId = line.ProductItem__c?.value ?? null;
			const product2Id = line.Product__c?.value ?? null;
			const linkedProduct2Id = product2Id
				|| (productItemId ? this._product2IdByProductItemId[productItemId] : null);
			if (product2Id && !this._productCodeByProduct2Id[product2Id]) {
				this._product2LookupId = product2Id;
			}
			return {
				_schema: 'parts',
				_entity: 'WorkOrderLineItem',
				assignedResourceId: this._resolveAssignedResourceId(line.AssignedResource__c?.value),
				partsSource: line.PartsSource__c?.value ?? PARTS_SOURCE_TRUNK,
				productItemId,
				product2Id,
				productCode: linkedProduct2Id
					? (this._productCodeByProduct2Id[linkedProduct2Id] ?? '')
					: '',
				partDescription: line.PartDescription__c?.value
					?? (linkedProduct2Id ? (this._partDescriptionByProduct2Id[linkedProduct2Id] ?? '') : '')
					?? '',
				quantity: line.UnitQty__c?.value ?? 0,
				partsQuantity: line.UnitQty__c?.value ?? 0,
				description: line.Description?.value ?? '',
				allowedUnit: line.AllowedUnit__c?.value ?? false,
				returnable: line.Returnable__c?.value
					?? (product2Id
						? this._resolveReturnableForProduct2(product2Id)
						: this._resolveReturnableForProductItem(productItemId))
					?? false,
				usagesException: line.UsagesException__c?.value ?? false,
				billingType: this._normalizeBillingType(line.BillingType__c?.value),
				discount: this._discountForBillingType(line.BillingType__c?.value)
			};
		}
		return {
			_schema: 'travel',
			_entity: 'WorkOrderLineItem',
			_lineType: lineType,
			...base,
			durationHours: line.Duration?.value
				?? this._computeDurationHours(line.StartDate?.value, line.EndDate?.value)
				?? '',
			listPrice: line.ListPrice__c?.value ?? null,
			unitPrice: line.UnitPrice__c?.value ?? null,
			totalPrice: line.TotalPrice__c?.value ?? null
		};
	}

	/**
	 * @description Internal helper: Validate For Schema.
	 */
	_validateForSchema(schema, payload) {
		if (schema === 'parts_consumed') return this._validatePartsConsumed(payload);
		if (schema === 'parts') return this._validatePartsWoli(payload);
		if (schema === 'required_product') return this._validateRequiredProduct(payload);
		if (schema === 'expense') return this._validateExpense(payload);
		if (schema === 'time') return this._validateTime(payload);
		if (schema === 'travel') return this._validateTravel(payload);
		if (schema === 'labor') return this._validateLabor(payload);
		if (schema === 'instrument') return this._validateInstrument(payload);
		if (schema === 'calibration') return this._validateCalibration(payload);
		return null;
	}

	/**
	 * @description Internal helper: Validate Parts Consumed.
	 */
	_validatePartsConsumed({ assignedResourceId, productItemId, quantityConsumed }) {
		if (!assignedResourceId) return 'Resource is required.';
		if (!productItemId) return 'Product Item is required.';
		if (!quantityConsumed || Number(quantityConsumed) <= 0) return 'Quantity Consumed must be greater than 0.';
		return null;
	}

	/**
	 * @description Internal helper: Validate Parts Woli.
	 */
	_validatePartsWoli({
		assignedResourceId,
		partsSource,
		productItemId,
		product2Id,
		quantity,
		partsQuantity,
		allowedUnit,
		usagesException
	}) {
		if (!assignedResourceId) return 'Resource is required.';
		if (!partsSource) return 'Part\'s Source is required.';
		if (productItemId && product2Id) {
			return 'Select either Product Item or Product, but not both.';
		}
		if (partsSource === PARTS_SOURCE_TRUNK) {
			if (!productItemId) return 'Product Item is required.';
			if (product2Id) return 'Select either Product Item or Product, but not both.';
		} else if (partsSource === PARTS_SOURCE_CUSTOMER) {
			if (!product2Id) return 'Product is required.';
			if (productItemId) return 'Select either Product Item or Product, but not both.';
		}
		const qty = partsQuantity ?? quantity;
		if (!qty || Number(qty) <= 0) return 'Unit Qty must be greater than 0.';
		if (allowedUnit === false && !usagesException) {
			return 'You are trying to consume a non approved part';
		}
		return null;
	}

	/**
	 * @description Internal helper: Validate Required Product.
	 */
	_validateRequiredProduct({ product2Id, quantityRequired }) {
		if (!product2Id) return 'Product is required.';
		if (!quantityRequired || Number(quantityRequired) <= 0) return 'Quantity Required must be greater than 0.';
		return null;
	}

	/**
	 * @description Internal helper: Validate Expense.
	 */
	_validateExpense({ expenseType, quantity, unitPrice }) {
		if (!expenseType) return 'Expense Type is required.';
		if (unitPrice === '' || unitPrice == null || Number(unitPrice) < 0) return 'Unit Price must be 0 or greater.';
		if (!quantity || Number(quantity) <= 0) return 'Quantity must be greater than 0.';
		return null;
	}

	/**
	 * @description Internal helper: Validate Travel.
	 */
	_validateTravel({ assignedResourceId, startDate, endDate }) {
		return this._validateTimeRange({ assignedResourceId, startDate, endDate });
	}

	/**
	 * @description Internal helper: Validate Time.
	 */
	_validateTime(payload) {
		if (!payload.lineType || !TIME_LINE_TYPES.has(payload.lineType)) {
			return 'Line Type is required.';
		}
		const schema = LINE_TYPE_TO_SCHEMA[payload.lineType];
		return this._validateForSchema(schema, payload);
	}

	/**
	 * @description Internal helper: Validate Labor.
	 */
	_validateLabor({ assignedResourceId, quantity }) {
		if (!assignedResourceId) return 'Resource is required.';
		if (!quantity || Number(quantity) <= 0) return 'Qty must be greater than 0.';
		return null;
	}

	/**
	 * @description Department on the work order asset.
	 * @return {string|null}
	 */
	_assetDepartmentId() {
		return this._workOrder?.Asset?.Department__c?.value || null;
	}

	/**
	 * @description Name of the department on the work order asset.
	 * @return {string}
	 */
	_assetDepartmentName() {
		return this._workOrder?.Asset?.Department__c?.displayValue || '';
	}

	/**
	 * @description Defaults Department from the asset when Beyond Repair Info is open and the line has none.
	 * @param {string} lineId Line or temp Id
	 */
	_defaultDepartmentOnEdit(lineId) {
		const departmentId = this._assetDepartmentId();
		if (!departmentId) return;
		const add = this._pendingAdds.find(item => item._tempId === lineId);
		const edit = add || this._pendingEdits[lineId];
		const stored = this._repairCenterByLineId[lineId] || {};
		const serviceCodeId = edit?.serviceCodeId || null;
		const showDetails = serviceCodeId
			? this._showsObrDetailFields(serviceCodeId)
			: this._lineNeedsObrDetails(stored);
		if (!showDetails) return;
		if (edit?.departmentId || stored.departmentId) return;
		this._stageEdit(lineId, 'departmentId', departmentId);
	}

	/**
	 * @description How complete a product-serviced line is.
	 * @param {Object} payload Staged instrument values
	 * @return {string} empty, partial, or complete
	 */
	_instrumentTone(payload) {
		const needsObrDetails = this._lineNeedsObrDetails(payload);
		const checks = [
			!!payload?.deviceTypeId,
			!!payload?.serviceCodeId || !!String(payload?.repairLevel || '').trim(),
			payload?.quantity !== '' && payload?.quantity != null && Number(payload.quantity) > 0
		];
		if (needsObrDetails) {
			checks.push(
				!!String(payload?.serialNumber || '').trim(),
				!!String(payload?.model || '').trim(),
				!!payload?.departmentId,
				!!String(payload?.reportedProblem || '').trim()
			);
		}
		const filled = checks.filter(Boolean).length;
		if (filled === 0) return 'empty';
		if (filled === checks.length) return 'complete';
		return 'partial';
	}

	/**
	 * @description Status fields used to color a product-serviced line.
	 * @param {string} status Current line status
	 * @param {Object} values Field values used to judge completeness
	 * @return {Object}
	 */
	_instrumentPresentation(status, values) {
		const resolvedStatus = status || 'New';
		return {
			status: resolvedStatus,
			canceled: resolvedStatus === WOLI_STATUS_CANCELED,
			editCanceled: resolvedStatus === WOLI_STATUS_CANCELED,
			instrumentTone: this._instrumentTone({ ...values, status: resolvedStatus })
		};
	}

	/**
	 * @description Status to store when a product-serviced line is closed or saved.
	 * @param {Object} payload Staged instrument values
	 * @param {boolean} closing True when the user closes the line or saves
	 * @return {string}
	 */
	_resolveInstrumentStatus(payload, pictureCount) {
		if (payload?.canceled || payload?.status === WOLI_STATUS_CANCELED) {
			return WOLI_STATUS_CANCELED;
		}
		const tone = this._instrumentTone(payload);
		if (tone === 'complete' && pictureCount >= REQUIRED_PICTURES_PER_LINE) return WOLI_STATUS_COMPLETED;
		if (tone !== 'empty' || payload?.status === WOLI_STATUS_COMPLETED) return WOLI_STATUS_IN_PROGRESS;
		return payload?.status || 'New';
	}

	/**
	 * @description Writes the product-serviced status onto a staged line.
	 *              The line is Completed when all its information is filled and it has the required pictures.
	 * @param {string} lineId Line or temp Id
	 */
	_finalizeInstrumentStatus(lineId) {
		const add = this._pendingAdds.find(item => item._tempId === lineId);
		if (add?._schema === 'instrument') {
			const status = this._resolveInstrumentStatus(add, (add.mobilePictures || []).length);
			this._pendingAdds = this._pendingAdds.map(item => (
				item._tempId === lineId ? { ...item, status, canceled: status === WOLI_STATUS_CANCELED } : item
			));
			return;
		}
		const edit = this._pendingEdits[lineId];
		if (edit?._schema !== 'instrument') return;
		const status = this._resolveInstrumentStatus(edit, this._savedPictureCount(lineId));
		this._stageEdit(lineId, 'status', status);
		this._stageEdit(lineId, 'canceled', status === WOLI_STATUS_CANCELED);
	}

	/**
	 * @description Applies the status to every staged product-serviced line before save.
	 */
	_finalizeInstrumentStatuses() {
		Object.keys(this._pendingEdits).forEach(lineId => {
			this._finalizeInstrumentStatus(lineId);
		});
		this._pendingAdds
			.filter(add => add._schema === 'instrument')
			.forEach(add => this._finalizeInstrumentStatus(add._tempId));
	}

	/**
	 * @param {string} lineId Line Id
	 * @return {number} Pictures saved on the line
	 */
	_savedPictureCount(lineId) {
		return (this._mobilePicturesByRecordId[this._pictureRecordKey(lineId)] || []).length;
	}

	/**
	 * @description Saved instrument line values used to judge whether the line is complete.
	 * @param {Object} l Server line
	 * @return {Object}
	 */
	_savedInstrumentValues(l) {
		const stored = this._repairCenterByLineId[l.Id] || {};
		return {
			deviceTypeId: l.Product2Id?.value ?? l.Product2?.Id ?? null,
			repairLevel: l.RepairLevel__c?.value ?? '',
			quantity: l.Quantity?.value ?? '',
			serialNumber: stored.serialNumber,
			model: l.Model__c?.value ?? stored.model,
			departmentId: stored.departmentId,
			reportedProblem: stored.reportedProblem,
			sendToRepairCenter: !!stored.sendToRepairCenter
		};
	}

	/**
	 * @description Saved instrument lines that have all their information and the required pictures,
	 *              but are not Completed yet.
	 * @return {string[]}
	 */
	_instrumentLineIdsReadyToComplete() {
		void this.mobilePictureVersion;
		return this._serverLines
			.filter(l => INSTRUMENT_TAB_LINE_TYPES.has(l.LineType__c?.value))
			.filter(l => !this._pendingDeletes[l.Id] && !this._pendingEdits[l.Id])
			.filter(l => l.Status?.value !== WOLI_STATUS_COMPLETED && l.Status?.value !== WOLI_STATUS_CANCELED)
			.filter(l => this._savedPictureCount(l.Id) >= REQUIRED_PICTURES_PER_LINE)
			.filter(l => this._instrumentTone(this._savedInstrumentValues(l)) === 'complete')
			.map(l => l.Id);
	}

	/**
	 * @description Sets Completed on saved instrument lines that are ready.
	 * @return {Promise<string[]>} Completed line Ids
	 */
	async _completeReadyInstrumentLines() {
		const completed = [];
		for (const id of this._instrumentLineIdsReadyToComplete()) {
			try {
				// eslint-disable-next-line no-await-in-loop
				await updateRecord({ fields: { Id: id, [WOLI_LINE_STATUS.fieldApiName]: WOLI_STATUS_COMPLETED } });
				completed.push(id);
			} catch (error) {
				this.editErrors = { ...this.editErrors, [id]: this._errorMessage(error) };
			}
		}
		if (completed.length) {
			try { await refreshGraphQL(this.graphqlResult); } catch (e) { /* swallow */ }
		}
		return completed;
	}

	/**
	 * @description Card color for a line. Text stays dark so the row can still be read.
	 *              Red Canceled, orange when an instrument has fewer than the required pictures
	 *              or Billing Type is Warranty, SVC Warranty, or Courtesy, green Completed,
	 *              yellow In Progress, blue New.
	 * @param {Object} line Line view model
	 * @return {string}
	 */
	_lineCardClass(line) {
		if (line?.status === WOLI_STATUS_CANCELED) return 'woli-card woli-card_canceled';
		if (this._lineUsesOrange(line)) return 'woli-card woli-card_billing';
		if (line?.status === WOLI_STATUS_COMPLETED) return 'woli-card woli-card_completed';
		if (line?.status === WOLI_STATUS_IN_PROGRESS || (line?.schema === 'instrument' && line?.instrumentTone === 'partial')) {
			return 'woli-card woli-card_incomplete';
		}
		if (line?.status === 'New') return 'woli-card woli-card_new';
		return 'woli-card';
	}

	/**
	 * @description Orange highlight for an instrument line with fewer than the required pictures,
	 *              or for Warranty, SVC Warranty, or Courtesy.
	 * @param {Object} line Line view model
	 * @return {boolean}
	 */
	_lineUsesOrange(line) {
		const billingType = line?.billingType || line?.editBillingType;
		if (HIGHLIGHT_BILLING_TYPES.has(billingType)) return true;
		return line?.schema === 'instrument'
			&& line?.status !== WOLI_STATUS_CANCELED
			&& (line?.mobilePictureCount || 0) < REQUIRED_PICTURES_PER_LINE;
	}

	/**
	 * @description Internal helper: Validate Instrument.
	 */
	_validateInstrument(payload) {
		if (payload?.canceled || payload?.status === WOLI_STATUS_CANCELED) return null;
		const tone = this._instrumentTone(payload);
		if (tone === 'partial') return null;
		if (!payload.deviceTypeId) return 'Device Type is required.';
		if (!payload.serviceCodeId && !String(payload.repairLevel || '').trim()) {
			return 'Service Code is required.';
		}
		if (payload.quantity === '' || payload.quantity == null || Number(payload.quantity) === 0) {
			return 'Quantity is required and cannot be 0.';
		}
		if (Number.isNaN(Number(payload.quantity)) || Number(payload.quantity) < 0) {
			return 'Quantity is required and cannot be 0.';
		}
		if (this._lineNeedsObrDetails(payload)) {
			if (!String(payload.serialNumber || '').trim()) return 'Make is required.';
			if (!String(payload.model || '').trim()) return 'Model is required.';
			if (!payload.departmentId) return 'Department is required.';
			if (!String(payload.reportedProblem || '').trim()) return 'Reported Problem is required.';
		}
		return null;
	}

	/**
	 * @description Internal helper: Validate Calibration.
	 */
	_validateCalibration({ assignedResourceId }) {
		if (!assignedResourceId) return 'Resource is required.';
		return null;
	}

	/**
	 * @description Internal helper: Schema For Line Type.
	 */
	_schemaForLineType(lineType) {
		return TYPE_TO_DEF[lineType]?.schema ?? 'travel';
	}

	/**
	 * @description Internal helper: Reset Draft.
	 */
	_resetDraft() {
		this._pendingEdits = {};
		this._pendingDeletes = {};
		this._pendingAdds = [];
		this._pendingCycleCount = undefined;
		this._pendingCycleCountDate = undefined;
		this.editStateMap = {};
		this.showAddForm = EMPTY_ADD_FORM_VISIBILITY();
		this.addFormState = this._emptyAddFormState();
		this.editErrors = {};
		this.addErrors = {};
		this._syncWorkOrderInProgress();
	}

	/**
	 * @description Internal helper: Empty Add Form State.
	 */
	_emptyAddFormState() {
		return {
			lineType: '',
			startDate: '',
			endDate: '',
			durationHours: '',
			workTypeId: this._headerWorkTypeId(),
			assignedResourceId: this._defaultAssignedResourceId(),
			productItemId: null,
			product2Id: null,
			productCode: '',
			partDescription: '',
			quantityConsumed: '',
			partsSource: PARTS_SOURCE_TRUNK,
			quantityRequired: '',
			expenseType: '',
			description: '',
			unitPrice: '',
			assetId: null,
			repairCodeId: null,
			laborPartProductCode: '',
			productDescription: '',
			quantity: '',
			billingType: BILLING_TYPE_BILLABLE,
			discount: 0,
			partsQuantity: '',
			usagesException: false,
			allowedUnit: null,
			returnable: null,
			deviceTypeId: null,
			deviceType: '',
			serviceCodeId: null,
			repairLevel: '',
			serialNumber: '',
			model: '',
			departmentId: null,
			reportedProblem: '',
			additionalServices: false,
			insulationPowderCoating: [],
			replacedWithIXchange: false,
			pictures: [],
			mobilePictures: [],
			canceled: false,
			status: 'New'
		};
	}

	/**
	 * @description Internal helper: Default Assigned Resource Id.
	 */
	_defaultAssignedResourceId() { return this._currentUserServiceResourceId ?? null; }
	/**
	 * @description Work Order header Work Type Id used as the Time-tab default.
	 * @return {string|null}
	 */
	_headerWorkTypeId() {
		return this._workOrder?.WorkTypeId?.value ?? this._workOrder?.WorkType?.Id ?? null;
	}
	/**
	 * @description Fills Work Type on an open Time add form once the Work Order header is available.
	 */
	_defaultAddFormWorkTypeFromHeader() {
		if (!this.showAddForm?.Time || this.addFormState?.workTypeId) {
			return;
		}
		const workTypeId = this._headerWorkTypeId();
		if (!workTypeId) {
			return;
		}
		this.addFormState = { ...this.addFormState, workTypeId };
	}
	/**
	 * @description Internal helper: Resolve Assigned Resource Id.
	 */
	_resolveAssignedResourceId(...values) {
		for (const value of values) {
			if (value) return value;
		}
		return this._defaultAssignedResourceId();
	}

	/**
	 * @description Internal helper: Assigned Resource Name For Id.
	 */
	_assignedResourceNameForId(resourceId) {
		if (!resourceId) return '';
		return this._serviceResourceNameById[resourceId] ?? '';
	}

	/**
	 * @description Internal helper: Cache Service Resource Name.
	 */
	_cacheServiceResourceName(resourceId, name) {
		if (!resourceId || !name || this._serviceResourceNameById[resourceId] === name) return;
		this._serviceResourceNameById = { ...this._serviceResourceNameById, [resourceId]: name };
	}

	/**
	 * @description Internal helper: Collect Service Resource Ids From Parts.
	 */
	_collectServiceResourceIdsFromParts(parts) {
		const ids = new Set();
		for (const p of parts ?? []) {
			const id = p.ServiceResource__c?.value ?? p.Service_Resource__c?.value;
			if (id) ids.add(id);
		}
		return [...ids];
	}

	/**
	 * @description Internal helper: Refresh Service Resource Name Lookups.
	 */
	_refreshServiceResourceNameLookups(parts) {
		const ids = this._collectServiceResourceIdsFromParts(parts).filter(
			id => !this._serviceResourceNameById[id]
		);
		this._serviceResourceIdsForLookup = ids.length ? ids : undefined;
	}

	/**
	 * @description Internal helper: On Resource Selected.
	 */
	_onResourceSelected(recordId, editId) {
		if (recordId && (!this._locationIdByServiceResourceId[recordId] || !this._serviceResourceNameById[recordId])) {
			this._serviceResourceLocationLookupId = recordId;
		}
		if (editId) {
			this._stageEdit(editId, 'productItemId', null);
			this._stageEdit(editId, 'allowedUnit', null);
		}
	}

	/**
	 * @description Internal helper: On Product Item Selected.
	 */
	_onProductItemSelected(recordId, options = {}) {
		if (recordId) this._productItemLookupId = recordId;
		this._evaluateAllowedUnitForProductItem(recordId, options);
	}

	/**
	 * @description Applies Parts Source change side-effects on a staged WOLI edit.
	 */
	_applyPartsSourceChangeToEdit(editId, partsSource) {
		if (!editId) return;
		this._stageEdit(editId, 'allowedUnit', null);
		this._stageEdit(editId, 'returnable', null);
		this._stageEdit(editId, 'productCode', '');
		this._stageEdit(editId, 'partDescription', '');
		if (partsSource === PARTS_SOURCE_TRUNK) {
			this._stageEdit(editId, 'product2Id', null);
			const productItemId = this._pendingEdits[editId]?.productItemId
				?? this._pendingAdds.find(a => a._tempId === editId)?.productItemId;
			if (productItemId) {
				const linkedProduct2Id = this._product2IdByProductItemId[productItemId];
				this._stageEdit(
					editId,
					'returnable',
					this._resolveReturnableForProductItem(productItemId)
				);
				if (linkedProduct2Id) {
					this._stageEdit(
						editId,
						'productCode',
						this._productCodeByProduct2Id[linkedProduct2Id] ?? ''
					);
					this._stageEdit(
						editId,
						'partDescription',
						this._partDescriptionByProduct2Id[linkedProduct2Id] ?? ''
					);
				}
				this._onProductItemSelected(productItemId, { editId });
			}
		} else if (partsSource === PARTS_SOURCE_CUSTOMER) {
			this._stageEdit(editId, 'productItemId', null);
		}
	}

	/**
	 * @description Evaluates Allowed Unit for a Product Item via Apex.
	 *              Apex skips SBOM cross-reference when Root PFCL SBOM Required is not Yes
	 *              (GW-4218) or when the Work Order has no Asset; both return evaluated=false.
	 */
	async _evaluateAllowedUnitForProductItem(productItemId, options = {}) {
		const { editId = null, isAddForm = false } = options;
		this._applyAllowedUnitResult(null, null, { editId, isAddForm });
	}

	/**
	 * @description GW-4311 Evaluates Allowed Unit for a Product2 via Apex.
	 */
	async _evaluateAllowedUnitForProduct(product2Id, options = {}) {
		const { editId = null, isAddForm = false } = options;
		this._applyAllowedUnitResult(null, null, { editId, isAddForm });
	}

	/**
	 * @description Internal helper: Apex Error Message.
	 */
	_apexErrorMessage(error) {
		if (!error) return null;
		if (typeof error.body?.message === 'string' && error.body.message) return error.body.message;
		if (Array.isArray(error.body) && error.body[0]?.message) return error.body[0].message;
		if (typeof error.message === 'string' && error.message) return error.message;
		return null;
	}

	/**
	 * @description Internal helper: Apply Allowed Unit Result.
	 */
	_applyAllowedUnitResult(allowedUnit, { editId = null, isAddForm = false } = {}) {
		if (isAddForm) {
			this.addFormState = { ...this.addFormState, allowedUnit };
			return;
		}
		if (editId) {
			this._stageEdit(editId, 'allowedUnit', allowedUnit);
		}
	}

	/**
	 * @description Internal helper: Resolve Returnable For Product Item.
	 */
	_resolveReturnableForProductItem(productItemId) {
		if (!productItemId) return null;
		return this._isReturnableByProductItemId[productItemId] ?? null;
	}

	/**
	 * @description Internal helper: Resolve Returnable For Product2.
	 */
	_resolveReturnableForProduct2(product2Id) {
		if (!product2Id) return null;
		return this._isReturnableByProduct2Id[product2Id] ?? null;
	}

	/**
	 * @description Internal helper: Sync Returnable For Product Item.
	 */
	_syncReturnableForProductItem(productItemId, isReturnable) {
		this._pendingAdds = this._pendingAdds.map(a => (
			a._entity === 'ProductConsumed' && a.productItemId === productItemId
				? { ...a, returnable: isReturnable }
				: a
		));
		const edits = { ...this._pendingEdits };
		let changed = false;
		for (const [id, edit] of Object.entries(edits)) {
			if (edit._entity === 'ProductConsumed' && edit.productItemId === productItemId) {
				edits[id] = { ...edit, returnable: isReturnable };
				changed = true;
			}
		}
		if (changed) this._pendingEdits = edits;
	}

	/**
	 * @description Caches Product2 details and syncs onto matching Parts form / pending rows.
	 */
	_applyProductDetails(product2Id, details = {}) {
		if (!product2Id) return;
		const { name, productCode, partDescription, isReturnable } = details;
		if (name) {
			this._productNameByProduct2Id = { ...this._productNameByProduct2Id, [product2Id]: name };
		}
		if (productCode != null) {
			this._productCodeByProduct2Id = { ...this._productCodeByProduct2Id, [product2Id]: productCode };
		}
		if (partDescription != null) {
			this._partDescriptionByProduct2Id = {
				...this._partDescriptionByProduct2Id,
				[product2Id]: partDescription
			};
		}
		if (isReturnable !== undefined && isReturnable !== null) {
			this._isReturnableByProduct2Id = {
				...this._isReturnableByProduct2Id,
				[product2Id]: isReturnable
			};
		}
		this._syncProductDetailsForProduct2(product2Id, { productCode, partDescription, isReturnable });

		if (this.addFormState?.deviceTypeId === product2Id && productCode) {
			this.addFormState = { ...this.addFormState, deviceType: productCode };
		}

		if (this.addFormState?.product2Id === product2Id && this.addFormIsCustomerStock) {
			this._evaluateAllowedUnitForProduct(product2Id, { isAddForm: true });
		}
		for (const [id, edit] of Object.entries(this._pendingEdits)) {
			if (edit._schema === 'parts' && edit.product2Id === product2Id) {
				this._evaluateAllowedUnitForProduct(product2Id, { editId: id });
			}
		}
	}

	/**
	 * @description Syncs Product2 code / description / returnable onto matching Parts rows.
	 */
	_syncProductDetailsForProduct2(product2Id, { productCode, partDescription, isReturnable } = {}) {
		if (!product2Id) return;
		if (this.addFormState?.product2Id === product2Id) {
			this.addFormState = {
				...this.addFormState,
				...(productCode != null ? { productCode } : {}),
				...(partDescription != null ? { partDescription } : {}),
				...(isReturnable !== undefined && isReturnable !== null ? { returnable: isReturnable } : {})
			};
		}
		this._pendingAdds = this._pendingAdds.map(a => (
			a._schema === 'parts' && a.product2Id === product2Id
				? {
					...a,
					...(productCode != null ? { productCode } : {}),
					...(partDescription != null ? { partDescription } : {}),
					...(isReturnable !== undefined && isReturnable !== null ? { returnable: isReturnable } : {})
				}
				: a
		));
		const edits = { ...this._pendingEdits };
		let changed = false;
		for (const [id, edit] of Object.entries(edits)) {
			if (edit._schema === 'parts' && edit.product2Id === product2Id) {
				edits[id] = {
					...edit,
					...(productCode != null ? { productCode } : {}),
					...(partDescription != null ? { partDescription } : {}),
					...(isReturnable !== undefined && isReturnable !== null ? { returnable: isReturnable } : {})
				};
				changed = true;
			}
		}
		if (changed) this._pendingEdits = edits;
	}

	/**
	 * @description Syncs Product2 code / description onto Parts rows keyed by Product Item.
	 */
	_syncProductDetailsForProductItem(productItemId, { productCode, partDescription } = {}) {
		if (!productItemId) return;
		if (this.addFormState?.productItemId === productItemId) {
			this.addFormState = {
				...this.addFormState,
				product2Id: null,
				...(productCode != null ? { productCode } : {}),
				...(partDescription != null ? { partDescription } : {})
			};
		}
		this._pendingAdds = this._pendingAdds.map(a => (
			a._schema === 'parts' && a.productItemId === productItemId
				? {
					...a,
					product2Id: null,
					...(productCode != null ? { productCode } : {}),
					...(partDescription != null ? { partDescription } : {})
				}
				: a
		));
		const edits = { ...this._pendingEdits };
		let changed = false;
		for (const [id, edit] of Object.entries(edits)) {
			if (edit._schema === 'parts' && edit.productItemId === productItemId) {
				edits[id] = {
					...edit,
					product2Id: null,
					...(productCode != null ? { productCode } : {}),
					...(partDescription != null ? { partDescription } : {})
				};
				changed = true;
			}
		}
		if (changed) this._pendingEdits = edits;
	}

	/**
	 * @description Internal helper: Fmt Returnable.
	 */
	_fmtReturnable(value) {
		if (value === true) return 'Yes';
		if (value === false) return 'No';
		return '';
	}

	/**
	 * @description Internal helper: Fmt Duration Label.
	 */
	_fmtDurationLabel(hours) {
		if (hours == null || hours === '') return '';
		const n = Number(hours);
		if (Number.isNaN(n)) return '';
		return `${n.toFixed(2)} hrs`;
	}

	/**
	 * @description Internal helper: Product Item Filter For Resource.
	 */
	_productItemFilterForResource(resourceId) {
		const locationId = resourceId ? this._locationIdByServiceResourceId[resourceId] : null;
		// Trunk stock: only Product Items at the selected Service Resource's Location.
		if (!locationId) {
			return {
				criteria: [{ fieldPath: 'LocationId', operator: 'eq', value: '000000000000000AAA' }]
			};
		}
		return {
			criteria: [
				{ fieldPath: 'LocationId', operator: 'eq', value: locationId },
				{ fieldPath: 'QuantityOnHand', operator: 'gt', value: 0 }
			],
			filterLogic: '1 AND 2'
		};
	}

	/**
	 * @description Internal helper: Resource Id For Edit Line.
	 */
	_resourceIdForEditLine(editId) {
		if (!editId) return null;
		const line = this._serverLines.find(l => l.Id === editId);
		if (line?.AssignedResource__c?.value) return line.AssignedResource__c.value;
		const part = this._serverPartsConsumed.find(p => p.Id === editId);
		return part?.ServiceResource__c?.value
			?? part?.Service_Resource__c?.value
			?? part?.ServiceResourceId?.value
			?? null;
	}

	/**
	 * @description Internal helper: Apply Scanned Product Item.
	 */
	_applyScannedProductItem(match, options = {}) {
		const { editId = null, isAddForm = false } = options;
		const productItemId = match.productItemId;
		if (match.productName) {
			this._productItemNameByProductItemId = {
				...this._productItemNameByProductItemId,
				[productItemId]: match.productName
			};
		}
		if (match.product2Id) {
			this._product2IdByProductItemId = {
				...this._product2IdByProductItemId,
				[productItemId]: match.product2Id
			};
			if (match.productName) {
				this._productNameByProduct2Id = {
					...this._productNameByProduct2Id,
					[match.product2Id]: match.productName
				};
			}
			if (match.productCode != null) {
				this._productCodeByProduct2Id = {
					...this._productCodeByProduct2Id,
					[match.product2Id]: match.productCode
				};
			}
			if (match.description != null) {
				this._partDescriptionByProduct2Id = {
					...this._partDescriptionByProduct2Id,
					[match.product2Id]: match.description
				};
			}
			if (match.isReturnable != null) {
				this._isReturnableByProduct2Id = {
					...this._isReturnableByProduct2Id,
					[match.product2Id]: match.isReturnable
				};
			}
		}
		if (match.isReturnable != null) {
			this._isReturnableByProductItemId = {
				...this._isReturnableByProductItemId,
				[productItemId]: match.isReturnable
			};
		}

		const productCode = match.productCode ?? '';
		const partDescription = match.description ?? '';

		if (isAddForm) {
			this.addFormState = {
				...this.addFormState,
				partsSource: PARTS_SOURCE_TRUNK,
				productItemId,
				product2Id: null,
				productCode,
				partDescription,
				returnable: match.isReturnable ?? null,
				allowedUnit: null
			};
			this._onProductItemSelected(productItemId, { isAddForm: true });
			this._toast('Product Item selected', match.productName || productItemId, 'success');
			return;
		}

		if (editId) {
			this._stageEdit(editId, 'partsSource', PARTS_SOURCE_TRUNK);
			this._stageEdit(editId, 'productItemId', productItemId);
			this._stageEdit(editId, 'product2Id', null);
			this._stageEdit(editId, 'productCode', productCode);
			this._stageEdit(editId, 'partDescription', partDescription);
			this._stageEdit(editId, 'returnable', match.isReturnable ?? null);
			this._stageEdit(editId, 'allowedUnit', null);
			this._onProductItemSelected(productItemId, { editId });
			this._toast('Product Item selected', match.productName || productItemId, 'success');
		}
	}

	/**
	 * @description GW-4311 Apply scanned Product2 (Customer Stock).
	 */
	_applyScannedProduct(match, options = {}) {
		const { editId = null, isAddForm = false } = options;
		const product2Id = match.product2Id;
		if (!product2Id) return;

		this._applyProductDetails(product2Id, {
			name: match.productName,
			productCode: match.productCode,
			partDescription: match.description,
			isReturnable: match.isReturnable
		});
		this._product2LookupId = product2Id;

		const productCode = match.productCode ?? this._productCodeByProduct2Id[product2Id] ?? '';
		const partDescription = match.description ?? this._partDescriptionByProduct2Id[product2Id] ?? '';
		const returnable = match.isReturnable ?? this._resolveReturnableForProduct2(product2Id) ?? null;

		if (isAddForm) {
			this.addFormState = {
				...this.addFormState,
				partsSource: PARTS_SOURCE_CUSTOMER,
				product2Id,
				productItemId: null,
				productCode,
				partDescription,
				returnable,
				allowedUnit: null
			};
			this._evaluateAllowedUnitForProduct(product2Id, { isAddForm: true });
			this._toast('Product selected', match.productName || productCode || product2Id, 'success');
			return;
		}

		if (editId) {
			this._stageEdit(editId, 'partsSource', PARTS_SOURCE_CUSTOMER);
			this._stageEdit(editId, 'product2Id', product2Id);
			this._stageEdit(editId, 'productItemId', null);
			this._stageEdit(editId, 'productCode', productCode);
			this._stageEdit(editId, 'partDescription', partDescription);
			this._stageEdit(editId, 'returnable', returnable);
			this._stageEdit(editId, 'allowedUnit', null);
			this._evaluateAllowedUnitForProduct(product2Id, { editId });
			this._toast('Product selected', match.productName || productCode || product2Id, 'success');
		}
	}

	/**
	 * @description Internal helper: Compute Total Price.
	 */
	_computeTotalPrice(unitPrice, quantity) {
		return (Number(unitPrice) || 0) * (Number(quantity) || 0);
	}

	/**
	 * @description Internal helper: Compute Duration Hours.
	 */
	_computeDurationHours(startDate, endDate) {
		if (!startDate || !endDate) return null;
		const start = new Date(startDate).getTime();
		const end = new Date(endDate).getTime();
		if (Number.isNaN(start) || Number.isNaN(end) || end <= start) return null;
		return (end - start) / (1000 * 60 * 60);
	}

	/**
	 * @description Syncs start/duration/end on an edit/add line after one of them changes.
	 * @param {string} id Line Id
	 * @param {string} changedField Field that changed
	 */
	_syncTimeFieldsOnEdit(id, changedField) {
		const pending = this._pendingEdits[id] || this._pendingAdds.find((a) => a._tempId === id);
		if (!pending) {
			return;
		}
		const synced = this._syncTimeFieldsOnState({ ...pending }, changedField);
		if (this._pendingAdds.some((a) => a._tempId === id)) {
			this._pendingAdds = this._pendingAdds.map((a) => (a._tempId === id ? { ...a, ...synced } : a));
			return;
		}
		this._pendingEdits = { ...this._pendingEdits, [id]: { ...pending, ...synced } };
	}

	/**
	 * @description Syncs start/duration/end on a state object.
	 * @param {object} state Form/edit state
	 * @param {string} changedField Field that changed
	 * @return {object}
	 */
	_syncTimeFieldsOnState(state, changedField) {
		const next = { ...state };
		if (changedField === 'durationHours' || changedField === 'startDate') {
			const hours = Number(next.durationHours);
			if (next.startDate && !Number.isNaN(hours) && hours > 0) {
				next.endDate = this._addHoursToDatetime(next.startDate, hours);
			}
		} else if (changedField === 'endDate') {
			const hours = this._computeDurationHours(next.startDate, next.endDate);
			if (hours != null) {
				next.durationHours = hours;
			}
		}
		return next;
	}

	/**
	 * @description Adds hours to an ISO datetime string.
	 * @param {string} startDate ISO datetime
	 * @param {number} hours Duration hours
	 * @return {string}
	 */
	_addHoursToDatetime(startDate, hours) {
		const startMs = new Date(startDate).getTime();
		if (Number.isNaN(startMs)) {
			return startDate;
		}
		return new Date(startMs + (hours * 60 * 60 * 1000)).toISOString();
	}

	/**
	 * @description Internal helper: Build Duration Fields.
	 */
	_buildDurationFields(startDate, endDate) {
		const duration = this._computeDurationHours(startDate, endDate);
		if (duration == null) return {};
		return { [WOLI_DURATION.fieldApiName]: duration, DurationType: 'Hours' };
	}

	/**
	 * @description Internal helper: Work Order Currency.
	 */
	_workOrderCurrency() { return this._workOrder?.CurrencyIsoCode?.value ?? 'USD'; }
	/**
	 * @description Internal helper: Rebuild Server Parts Consumed.
	 */
	_rebuildServerPartsConsumed() {
		const byId = new Map();
		const richness = (p) => {
			let score = 0;
			if (p.ProductItem?.ProductName?.value) score += 4;
			if (p.Product2?.Name?.value) score += 2;
			if (p.ProductItemId?.value) score += 1;
			return score;
		};
		for (const p of [...this._serverPartsFromRelatedList, ...this._serverPartsFromGraphql]) {
			if (!p?.Id) continue;
			const prev = byId.get(p.Id);
			if (!prev || richness(p) >= richness(prev)) byId.set(p.Id, p);
		}
		this._serverPartsConsumed = [...byId.values()];
	}

	/**
	 * @description Internal helper: Rebuild Server Products Required.
	 */
	_rebuildServerProductsRequired() {
		const byId = new Map();
		for (const p of this._serverRequiredFromRelatedList) if (p.Id) byId.set(p.Id, p);
		for (const p of this._serverRequiredFromGraphql) if (p.Id) byId.set(p.Id, p);
		this._serverProductsRequired = [...byId.values()];
	}

	/**
	 * @description Internal helper: Rebuild Server Expenses.
	 */
	_rebuildServerExpenses() {
		const byId = new Map();
		for (const e of this._serverExpensesFromRelatedList) if (e.Id) byId.set(e.Id, e);
		for (const e of this._serverExpensesFromGraphql) if (e.Id) byId.set(e.Id, e);
		this._serverExpenses = [...byId.values()];
	}

	/**
	 * @description Internal helper: Normalize Part From Lds.
	 */
	_normalizePartFromLds(record) {
		const f = record.fields ?? {};
		const val = (api) => f[api]?.value ?? null;
		return {
			Id: record.id,
			QuantityConsumed: { value: val('QuantityConsumed') },
			Description: { value: val('Description') ?? '' },
			ProductItemId: { value: val('ProductItemId') },
			Product2Id: { value: val('Product2Id') },
			Returnable__c: { value: val('Returnable__c') },
			ServiceResource__c: { value: val('ServiceResource__c') ?? val('Service_Resource__c') },
			WorkOrderLineItemId: { value: val('WorkOrderLineItemId') }
		};
	}

	/**
	 * @description Internal helper: Normalize Required From Lds.
	 */
	_normalizeRequiredFromLds(record) {
		const f = record.fields ?? {};
		const val = (api) => f[api]?.value ?? null;
		return {
			Id: record.id,
			Product2Id: { value: val('Product2Id') },
			QuantityRequired: { value: val('QuantityRequired') },
			Returnable__c: { value: val('Returnable__c') ?? '' }
		};
	}

	/**
	 * @description Internal helper: Normalize Expense From Lds.
	 */
	_normalizeExpenseFromLds(record) {
		const f = record.fields ?? {};
		const val = (api) => f[api]?.value ?? null;
		return {
			Id: record.id,
			ExpenseType: { value: val('ExpenseType') ?? '' },
			Description: { value: val('Description') ?? '' },
			Quantity: { value: val('Quantity') },
			UnitPrice: { value: val('UnitPrice') },
			TotalPrice: { value: val('TotalPrice') },
			Amount: { value: val('Amount') }
		};
	}

	/**
	 * @description Internal helper: Build Labor Persist Fields.
	 */
	_buildLaborPersistFields(labor) {
		return {
			[WOLI_UNIT_QTY.fieldApiName]: Number(labor.quantity) || 0
		};
	}

	/**
	 * @description Create or update a labor line through Apex.
	 * @param {string|null} woliId Existing WOLI Id, or null when creating
	 * @param {Object} payload Pending add or edit
	 * @return {Promise<string|null>} Saved WOLI Id
	 */
	async _saveLaborLineViaApex(woliId, payload) {
		return saveLaborLine({
			workOrderId: this.recordId,
			workOrderLineItemId: this._isSalesforceWoliId(woliId) ? woliId : null,
			assignedResourceId: payload.assignedResourceId || null,
			workTypeId: payload.workTypeId || null,
			quantity: Number(payload.quantity) || 0,
			lineType: payload.lineType || payload._lineType || 'Labor',
			billingType: BILLING_TYPE_NON_BILLABLE
		});
	}

	/**
	 * @description Billing Type API value, defaulting to Billable unless a fallback is provided.
	 * @param {string} value Picklist value
	 * @param {string} [fallback=Billable]
	 * @return {string}
	 */
	_normalizeBillingType(value, fallback = BILLING_TYPE_BILLABLE) {
		return value || fallback;
	}

	/**
	 * @description Resolves Billing Type from edit/state/record, defaulting to Billable.
	 * @param {Object} [edit]
	 * @param {Object} [state]
	 * @param {string} [recordValue]
	 * @return {string}
	 */
	_resolveBillingType(edit, state, recordValue, fallback = BILLING_TYPE_BILLABLE) {
		return this._normalizeBillingType(state?.billingType ?? edit?.billingType ?? recordValue, fallback);
	}

	/**
	 * @description True when Billing Type should persist 100% Discount.
	 * @param {string} billingType
	 * @return {boolean}
	 */
	_isFullDiscountBillingType(billingType) {
		const resolved = this._normalizeBillingType(billingType);
		return resolved === BILLING_TYPE_COURTESY || resolved === BILLING_TYPE_WARRANTY;
	}

	/**
	 * @description 100% Discount when Billing Type is Warranty or Courtesy; otherwise none.
	 * @param {string} billingType
	 * @return {number|null}
	 */
	_discountForBillingType(billingType) {
		return this._isFullDiscountBillingType(billingType) ? 100 : 0;
	}

	/**
	 * @description Billing Type and Discount fields for LDS create/update.
	 * @param {Object} payload Pending add or edit
	 * @param {boolean} [includeDiscount=false] True for Parts lines that can have a unit price
	 * @return {Object}
	 */
	_buildBillingPersistFields(payload, includeDiscount = false) {
		const billingType = this._normalizeBillingType(payload?.billingType);
		const fields = {
			[WOLI_BILLING_TYPE.fieldApiName]: billingType
		};
		if (includeDiscount) {
			fields[WOLI_DISCOUNT.fieldApiName] = this._discountForBillingType(billingType);
		}
		return fields;
	}

	/**
	 * @description Product2 Id from a Parts add/edit payload.
	 * @param {Object} payload Pending add or edit
	 * @return {string|null}
	 */
	_partsProduct2Id(payload) {
		if (payload?.product2Id) {
			return payload.product2Id;
		}
		if (payload?.productItemId) {
			return this._product2IdByProductItemId[payload.productItemId] ?? null;
		}
		return null;
	}

	/**
	 * @description Warranty and Courtesy Discount require standard Product2Id, which is set
	 *              from PricebookEntryId. Product Item lines only populate ProductItem__c.
	 * @param {Object} fields Create/update field map
	 * @param {Object} payload Pending add or edit
	 * @return {Promise<void>}
	 */
	async _applyCourtesyProductPersistFields(fields, payload) {
		if (!this._isFullDiscountBillingType(payload?.billingType)) {
			return;
		}
		const product2Id = payload?.deviceTypeId || this._partsProduct2Id(payload);
		const pricebookEntryId = fields[WOLI_PRICEBOOK_ENTRY.fieldApiName]
			|| (product2Id ? await this._resolvePricebookEntryIdForProduct(product2Id) : null);
		if (!pricebookEntryId) {
			delete fields[WOLI_DISCOUNT.fieldApiName];
			throw new Error(
				'Warranty and Courtesy discount require a pricebook entry for the selected item.'
			);
		}
		fields[WOLI_PRICEBOOK_ENTRY.fieldApiName] = pricebookEntryId;
		fields[WOLI_DISCOUNT.fieldApiName] = 100;
	}

	/**
	 * @description Time lines are always Non-Billable.
	 * @return {Object}
	 */
	_buildTimeBillingPersistFields() {
		return {
			[WOLI_BILLING_TYPE.fieldApiName]: BILLING_TYPE_NON_BILLABLE
		};
	}

	/**
	 * @description Display label for Billing Type.
	 * @param {string} value Picklist API value
	 * @return {string}
	 */
	_fmtBillingType(value) {
		if (value == null || value === '') {
			return '';
		}
		return this.billingTypeOptions.find(option => option.value === value)?.label ?? value;
	}

	/**
	 * @description True when the value is a Salesforce Work Order Line Item Id.
	 * @param {string} value Candidate Id
	 * @return {boolean}
	 */
	_isSalesforceWoliId(value) {
		return typeof value === 'string' && /^1WL[a-zA-Z0-9]{12}([a-zA-Z0-9]{3})?$/i.test(value);
	}

	/**
	 * @description GW-375 - Record id sent to Apex. Keeps all 18 characters so a lowercased mobile id can be repaired.
	 * @param {*} value Record id from the screen
	 * @return {string|null}
	 */
	_apexId(value) {
		if (value == null) {
			return null;
		}
		const text = String(value).trim();
		if (!/^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$/.test(text)) {
			return null;
		}
		return text;
	}

	/**
	 * @description GW-375 - Map key for a record's pictures. Ignores id length and case.
	 * @param {*} value Record id
	 * @return {string}
	 */
	_pictureRecordKey(value) {
		const id = this._apexId(value);
		return id ? id.substring(0, 15).toUpperCase() : '';
	}

	/**
	 * @description Internal helper: Build Instrument Persist Fields.
	 */
	_buildInstrumentPersistFields(instrument) {
		const deviceType = instrument.deviceType
			|| this._productCodeByProduct2Id[instrument.deviceTypeId]
			|| '';
		const repairLevel = instrument.repairLevel
			|| this._repairLevelFromServiceCodeId(instrument.serviceCodeId)
			|| '';
		return {
			[WOLI_DEVICE_TYPE.fieldApiName]: deviceType,
			[WOLI_REPAIR_LEVEL.fieldApiName]: repairLevel,
			...(instrument?.status ? { [WOLI_LINE_STATUS.fieldApiName]: instrument.status } : {}),
			...this._repairCenterPersistFields(instrument)
		};
	}

	/**
	 * @description Beyond-repair values saved on the work order line.
	 *              Send to Repair Center is set only for Forward to National Repair Center for Service.
	 * @param {Object} instrument Staged instrument line
	 * @return {Object}
	 */
	_repairCenterPersistFields(instrument) {
		const serviceCodeId = instrument?.serviceCodeId;
		if (!serviceCodeId) {
			if (this._lineNeedsObrDetails(instrument)) {
				return this._obrDetailPersistFields(instrument, !!instrument.sendToRepairCenter);
			}
			if (instrument && 'replacedWithIXchange' in instrument) {
				return {
					[WOLI_REPLACED_WITH_IXCHANGE.fieldApiName]: !instrument.sendToRepairCenter
						&& !!instrument.replacedWithIXchange
				};
			}
			return {};
		}
		const sendToRepairCenter = this._isRepairCenterServiceCode(serviceCodeId);
		const fields = {
			[WOLI_SEND_TO_REPAIR_CENTER.fieldApiName]: sendToRepairCenter
		};
		if (!this._showsObrDetailFields(serviceCodeId)) {
			fields[WOLI_SERIAL_NUMBER.fieldApiName] = null;
			fields[WOLI_MODEL.fieldApiName] = null;
			fields[WOLI_DEPARTMENT.fieldApiName] = null;
			fields[WOLI_REPORTED_PROBLEM.fieldApiName] = null;
			fields[WOLI_ADDITIONAL_SERVICES.fieldApiName] = false;
			fields[WOLI_INSULATION.fieldApiName] = null;
			fields[WOLI_REPLACED_WITH_IXCHANGE.fieldApiName] = false;
			return fields;
		}
		return { ...fields, ...this._obrDetailPersistFields(instrument, sendToRepairCenter) };
	}

	/**
	 * @description Beyond Repair Info values written to the work order line.
	 * @param {Object} instrument Staged instrument line
	 * @param {boolean} sendToRepairCenter True when the line goes to the Repair Center
	 * @return {Object}
	 */
	_obrDetailPersistFields(instrument, sendToRepairCenter) {
		const additionalServices = !!instrument.additionalServices;
		return {
			[WOLI_REPLACED_WITH_IXCHANGE.fieldApiName]: !sendToRepairCenter && !!instrument.replacedWithIXchange,
			[WOLI_SERIAL_NUMBER.fieldApiName]: String(instrument.serialNumber || '').trim(),
			[WOLI_MODEL.fieldApiName]: String(instrument.model || '').trim(),
			[WOLI_DEPARTMENT.fieldApiName]: instrument.departmentId || null,
			[WOLI_REPORTED_PROBLEM.fieldApiName]: String(instrument.reportedProblem || '').trim(),
			[WOLI_ADDITIONAL_SERVICES.fieldApiName]: additionalServices,
			[WOLI_INSULATION.fieldApiName]: additionalServices
				? this._insulationPersistValue(instrument.insulationPowderCoating)
				: null
		};
	}

	/**
	 * @description Keeps the saved Beyond Repair values on screen after Save All, before the query refreshes.
	 *              Without this, the line reopens with the old values and the next save writes them back.
	 * @param {string} lineId Work order line Id
	 * @param {Object} fields Fields sent to the line
	 */
	_rememberRepairCenterFields(lineId, fields) {
		if (!lineId || !fields) return;
		const has = field => Object.prototype.hasOwnProperty.call(fields, field.fieldApiName);
		const next = { ...(this._repairCenterByLineId[lineId] || {}) };
		if (has(WOLI_SERIAL_NUMBER)) next.serialNumber = fields[WOLI_SERIAL_NUMBER.fieldApiName] ?? '';
		if (has(WOLI_MODEL)) next.model = fields[WOLI_MODEL.fieldApiName] ?? '';
		if (has(WOLI_DEPARTMENT)) next.departmentId = fields[WOLI_DEPARTMENT.fieldApiName] ?? null;
		if (has(WOLI_REPORTED_PROBLEM)) next.reportedProblem = fields[WOLI_REPORTED_PROBLEM.fieldApiName] ?? '';
		if (has(WOLI_ADDITIONAL_SERVICES)) next.additionalServices = !!fields[WOLI_ADDITIONAL_SERVICES.fieldApiName];
		if (has(WOLI_INSULATION)) next.insulationPowderCoating = fields[WOLI_INSULATION.fieldApiName] ?? '';
		if (has(WOLI_SEND_TO_REPAIR_CENTER)) next.sendToRepairCenter = !!fields[WOLI_SEND_TO_REPAIR_CENTER.fieldApiName];
		if (has(WOLI_REPLACED_WITH_IXCHANGE)) {
			next.replacedWithIXchange = !!fields[WOLI_REPLACED_WITH_IXCHANGE.fieldApiName];
		}
		this._repairCenterByLineId = { ...this._repairCenterByLineId, [lineId]: next };
		this.repairCenterUiVersion += 1;
	}

	/**
	 * @description Template values for the repair-center fields on an instrument line.
	 * @param {string} lineId Line or temp Id
	 * @param {string} serviceCodeId Selected Service Code Id
	 * @param {Object} source Staged values
	 * @param {Object} stored Values already saved on the line
	 * @return {Object}
	 */
	_repairCenterFieldModel(lineId, serviceCodeId, source, stored) {
		void this.repairCenterUiVersion;
		void this.repairCodeUiVersion;
		const saved = stored || {};
		const showRepairCenterFields = serviceCodeId
			? this._showsObrDetailFields(serviceCodeId)
			: this._lineNeedsObrDetails(saved);
		const additionalServices = source?.additionalServices ?? saved.additionalServices ?? false;
		return {
			showRepairCenterFields,
			editSerialNumber: source?.serialNumber ?? saved.serialNumber ?? '',
			editModel: source?.model ?? saved.model ?? '',
			editDepartmentId: source?.departmentId
				?? saved.departmentId
				?? (showRepairCenterFields ? this._assetDepartmentId() : null),
			editReportedProblem: source?.reportedProblem ?? saved.reportedProblem ?? '',
			editAdditionalServices: !!additionalServices,
			showInsulationField: showRepairCenterFields && !!additionalServices,
			showReplacedWithIXchangeField: showRepairCenterFields
				&& this._showsReplacedWithIXchange(serviceCodeId, saved),
			editReplacedWithIXchange: !!(source?.replacedWithIXchange ?? saved.replacedWithIXchange),
			editInsulationPowderCoating: this._insulationList(
				source?.insulationPowderCoating ?? saved.insulationPowderCoating
			),
		};
	}

	/**
	 * @description True when the Service Code is Forward to National Repair Center for Service.
	 *              This is the only code that sets Send to Repair Center.
	 * @param {string} serviceCodeId Service Code Product2 Id
	 * @return {boolean}
	 */
	_isRepairCenterServiceCode(serviceCodeId) {
		if (!serviceCodeId) return false;
		const text = [
			this._repairCodeNameById[serviceCodeId],
			this._repairCodeDescriptionById[serviceCodeId],
			this._productNameByProduct2Id[serviceCodeId]
		].filter(Boolean).join(' ');
		return text.toLowerCase().includes(REPAIR_CENTER_SERVICE_TEXT);
	}

	/**
	 * @description True when the Service Code product code is a beyond-repair OBR code.
	 * @param {string} serviceCodeId Service Code Product2 Id
	 * @return {boolean}
	 */
	_isObrServiceCodeId(serviceCodeId) {
		if (!serviceCodeId) return false;
		const productCode = this._repairCodeProductCodeById[serviceCodeId]
			|| this._productCodeByProduct2Id[serviceCodeId]
			|| '';
		return OBR_PRODUCT_CODE_PATTERN.test(String(productCode));
	}

	/**
	 * @description True when Beyond Repair Info should be collected for this Service Code.
	 *              Every OBR code opens the fields. Send to Repair Center stays limited to
	 *              Forward to National Repair Center for Service.
	 * @param {string} serviceCodeId Service Code Product2 Id
	 * @return {boolean}
	 */
	_showsObrDetailFields(serviceCodeId) {
		return this._isObrServiceCodeId(serviceCodeId) || this._isRepairCenterServiceCode(serviceCodeId);
	}

	/**
	 * @description GW-6191 - True when Replaced with I-Xchange applies: a beyond-repair line
	 *              that is not Forward to National Repair Center for Service.
	 * @param {string} serviceCodeId Selected Service Code Id
	 * @param {Object} stored Values already saved on the line, used when no Service Code is selected
	 * @return {boolean}
	 */
	_showsReplacedWithIXchange(serviceCodeId, stored) {
		if (serviceCodeId) {
			return this._isObrServiceCodeId(serviceCodeId) && !this._isRepairCenterServiceCode(serviceCodeId);
		}
		return !!stored && !stored.sendToRepairCenter && this._hasObrDetailValues(stored);
	}

	/**
	 * @description True when the line should show and require the beyond-repair fields.
	 * @param {Object} payload Selected service code or values already stored on the line
	 * @return {boolean}
	 */
	_lineNeedsObrDetails(payload) {
		const serviceCodeId = payload?.serviceCodeId;
		if (serviceCodeId) {
			return this._showsObrDetailFields(serviceCodeId);
		}
		return !!payload?.sendToRepairCenter || this._hasObrDetailValues(payload);
	}

	/**
	 * @description True when a line already has beyond-repair details saved.
	 * @param {Object} source Staged or stored line values
	 * @return {boolean}
	 */
	_hasObrDetailValues(source) {
		if (!source) return false;
		return !!String(source.serialNumber || '').trim()
			|| !!String(source.model || '').trim()
			|| !!String(source.reportedProblem || '').trim()
			|| !!source.additionalServices
			|| this._insulationList(source.insulationPowderCoating).length > 0;
	}

	/**
	 * @description Multi-select values as a list.
	 * @param {string|Array} value Stored or staged insulation values
	 * @return {Array}
	 */
	_insulationList(value) {
		if (Array.isArray(value)) return value.filter(Boolean);
		if (!value) return [];
		return String(value).split(';').map(item => item.trim()).filter(Boolean);
	}

	/**
	 * @description Multi-select values stored as a semicolon-separated string.
	 * @param {string|Array} value Staged insulation values
	 * @return {string|null}
	 */
	_insulationPersistValue(value) {
		const items = this._insulationList(value);
		return items.length ? items.join(';') : null;
	}

	/**
	 * @description Record Type, Quantity, Line Type, and Device Type Pricebook Entry.
	 *              Product2Id is read-only on WorkOrderLineItem and is set from PricebookEntryId.
	 * @param {{ deviceTypeId: string, quantity: * }} instrument Staged instrument line
	 * @return {Promise<Object>} Fields to merge into create/update
	 */
	async _instrumentProductPersistFields(instrument) {
		const deviceTypeId = instrument?.deviceTypeId;
		const fields = {
			[WOLI_QUANTITY.fieldApiName]: Number(instrument?.quantity),
			[WOLI_LINETYPE.fieldApiName]: INSTRUMENT_LINE_TYPE
		};
		if (this._productServicedRecordTypeId) {
			fields[WOLI_RECORD_TYPE.fieldApiName] = this._productServicedRecordTypeId;
		}
		if (!deviceTypeId) {
			throw new Error('Device Type is required.');
		}
		const pricebookEntryId = await this._resolvePricebookEntryIdForProduct(deviceTypeId);
		if (!pricebookEntryId) {
			throw new Error('No pricebook entry found for the selected Device Type.');
		}
		fields[WOLI_PRICEBOOK_ENTRY.fieldApiName] = pricebookEntryId;
		return fields;
	}

	/**
	 * @description Active PricebookEntry for a Device Type from the GraphQL @wire cache.
	 * @param {string} product2Id Device Type Product2 Id
	 * @return {Promise<string|null>} PricebookEntry Id, or null when none match
	 */
	async _resolvePricebookEntryIdForProduct(product2Id) {
		if (!product2Id) return null;
		if (this._pricebookEntryIdByProduct2Id[product2Id]) {
			return this._pricebookEntryIdByProduct2Id[product2Id];
		}
		this._pbeQueryProduct2Id = product2Id;
		for (let attempt = 0; attempt < 15; attempt += 1) {
			if (this._pricebookEntryIdByProduct2Id[product2Id]) {
				return this._pricebookEntryIdByProduct2Id[product2Id];
			}
			await new Promise((resolve) => setTimeout(resolve, 200));
		}
		return this._pricebookEntryIdByProduct2Id[product2Id] ?? null;
	}

	/**
	 * @description Product2 lookup by Product Code (optional Product Type) via GraphQL.
	 * @param {string} productCode Scanned or typed Product Code
	 * @param {string} [productType] ProductType__c filter
	 * @return {Promise<Object>} Match payload used by scan handlers
	 */
	async _findProductByProductCode(productCode, productType) {
		const code = (productCode ?? '').trim();
		if (!code) return { product2Id: null, matchCount: 0 };
		const result = await graphql(this, {
			query: productType ? PRODUCT_BY_CODE_TYPE_QUERY : PRODUCT_BY_CODE_QUERY,
			variables: productType ? { productCode: code, productType } : { productCode: code }
		});
		const edges = result?.data?.uiapi?.query?.Product2?.edges ?? [];
		const node = edges[0]?.node;
		if (!node?.Id) return { product2Id: null, matchCount: 0 };
		return {
			product2Id: node.Id,
			productName: node.Name?.value ?? '',
			productCode: node.ProductCode?.value ?? code,
			description: node.Description?.value ?? '',
			isReturnable: node.IsReturnable__c?.value,
			matchCount: edges.length
		};
	}

	/**
	 * @description Product Item barcode lookup is Apex-backed elsewhere; skip it here
	 *              so Field Service users are not blocked by class access.
	 * @return {Promise<Object>} Empty match
	 */
	async _findProductItemByProductCode() {
		return { productItemId: null, locationId: null, matchCount: 0 };
	}

	/**
	 * @description Applies a Device Type product selection on the add form.
	 * @param {Object} next Mutable add-form state
	 * @param {string|null} deviceTypeId Selected Product2 Id
	 * @param {string} [knownProductCode] Optional Product Code already known from scan
	 */
	_applyDeviceTypeSelection(next, deviceTypeId, knownProductCode) {
		next.serviceCodeId = null;
		next.repairLevel = '';
		next.deviceType = knownProductCode
			|| this._productCodeByProduct2Id[deviceTypeId]
			|| '';
		if (deviceTypeId) {
			this._product2LookupId = deviceTypeId;
			this._loadProductMeta(deviceTypeId);
			this._loadRepairCodesForProduct(deviceTypeId);
		}
	}

	/**
	 * @description Stages a Device Type product selection on an existing/pending line.
	 * @param {string} lineId Line or temp Id
	 * @param {string|null} deviceTypeId Selected Product2 Id
	 * @param {string} [knownProductCode] Optional Product Code already known from scan
	 */
	_stageDeviceTypeSelection(lineId, deviceTypeId, knownProductCode) {
		this._stageEdit(lineId, 'serviceCodeId', null);
		this._stageEdit(lineId, 'repairLevel', '');
		this._stageEdit(
			lineId,
			'deviceType',
			knownProductCode || this._productCodeByProduct2Id[deviceTypeId] || ''
		);
		if (deviceTypeId) {
			this._product2LookupId = deviceTypeId;
			this._loadProductMeta(deviceTypeId);
			this._loadRepairCodesForProduct(deviceTypeId);
		}
	}

	/**
	 * @description Applies a Service Code product selection on the add form.
	 * @param {Object} next Mutable add-form state
	 * @param {string|null} serviceCodeId Selected Service Code Product2 Id
	 */
	_applyServiceCodeSelection(next, serviceCodeId) {
		next.repairLevel = this._repairLevelFromServiceCodeId(serviceCodeId);
		if (this._showsObrDetailFields(serviceCodeId) && !next.departmentId) {
			next.departmentId = this._assetDepartmentId();
		}
		if (serviceCodeId) {
			this._repairCodeLookupId = serviceCodeId;
			this._loadProductMeta(serviceCodeId);
		}
	}

	/**
	 * @description Stages a Service Code product selection on an existing/pending line.
	 * @param {string} lineId Line or temp Id
	 * @param {string|null} serviceCodeId Selected Service Code Product2 Id
	 */
	_stageServiceCodeSelection(lineId, serviceCodeId) {
		this._stageEdit(lineId, 'repairLevel', this._repairLevelFromServiceCodeId(serviceCodeId));
		if (this._showsObrDetailFields(serviceCodeId)) {
			this._defaultDepartmentOnEdit(lineId);
		}
		if (serviceCodeId) {
			this._repairCodeLookupId = serviceCodeId;
			this._loadProductMeta(serviceCodeId);
		}
	}

	/**
	 * @description Last digit of the Service Code Item Number / Product Code.
	 * @param {string} serviceCodeId Service Code Product2 Id
	 * @return {string} Repair Level digit, or empty
	 */
	_repairLevelFromServiceCodeId(serviceCodeId) {
		if (!serviceCodeId) return '';
		const productCode = this._repairCodeProductCodeById[serviceCodeId]
			|| this._productCodeByProduct2Id[serviceCodeId]
			|| '';
		const match = String(productCode).match(/(\d)$/);
		return match ? match[1] : '';
	}

	/**
	 * @description Instrument list summary: quantity, service code, repair level, and billing type.
	 * @param {Object} line Resolved instrument values
	 * @return {string}
	 */
	_instrumentSummaryMeta({ quantity, serviceCodeId, deviceTypeId, repairLevel, billingType }) {
		void this.repairCodeUiVersion;
		const resolvedId = serviceCodeId || this._matchServiceCodeId(deviceTypeId, repairLevel);
		const serviceCodeLabel = this._serviceCodeSummaryLabel(resolvedId);
		const parts = [];
		if (quantity !== '' && quantity != null) parts.push(`QTY ${quantity}`);
		if (serviceCodeLabel) parts.push(serviceCodeLabel);
		if (repairLevel !== '' && repairLevel != null) parts.push(`Repair Level - ${repairLevel}`);
		const billingLabel = this._fmtBillingType(billingType);
		if (billingLabel) parts.push(billingLabel);
		return parts.join(' · ');
	}

	/**
	 * @description Service Code label for the instrument summary (product code and name).
	 * @param {string} serviceCodeId Service Code Product2 Id
	 * @return {string}
	 */
	_serviceCodeSummaryLabel(serviceCodeId) {
		if (!serviceCodeId) return '';
		const productCode = this._repairCodeProductCodeById[serviceCodeId] || '';
		const name = this._repairCodeNameById[serviceCodeId]
			|| this._productNameByProduct2Id[serviceCodeId]
			|| '';
		if (productCode && name) return `${productCode} — ${name}`;
		return productCode || name;
	}

	/**
	 * @description Caches Service Code product code, name, and full description.
	 * @param {Array} nodes Product2 nodes from the service-code query
	 * @return {Array} Combobox options
	 */
	_cacheServiceCodeNodes(nodes) {
		const codesById = { ...this._repairCodeProductCodeById };
		const namesById = { ...this._repairCodeNameById };
		const descriptionsById = { ...this._repairCodeDescriptionById };
		const options = [];
		for (const node of nodes || []) {
			if (!node?.Id) continue;
			const productCode = node.ProductCode?.value ?? '';
			const name = node.Name?.value ?? '';
			const description = node.Description?.value ?? '';
			options.push({
				label: productCode && name ? `${productCode} — ${name}` : (productCode || name || node.Id),
				value: node.Id
			});
			if (productCode) codesById[node.Id] = productCode;
			if (name) namesById[node.Id] = name;
			descriptionsById[node.Id] = description;
		}
		this._repairCodeProductCodeById = codesById;
		this._repairCodeNameById = namesById;
		this._repairCodeDescriptionById = descriptionsById;
		return options;
	}

	/**
	 * @description Queues the Service Codes of each Instrument device type on the work order.
	 *              The Service Code wire serves one Device Type at a time, so the rest wait in the queue
	 *              and load as each one finishes.
	 * @param {Array} lines Work order line nodes
	 */
	_prefetchInstrumentServiceCodes(lines) {
		const pending = [];
		for (const line of lines ?? []) {
			if (!INSTRUMENT_TAB_LINE_TYPES.has(line.LineType__c?.value)) continue;
			const deviceTypeId = line.Product2Id?.value ?? line.Product2?.Id;
			if (!deviceTypeId || pending.includes(deviceTypeId)) continue;
			if (Object.prototype.hasOwnProperty.call(this._repairCodeOptionsByProduct2Id, deviceTypeId)) continue;
			pending.push(deviceTypeId);
		}
		if (!pending.length) return;
		const loading = { ...this._repairCodeLoadingByProduct2Id };
		pending.forEach(deviceTypeId => { loading[deviceTypeId] = true; });
		this._repairCodeLoadingByProduct2Id = loading;
		this.repairCodeUiVersion += 1;
		this._loadNextQueuedServiceCodes();
	}

	/**
	 * @description Starts the next queued Device Type when the Service Code wire is free.
	 */
	_loadNextQueuedServiceCodes() {
		const current = this._serviceCodeQueryProduct2Id;
		if (current && this._repairCodeLoadingByProduct2Id[current]) return;
		const next = Object.keys(this._repairCodeLoadingByProduct2Id).find(product2Id => (
			this._repairCodeLoadingByProduct2Id[product2Id]
			&& !Object.prototype.hasOwnProperty.call(this._repairCodeOptionsByProduct2Id, product2Id)
		));
		if (next) {
			this._loadRepairCodesForProduct(next);
		}
	}

	/**
	 * @description Service Codes already loaded for another Device Type with the same Base Service Code.
	 *              The wire does not run again for the same query, so these are reused.
	 * @param {string} base Base Service Code
	 * @return {Array|null}
	 */
	_loadedServiceCodesForBase(base) {
		if (!base) return null;
		const loadedId = Object.keys(this._repairCodeOptionsByProduct2Id).find(product2Id => (
			this._baseServiceCodeByProduct2Id[product2Id] === base
			&& !this._repairCodeLoadingByProduct2Id[product2Id]
		));
		return loadedId ? this._repairCodeOptionsByProduct2Id[loadedId] : null;
	}

	/**
	 * @description Finds a loaded Service Code whose Item Number ends with the stored Repair Level.
	 * @param {string} deviceTypeId Device Type Product2 Id
	 * @param {string} repairLevel Last-digit repair level
	 * @return {string|null} Matching Service Code Product2 Id
	 */
	_matchServiceCodeId(deviceTypeId, repairLevel) {
		if (!deviceTypeId || repairLevel == null || repairLevel === '') return null;
		const level = String(repairLevel).trim();
		const options = this._repairCodeOptionsForProduct(deviceTypeId);
		const match = options.find(opt => {
			const code = this._repairCodeProductCodeById[opt.value] || opt.label || '';
			return String(code).endsWith(level);
		});
		return match?.value ?? null;
	}

	/**
	 * @description Service Code of a saved instrument line. The line stores only the Repair Level,
	 *              so the code is matched from the Device Type Service Codes. A line with Beyond Repair
	 *              Info only matches a beyond-repair code, so saving it does not clear Make and Model.
	 * @param {string} deviceTypeId Device Type Product2 Id
	 * @param {string} repairLevel Saved Repair Level
	 * @param {Object} stored Beyond Repair values saved on the line
	 * @return {string|null} Service Code Product2 Id, or null when it cannot be matched
	 */
	_savedServiceCodeId(deviceTypeId, repairLevel, stored) {
		if (!deviceTypeId || repairLevel == null || repairLevel === '') return null;
		const level = String(repairLevel).trim();
		const matches = this._repairCodeOptionsForProduct(deviceTypeId)
			.map(opt => opt.value)
			.filter(id => String(this._repairCodeProductCodeById[id] || '').endsWith(level));
		if (!matches.length) return null;
		if (!this._lineNeedsObrDetails(stored)) {
			return matches.find(id => !this._showsObrDetailFields(id)) ?? null;
		}
		const beyondRepair = matches.filter(id => this._showsObrDetailFields(id));
		const repairCenter = beyondRepair.find(id => this._isRepairCenterServiceCode(id));
		const otherBeyondRepair = beyondRepair.find(id => !this._isRepairCenterServiceCode(id));
		return stored?.sendToRepairCenter
			? (repairCenter ?? otherBeyondRepair ?? null)
			: (otherBeyondRepair ?? repairCenter ?? null);
	}

	/**
	 * @description Service Code combobox UI keyed off Device Type (reuses getRepairCodesForProduct cache).
	 * @param {string} deviceTypeId Device Type Product2 Id
	 * @return {Object} Template properties for the Service Code combobox
	 */
	_serviceCodeComboboxUiForDeviceType(deviceTypeId, selectedId) {
		const ui = this._repairCodeComboboxUiForProduct(deviceTypeId);
		const placeholder = (ui.repairCodeComboboxPlaceholder || '')
			.replace('Select an instrument first', 'Select a device type first');
		const status = (ui.repairCodeStatusMessage || '')
			.replace('Select an instrument first', 'Select a device type first');
		return {
			serviceCodeLoading: ui.repairCodeLoading,
			serviceCodeOptions: this._serviceCodeListOptions(ui.repairCodeOptions, selectedId),
			serviceCodeComboboxPlaceholder: placeholder,
			showServiceCodeCombobox: ui.showRepairCodeCombobox,
			serviceCodeStatusMessage: status
		};
	}

	/**
	 * @description Service Code list with normal codes first and OBR codes last.
	 * @param {Array} options Cached service-code options
	 * @param {string} selectedId Selected Service Code Id
	 * @return {Array}
	 */
	_serviceCodeListOptions(options, selectedId) {
		const sorted = [...(options || [])].sort((left, right) => {
			const leftBeyondRepair = this._isObrServiceCode(left);
			const rightBeyondRepair = this._isObrServiceCode(right);
			if (leftBeyondRepair !== rightBeyondRepair) {
				return leftBeyondRepair ? 1 : -1;
			}
			return String(left.label || '').localeCompare(String(right.label || ''));
		});
		return sorted.map(option => ({
			...option,
			optionClass: option.value === selectedId
				? 'service-code-option service-code-option_selected'
				: 'service-code-option'
		}));
	}

	/**
	 * @description True when the Service Code product code is a beyond-repair OBR code.
	 * @param {Object} option Service code option
	 * @return {boolean}
	 */
	_isObrServiceCode(option) {
		const productCode = this._repairCodeProductCodeById[option?.value] || option?.label || '';
		return OBR_PRODUCT_CODE_PATTERN.test(String(productCode));
	}

	/**
	 * @description NL service-code prefixes plus the same prefixes with NL replaced by BR.
	 *              SC.ONL.130 also matches beyond-repair codes SC.OBR.130 / SC.OBR1304.
	 * @param {string} base Device Type Base Service Code
	 * @return {Object} GraphQL like-pattern variables
	 */
	_serviceCodeLikePatterns(base) {
		const likePattern = `${base}%`;
		const itemNumberLike = `${String(base).replace(/\.(\d+)$/, '$1')}%`;
		const beyondRepairBase = String(base).replace(/NL/gi, 'BR');
		return {
			likePattern,
			itemNumberLike,
			beyondRepairLike: `${beyondRepairBase}%`,
			beyondRepairItemNumberLike: `${beyondRepairBase.replace(/\.(\d+)$/, '$1')}%`
		};
	}

	/**
	 * @description Moves the Work Order to In Progress when an instrument line is added.
	 *              Removes that change if the new line is deleted before it is saved.
	 */
	_syncWorkOrderInProgress() {
		const storedStatus = this._workOrder?.Status?.value;
		if (this._hasPendingInstrumentAdd() && this._shouldMoveWorkOrderToInProgress(storedStatus)) {
			if (this._statusBeforeInProgress === undefined) {
				this._statusBeforeInProgress = storedStatus ?? '';
			}
			this._pendingWorkOrderStatus = WO_STATUS_IN_PROGRESS;
			this._enqueueWorkOrderStatus(WO_STATUS_IN_PROGRESS);
			return;
		}
		if (this._hasPendingInstrumentAdd()) {
			return;
		}
		this._pendingWorkOrderStatus = undefined;
		if (this._hasSavedInstrumentLine() || this._statusBeforeInProgress === undefined) {
			return;
		}
		const revertTo = this._statusBeforeInProgress;
		this._statusBeforeInProgress = undefined;
		if (revertTo && revertTo !== WO_STATUS_IN_PROGRESS) {
			this._enqueueWorkOrderStatus(revertTo);
		}
	}

	/**
	 * @description True when the Work Order can leave its current status for In Progress.
	 * @param {string} status Stored Work Order status
	 * @return {boolean}
	 */
	_shouldMoveWorkOrderToInProgress(status) {
		if (WO_CLOSED_STATUSES.has(status)) return false;
		return status !== WO_STATUS_IN_PROGRESS;
	}

	/**
	 * @description True when an instrument line has been added and is not saved yet.
	 * @return {boolean}
	 */
	_hasPendingInstrumentAdd() {
		return this._pendingAdds.some(add => add._schema === 'instrument');
	}

	/**
	 * @description True when a saved instrument line is still on the Work Order.
	 * @return {boolean}
	 */
	_hasSavedInstrumentLine() {
		return (this._serverLines || []).some(line =>
			!this._pendingDeletes[line.Id]
			&& INSTRUMENT_TAB_LINE_TYPES.has(line.LineType__c?.value)
		);
	}

	/**
	 * @description Writes the Work Order status once. Later requests wait, so the last one wins.
	 * @param {string} status Status to store
	 * @return {Promise<void>}
	 */
	_enqueueWorkOrderStatus(status) {
		if (!status || !this.recordId || status === this._queuedWorkOrderStatus) {
			return this._statusWriteChain;
		}
		this._queuedWorkOrderStatus = status;
		this._holdInProgressStatus = status === WO_STATUS_IN_PROGRESS;
		const write = this._statusWriteChain
			.catch(() => undefined)
			.then(async () => {
				try {
					await updateRecord({
						fields: {
							Id: this.recordId,
							[WO_STATUS.fieldApiName]: status
						}
					});
					this._applyLocalWorkOrderStatus(status);
					if (status === WO_STATUS_IN_PROGRESS) {
						this._pendingWorkOrderStatus = undefined;
					} else {
						this._holdInProgressStatus = false;
					}
					notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
				} catch (error) {
					if (this._queuedWorkOrderStatus === status) {
						this._queuedWorkOrderStatus = this._workOrder?.Status?.value;
					}
					if (status === WO_STATUS_IN_PROGRESS) {
						this._holdInProgressStatus = false;
					}
					this._toast('Status was not updated', this._errorMessage(error), 'error');
				}
			});
		this._statusWriteChain = write;
		return write;
	}

	/**
	 * @description Keeps a just-set In Progress status when a refresh still has the previous status.
	 * @param {Object} node Work Order node from GraphQL
	 * @return {Object}
	 */
	_workOrderFromWire(node) {
		const serverStatus = node?.Status?.value;
		if (serverStatus === WO_STATUS_IN_PROGRESS || WO_CLOSED_STATUSES.has(serverStatus)) {
			this._holdInProgressStatus = false;
			return node;
		}
		if (this._holdInProgressStatus || this._pendingWorkOrderStatus === WO_STATUS_IN_PROGRESS) {
			return { ...node, Status: { value: WO_STATUS_IN_PROGRESS } };
		}
		return node;
	}

	/**
	 * @description Stores the Work Order status on the loaded header.
	 * @param {string} status Status value
	 */
	_applyLocalWorkOrderStatus(status) {
		if (!this._workOrder) return;
		this._workOrder = {
			...this._workOrder,
			Status: { value: status }
		};
	}

	/**
	 * @description Whole-number Quantity used for Total Serviced Instruments.
	 * @param {*} value Line quantity
	 * @return {number}
	 */
	_instrumentQuantityNumber(value) {
		if (value === '' || value == null) return 0;
		const parsed = Number(value);
		return Number.isFinite(parsed) ? parsed : 0;
	}

	/**
	 * @description Sum of Instrument line quantities, including unsaved adds, edits, and deletes.
	 * @return {number}
	 */
	_sumServicedInstrumentQuantities() {
		let total = 0;
		for (const line of this._serverLines) {
			if (this._pendingDeletes[line.Id]) continue;
			if (!INSTRUMENT_TAB_LINE_TYPES.has(line.LineType__c?.value)) continue;
			const edit = this._pendingEdits[line.Id];
			const raw = edit ? edit.quantity : line.Quantity?.value;
			total += this._instrumentQuantityNumber(raw);
		}
		for (const add of this._pendingAdds) {
			if (add._schema !== 'instrument') continue;
			total += this._instrumentQuantityNumber(add.quantity);
		}
		return Math.round(total);
	}

	/**
	 * @description Stored Total Serviced Instruments, or null when the Work Order field is blank.
	 * @return {number|null}
	 */
	_storedTotalServicedInstruments() {
		const raw = this._workOrder?.TotalServicedInstruments__c?.value;
		if (raw === null || raw === undefined || raw === '') return null;
		const parsed = Number(raw);
		return Number.isNaN(parsed) ? null : parsed;
	}

	/**
	 * @description True when the calculated instrument total should be written on save.
	 * @return {boolean}
	 */
	_totalServicedInstrumentsNeedsSave() {
		if (!this._workOrder) return false;
		return this._shouldPersistTotalServicedInstruments(this._sumServicedInstrumentQuantities());
	}

	/**
	 * @description Blank stored totals are left alone when the calculated total is zero.
	 * @param {number} value Calculated total to persist
	 * @return {boolean}
	 */
	_shouldPersistTotalServicedInstruments(value) {
		const stored = this._storedTotalServicedInstruments();
		if (stored === null) return value !== 0;
		return stored !== value;
	}

	/**
	 * @description Calculated total after dropping instrument changes that failed to save.
	 * @param {Object} failedDeletes Delete ids that did not save
	 * @param {Object} failedEdits Edits that did not save
	 * @param {Array} failedAdds Adds that did not save
	 * @return {number}
	 */
	_instrumentTotalForPersist(failedDeletes, failedEdits, failedAdds) {
		let total = this._sumServicedInstrumentQuantities();
		for (const id of Object.keys(failedDeletes || {})) {
			const line = this._serverLines.find(l => l.Id === id);
			if (!line || !INSTRUMENT_TAB_LINE_TYPES.has(line.LineType__c?.value)) continue;
			total += this._instrumentQuantityNumber(line.Quantity?.value);
		}
		for (const [id, edit] of Object.entries(failedEdits || {})) {
			if (edit?._schema !== 'instrument') continue;
			const line = this._serverLines.find(l => l.Id === id);
			total += this._instrumentQuantityNumber(line?.Quantity?.value)
				- this._instrumentQuantityNumber(edit.quantity);
		}
		for (const add of failedAdds || []) {
			if (add?._schema !== 'instrument') continue;
			total -= this._instrumentQuantityNumber(add.quantity);
		}
		return Math.max(0, Math.round(total));
	}

	/**
	 * @description Current Device Type and Billing Type for cloning an Instrument line.
	 * @param {string} lineId Line or temp Id
	 * @return {Object|null}
	 */
	_instrumentCloneSource(lineId) {
		const pendingAdd = this._pendingAdds.find(a => a._tempId === lineId);
		if (pendingAdd) {
			return {
				deviceTypeId: pendingAdd.deviceTypeId ?? null,
				deviceType: pendingAdd.deviceType ?? '',
				billingType: pendingAdd.billingType
			};
		}
		const edit = this._pendingEdits[lineId];
		const line = this._serverLines.find(l => l.Id === lineId);
		if (!edit && !line) return null;
		const deviceTypeId = edit?.deviceTypeId
			?? line?.Product2Id?.value
			?? line?.Product2?.Id
			?? null;
		return {
			deviceTypeId,
			deviceType: edit?.deviceType
				?? line?.DeviceType__c?.value
				?? line?.Product2?.ProductCode?.value
				?? this._productCodeByProduct2Id[deviceTypeId]
				?? '',
			billingType: edit?.billingType ?? line?.BillingType__c?.value
		};
	}

	/**
	 * @description Device Type Product2 Id for an existing or pending Instrument line.
	 * @param {string} lineId Line or temp Id
	 * @return {string|null}
	 */
	_instrumentDeviceTypeIdForLine(lineId) {
		const pendingAdd = this._pendingAdds.find(a => a._tempId === lineId);
		if (pendingAdd?.deviceTypeId) return pendingAdd.deviceTypeId;
		const edit = this._pendingEdits[lineId];
		if (edit?.deviceTypeId) return edit.deviceTypeId;
		const line = this._serverLines.find(l => l.Id === lineId);
		return line?.Product2Id?.value ?? line?.Product2?.Id ?? null;
	}

	/**
	 * @description Internal helper: Labor Instrument Node.
	 */
	_laborInstrumentNode(line) {
		return line?.Instrument__r ?? null;
	}

	/**
	 * @description Internal helper: On Labor Product Selected.
	 */
	_onLaborProductSelected(product2Id) {
		if (!product2Id) return;
		const nextBase = { ...this._baseServiceCodeByProduct2Id };
		delete nextBase[product2Id];
		this._baseServiceCodeByProduct2Id = nextBase;
		this._laborProductLookupId = product2Id;
	}

	/**
	 * @description Internal helper: Format Labor Product Label.
	 */
	_formatLaborProductLabel(productCode, name, id) {
		if (productCode && name) return `${productCode} — ${name}`;
		return productCode || name || id || '';
	}

	/**
	 * @description Internal helper: Format Repair Code Option Label.
	 */
	_formatRepairCodeOptionLabel(productCode, name, id) {
		if (productCode && name) return `${productCode} — ${name}`;
		return productCode || name || id;
	}

	/**
	 * @description Internal helper: Resolve Labor Product2Id.
	 */
	_resolveLaborProduct2Id(line, edit) {
		if (edit?.product2Id) return edit.product2Id;
		const partCode = (edit?.laborPartProductCode ?? line.ProductCode__c?.value ?? '').trim();
		if (partCode && this._product2IdByPartProductCode[partCode]) {
			return this._product2IdByPartProductCode[partCode];
		}
		return line.Instrument__c?.value ?? line.Instrument__r?.Id ?? null;
	}

	/**
	 * @description Internal helper: Repair Code Options For Product.
	 */
	_repairCodeOptionsForProduct(product2Id) {
		if (!product2Id) return [];
		return this._repairCodeOptionsByProduct2Id[product2Id] ?? [];
	}

	/**
	 * @description Internal helper: Base Service Code For Product.
	 */
	_baseServiceCodeForProduct(product2Id) {
		if (!product2Id) return '';
		if (Object.prototype.hasOwnProperty.call(this._baseServiceCodeByProduct2Id, product2Id)) {
			return this._baseServiceCodeByProduct2Id[product2Id];
		}
		return undefined;
	}

	/**
	 * @description Starts GraphQL @wire load of Service Codes for a Device Type.
	 * @param {string} product2Id Device Type Product2 Id
	 */
	async _loadRepairCodesForProduct(product2Id) {
		if (!product2Id) return;
		const base = this._baseServiceCodeByProduct2Id[product2Id];
		const loadedForBase = this._loadedServiceCodesForBase(base);
		this._repairCodeLoadingByProduct2Id = { ...this._repairCodeLoadingByProduct2Id, [product2Id]: true };
		this.repairCodeUiVersion += 1;
		this._pbeQueryProduct2Id = product2Id;
		this._serviceCodeQueryProduct2Id = product2Id;
		this._loadProductMeta(product2Id);
		if (base === '') {
			this._setRepairCodesForProduct(product2Id, '', []);
		} else if (loadedForBase) {
			this._setRepairCodesForProduct(product2Id, base, loadedForBase);
		}
	}

	/**
	 * @description Stores the Service Codes for a Device Type and for any other queued Device Type
	 *              with the same Base Service Code, then starts the next queued Device Type.
	 */
	_setRepairCodesForProduct(product2Id, baseServiceCode, options) {
		if (!product2Id) return;
		const base = baseServiceCode ?? '';
		const nextBase = { ...this._baseServiceCodeByProduct2Id, [product2Id]: base };
		const nextOptions = { ...this._repairCodeOptionsByProduct2Id, [product2Id]: options };
		const nextLoading = { ...this._repairCodeLoadingByProduct2Id, [product2Id]: false };
		if (base) {
			Object.keys(nextLoading).forEach(id => {
				if (nextLoading[id] && nextBase[id] === base) {
					nextOptions[id] = options;
					nextLoading[id] = false;
				}
			});
		}
		this._baseServiceCodeByProduct2Id = nextBase;
		this._repairCodeOptionsByProduct2Id = nextOptions;
		this._repairCodeLoadingByProduct2Id = nextLoading;
		this.repairCodeUiVersion += 1;
		this._loadNextQueuedServiceCodes();
	}

	/**
	 * @description Internal helper: Repair Code Combobox Placeholder For Product.
	 */
	_repairCodeComboboxPlaceholderForProduct(product2Id) {
		if (!product2Id) return 'Select an instrument first';
		if (this._repairCodeLoadingByProduct2Id[product2Id]) return 'Loading service codes…';
		if (!Object.prototype.hasOwnProperty.call(this._repairCodeOptionsByProduct2Id, product2Id)) {
			return 'Loading service codes…';
		}
		const prefix = this._baseServiceCodeForProduct(product2Id);
		if (prefix === undefined) return 'Loading service codes…';
		if (!prefix) return 'This product has no Base Service Code';
		const opts = this._repairCodeOptionsForProduct(product2Id);
		if (!opts.length) return `No service codes found for base code ${prefix}`;
		return 'Select a service code…';
	}

	/**
	 * @description Internal helper: Repair Code Status Message For Product.
	 */
	_repairCodeStatusMessageForProduct(product2Id) {
		if (!product2Id) return '';
		if (this._repairCodeLoadingByProduct2Id[product2Id]) return '';
		if ((this._repairCodeOptionsForProduct(product2Id) ?? []).length) return '';
		const placeholder = this._repairCodeComboboxPlaceholderForProduct(product2Id);
		if (placeholder === 'Select a service code…' || placeholder === 'Loading service codes…') return '';
		return placeholder;
	}

	/**
	 * @description Internal helper: Repair Code Combobox Ui For Product.
	 */
	_repairCodeComboboxUiForProduct(product2Id) {
		const options = this._repairCodeOptionsForProduct(product2Id);
		const loading = !!(product2Id && this._repairCodeLoadingByProduct2Id[product2Id]);
		return {
			repairCodeLoading: loading,
			repairCodeOptions: options,
			repairCodeComboboxPlaceholder: this._repairCodeComboboxPlaceholderForProduct(product2Id),
			showRepairCodeCombobox: !!(product2Id && !loading && options.length),
			repairCodeStatusMessage: this._repairCodeStatusMessageForProduct(product2Id)
		};
	}

	/**
	 * @description Internal helper: Ensure Repair Codes For Product.
	 */
	_ensureRepairCodesForProduct(product2Id) {
		if (!product2Id) return;
		if (Object.prototype.hasOwnProperty.call(this._repairCodeOptionsByProduct2Id, product2Id)) return;
		this._loadRepairCodesForProduct(product2Id);
	}

	/**
	 * @description Internal helper: Labor Product Label For Id.
	 */
	_laborProductLabelForId(product2Id) {
		if (!product2Id) return '';
		return this._laborProductLabelById[product2Id] ?? '';
	}

	/**
	 * @description Internal helper: Labor Product2Id For Line.
	 */
	_laborProduct2IdForLine(lineId) {
		const pendingAdd = this._pendingAdds.find((a) => a._tempId === lineId);
		if (pendingAdd?.product2Id) return pendingAdd.product2Id;
		const edit = this._pendingEdits[lineId];
		if (edit?.product2Id) return edit.product2Id;
		const line = this._serverLines.find((l) => l.Id === lineId);
		if (!line) return null;
		return this._resolveLaborProduct2Id(line, edit);
	}

	/**
	 * @description Internal helper: Ensure Product2Id For Part Code.
	 */
	async _ensureProduct2IdForPartCode(partCode) {
		const code = (partCode ?? '').trim();
		if (!code || this._product2IdByPartProductCode[code]) return;

		try {
			const result = await graphql(this, {
				query: PART_PRODUCT_BY_CODE_QUERY,
				variables: { productCode: code }
			});
			const node = result?.data?.uiapi?.query?.Product2?.edges?.[0]?.node;
			if (!node?.Id) return;

			const product2Id = node.Id;
			const productCode = node.ProductCode?.value ?? code;
			const name = node.Name?.value ?? '';
			const description = node.Description?.value ?? '';
			this._product2IdByPartProductCode = {
				...this._product2IdByPartProductCode,
				[code]: product2Id
			};
			this._cacheLaborPartDetails(product2Id, productCode, description);
			this.repairCodeUiVersion += 1;
		} catch (e) {
			/* lookup is best-effort for edit picker rehydration */
		}
	}

	/**
	 * @description Internal helper: Seed Labor Product Label Cache.
	 */
	_seedLaborProductLabelCache(lines) {
		const nextLabel = { ...this._laborProductLabelById };
		const nextDescription = { ...this._laborPartDescriptionById };
		const nextCode = { ...this._laborPartProductCodeById };
		let labelChanged = false;
		let descriptionChanged = false;
		let codeChanged = false;
		for (const l of lines) {
			if (l.LineType__c?.value !== 'Labor') continue;
			const instrument = this._laborInstrumentNode(l);
			const productCode = (l.ProductCode__c?.value ?? instrument?.ProductCode?.value ?? '').trim();
			const name = instrument?.Name?.value ?? '';
			const description = (l.ProductDescription__c?.value ?? instrument?.Description?.value ?? '').trim();
			const product2Id = l.Instrument__c?.value ?? instrument?.Id;
			const label = this._formatLaborProductLabel(productCode, name, product2Id || productCode);
			if (product2Id && label && nextLabel[product2Id] !== label) {
				nextLabel[product2Id] = label;
				labelChanged = true;
			}
			if (product2Id && nextDescription[product2Id] !== description) {
				nextDescription[product2Id] = description;
				descriptionChanged = true;
			}
			if (product2Id && productCode && nextCode[product2Id] !== productCode) {
				nextCode[product2Id] = productCode;
				codeChanged = true;
			}
			if (productCode) {
				this._ensureProduct2IdForPartCode(productCode);
			}
		}
		if (labelChanged) this._laborProductLabelById = nextLabel;
		if (descriptionChanged) this._laborPartDescriptionById = nextDescription;
		if (codeChanged) this._laborPartProductCodeById = nextCode;
	}

	/**
	 * @description Internal helper: Seed Labor Repair Code Cache.
	 */
	_seedLaborRepairCodeCache(lines) {
		for (const l of lines) {
			if (l.LineType__c?.value !== 'Labor') continue;
			const product2Id = this._resolveLaborProduct2Id(l, null);
			if (product2Id) {
				this._ensureRepairCodesForProduct(product2Id);
			}
		}
	}

	/**
	 * @description Internal helper: Seed Repair Code Cache.
	 */
	_seedRepairCodeCache(lines) {
		const nextName = { ...this._repairCodeNameById };
		const nextCode = { ...this._repairCodeProductCodeById };
		const nextDesc = { ...this._repairCodeDescriptionById };
		let changed = false;
		for (const l of lines) {
			const id = l.RepairCode__c?.value;
			if (!id) continue;
			const name = l.RepairCode__r?.Name?.value;
			const productCode = l.RepairCode__r?.ProductCode?.value;
			const description = l.RepairCode__r?.Description?.value;
			if (name && nextName[id] !== name) { nextName[id] = name; changed = true; }
			if (productCode != null && nextCode[id] !== productCode) { nextCode[id] = productCode; changed = true; }
			if (description != null && nextDesc[id] !== description) { nextDesc[id] = description; changed = true; }
		}
		if (changed) {
			this._repairCodeNameById = nextName;
			this._repairCodeProductCodeById = nextCode;
			this._repairCodeDescriptionById = nextDesc;
		}
	}

	/**
	 * @description Internal helper: Cache Repair Code Details.
	 */
	_cacheRepairCodeDetails(id, { name, productCode, description }) {
		if (!id) return;
		if (name) {
			this._repairCodeNameById = { ...this._repairCodeNameById, [id]: name };
		}
		if (productCode != null) {
			this._repairCodeProductCodeById = { ...this._repairCodeProductCodeById, [id]: productCode };
		}
		if (description != null) {
			this._repairCodeDescriptionById = { ...this._repairCodeDescriptionById, [id]: description };
		}
	}

	/**
	 * @description Internal helper: Resolve Product Code For Repair Code.
	 */
	_resolveProductCodeForRepairCode(repairCodeId) {
		if (!repairCodeId) return null;
		return this._repairCodeProductCodeById[repairCodeId] ?? null;
	}

	/**
	 * @description Internal helper: Resolve Product Description For Repair Code.
	 */
	_resolveProductDescriptionForRepairCode(repairCodeId) {
		if (!repairCodeId) return null;
		return this._repairCodeDescriptionById[repairCodeId] ?? null;
	}

	/**
	 * @description Internal helper: Sync Repair Code Details For Product.
	 */
	_syncRepairCodeDetailsForProduct(repairCodeId, productCode, description) {
		void description;
		this._pendingAdds = this._pendingAdds.map(a => {
			if (a._schema === 'labor' && a.repairCodeId === repairCodeId) {
				return { ...a, productCode: productCode ?? a.productCode ?? '' };
			}
			if (a._schema === 'instrument' && a.serviceCodeId === repairCodeId) {
				return {
					...a,
					repairLevel: this._repairLevelFromServiceCodeId(repairCodeId) || a.repairLevel
				};
			}
			return a;
		});
		if (this.addFormState?.serviceCodeId === repairCodeId) {
			this.addFormState = {
				...this.addFormState,
				repairLevel: this._repairLevelFromServiceCodeId(repairCodeId)
					|| this.addFormState.repairLevel
			};
		}
		const edits = { ...this._pendingEdits };
		let changed = false;
		for (const [id, edit] of Object.entries(edits)) {
			if (edit._schema === 'labor' && edit.repairCodeId === repairCodeId) {
				edits[id] = {
					...edit,
					productCode: productCode ?? edit.productCode ?? ''
				};
				changed = true;
			} else if (edit._schema === 'instrument' && edit.serviceCodeId === repairCodeId) {
				edits[id] = {
					...edit,
					repairLevel: this._repairLevelFromServiceCodeId(repairCodeId) || edit.repairLevel
				};
				changed = true;
			}
		}
		if (changed) this._pendingEdits = edits;
		if (this.addFormState.repairCodeId === repairCodeId) {
			this.addFormState = {
				...this.addFormState,
				productCode: productCode ?? this.addFormState.productCode ?? ''
			};
		}
	}

	/**
	 * @description Internal helper: Cache Labor Part Details.
	 */
	_cacheLaborPartDetails(product2Id, productCode, description) {
		if (!product2Id) return;
		if (productCode != null && productCode !== '') {
			const code = productCode.trim();
			this._laborPartProductCodeById = {
				...this._laborPartProductCodeById,
				[product2Id]: code
			};
			this._product2IdByPartProductCode = {
				...this._product2IdByPartProductCode,
				[code]: product2Id
			};
		}
		if (description != null) {
			this._laborPartDescriptionById = {
				...this._laborPartDescriptionById,
				[product2Id]: description
			};
		}
	}

	/**
	 * @description Internal helper: Sync Labor Product Details.
	 */
	_syncLaborProductDetails(product2Id, productCode, description) {
		if (!product2Id) return;
		const nextCode = (productCode ?? '').trim();
		const nextDescription = description ?? '';
		this._pendingAdds = this._pendingAdds.map(a => (
			a._schema === 'labor' && a.product2Id === product2Id
				? {
					...a,
					laborPartProductCode: nextCode,
					productDescription: nextDescription
				}
				: a
		));
		const edits = { ...this._pendingEdits };
		let changed = false;
		for (const [id, edit] of Object.entries(edits)) {
			if (edit._schema === 'labor' && edit.product2Id === product2Id) {
				edits[id] = {
					...edit,
					laborPartProductCode: nextCode,
					productDescription: nextDescription
				};
				changed = true;
			}
		}
		if (changed) this._pendingEdits = edits;
		if (this.addFormState.product2Id === product2Id) {
			this.addFormState = {
				...this.addFormState,
				laborPartProductCode: nextCode,
				productDescription: nextDescription
			};
		}
	}

	/**
	 * @description Internal helper: Resolve Labor Product Code.
	 */
	_resolveLaborProductCode(repairCodeId, productCode) {
		return productCode ?? this._resolveProductCodeForRepairCode(repairCodeId) ?? '';
	}

	/**
	 * @description Internal helper: Resolve Labor Product Description.
	 */
	_resolveLaborProductDescription(product2Id, productDescription) {
		if (productDescription != null && productDescription !== '') {
			return productDescription;
		}
		return this._laborPartDescriptionById[product2Id] ?? '';
	}

	/**
	 * @description Internal helper: Seed Returnable Cache From Parts.
	 */
	_seedReturnableCacheFromParts(parts) {
		const next = { ...this._isReturnableByProductItemId };
		let changed = false;
		for (const p of parts) {
			const productItemId = p.ProductItemId?.value;
			const isReturnable = p.Product2?.IsReturnable__c?.value;
			if (productItemId && isReturnable !== undefined && isReturnable !== null && next[productItemId] !== isReturnable) {
				next[productItemId] = isReturnable;
				changed = true;
			}
		}
		if (changed) this._isReturnableByProductItemId = next;
	}

	/**
	 * @description Internal helper: Seed Product Item Name Cache From Parts.
	 */
	_seedProductItemNameCacheFromParts(parts) {
		const next = { ...this._productItemNameByProductItemId };
		let changed = false;
		for (const p of parts) {
			const productItemId = p.ProductItemId?.value;
			const name = p.ProductItem?.ProductName?.value ?? p.Product2?.Name?.value;
			if (productItemId && name && next[productItemId] !== name) {
				next[productItemId] = name;
				changed = true;
			}
		}
		if (changed) this._productItemNameByProductItemId = next;
	}

	/**
	 * @description Internal helper: Seed Product Item Name Cache From Woli Lines.
	 */
	_seedProductItemNameCacheFromWoliLines(lines) {
		for (const l of lines ?? []) {
			const productItemId = l.ProductItem__c?.value;
			if (productItemId && !this._productItemNameByProductItemId[productItemId]) {
				this._productItemLookupId = productItemId;
				break;
			}
		}
		this._seedProduct2CacheFromWoliLines(lines);
	}

	/**
	 * @description Seeds Product2 detail lookups for Customer Stock WOLI lines.
	 */
	_seedProduct2CacheFromWoliLines(lines) {
		for (const l of lines ?? []) {
			const product2Id = l.Product__c?.value;
			if (
				product2Id
				&& (
					!this._productNameByProduct2Id[product2Id]
					|| this._productCodeByProduct2Id[product2Id] == null
				)
			) {
				this._product2LookupId = product2Id;
				break;
			}
		}
	}

	/**
	 * @description Internal helper: Apply Local Create.
	 */
	_applyLocalCreate(id, add) {
		if (add._entity === 'Expense') this._applyExpenseCreate(id, add);
		else if (add._entity === 'ProductConsumed') this._applyPartsConsumedCreate(id, add);
		else if (add._entity === 'ProductRequired') this._applyProductRequiredCreate(id, add);
	}

	/**
	 * @description Internal helper: Apply Local Update.
	 */
	_applyLocalUpdate(id, edit) {
		if (edit._entity === 'Expense') this._applyExpenseUpdate(id, edit);
		else if (edit._entity === 'ProductConsumed') this._applyPartsConsumedUpdate(id, edit);
		else if (edit._entity === 'ProductRequired') this._applyProductRequiredUpdate(id, edit);
	}

	/**
	 * @description Internal helper: Build Server Expense.
	 */
	_buildServerExpense(id, data) {
		return {
			Id: id,
			ExpenseType: { value: data.expenseType ?? '' },
			Description: { value: data.description ?? '' },
			Quantity: { value: data.quantity },
			UnitPrice: { value: data.unitPrice },
			TotalPrice: { value: data.totalPrice },
			Amount: { value: data.totalPrice }
		};
	}

	/**
	 * @description Internal helper: Apply Expense Create.
	 */
	_applyExpenseCreate(id, add) {
		this._upsertLocalExpense(this._buildServerExpense(id, {
			expenseType: add.expenseType,
			description: add.description,
			quantity: Number(add.quantity) || 0,
			unitPrice: Number(add.unitPrice) || 0,
			totalPrice: this._computeTotalPrice(add.unitPrice, add.quantity)
		}));
	}

	/**
	 * @description Internal helper: Apply Expense Update.
	 */
	_applyExpenseUpdate(id, edit) {
		this._upsertLocalExpense(this._buildServerExpense(id, {
			expenseType: edit.expenseType,
			description: edit.description,
			quantity: Number(edit.quantity) || 0,
			unitPrice: Number(edit.unitPrice) || 0,
			totalPrice: this._computeTotalPrice(edit.unitPrice, edit.quantity)
		}));
	}

	/**
	 * @description Internal helper: Apply Expense Delete.
	 */
	_applyExpenseDelete(id) {
		this._serverExpensesFromGraphql = this._serverExpensesFromGraphql.filter(e => e.Id !== id);
		this._serverExpensesFromRelatedList = this._serverExpensesFromRelatedList.filter(e => e.Id !== id);
		this._rebuildServerExpenses();
	}

	/**
	 * @description Internal helper: Upsert Local Expense.
	 */
	_upsertLocalExpense(expense) {
		this._serverExpensesFromRelatedList = [
			...this._serverExpensesFromRelatedList.filter(e => e.Id !== expense.Id),
			expense
		];
		this._rebuildServerExpenses();
	}

	/**
	 * @description Internal helper: Build Server Part.
	 */
	_buildServerPart(id, data) {
		const productItemId = data.productItemId ?? null;
		const product2Id = data.product2Id ?? this._product2IdByProductItemId[productItemId] ?? null;
		const productName = this._productItemNameByProductItemId[productItemId] ?? null;
		return {
			Id: id,
			QuantityConsumed: { value: data.quantityConsumed },
			Description: { value: data.description ?? '' },
			ProductItemId: { value: productItemId },
			Product2Id: { value: product2Id },
			Returnable__c: { value: data.returnable ?? null },
			ServiceResource__c: { value: data.assignedResourceId ?? null },
			WorkOrderLineItemId: { value: data.workOrderLineItemId ?? null },
			...(data.partsSource != null && data.workOrderLineItemId
				? { WorkOrderLineItem: { PartsSource__c: { value: data.partsSource } } }
				: {}),
			...(productName ? { ProductItem: { ProductName: { value: productName } } } : {})
		};
	}

	/**
	 * @description Internal helper: Apply Parts Consumed Create.
	 */
	_applyPartsConsumedCreate(id, add) {
		this._upsertLocalPart(this._buildServerPart(id, add));
	}

	/**
	 * @description Internal helper: Apply Parts Consumed Update.
	 */
	_applyPartsConsumedUpdate(id, edit) {
		this._upsertLocalPart(this._buildServerPart(id, edit));
	}

	/**
	 * @description Internal helper: Apply Parts Consumed Delete.
	 */
	_applyPartsConsumedDelete(id) {
		this._serverPartsFromGraphql = this._serverPartsFromGraphql.filter(p => p.Id !== id);
		this._serverPartsFromRelatedList = this._serverPartsFromRelatedList.filter(p => p.Id !== id);
		this._rebuildServerPartsConsumed();
	}

	/**
	 * @description Internal helper: Upsert Local Part.
	 */
	_upsertLocalPart(part) {
		this._serverPartsFromGraphql = [
			...this._serverPartsFromGraphql.filter(p => p.Id !== part.Id),
			part
		];
		this._rebuildServerPartsConsumed();
	}

	/**
	 * @description Internal helper: Build Server Required.
	 */
	_buildServerRequired(id, data) {
		return {
			Id: id,
			Product2Id: { value: data.product2Id },
			QuantityRequired: { value: data.quantityRequired },
			Returnable__c: { value: data.returnable ?? '' }
		};
	}

	/**
	 * @description Internal helper: Apply Product Required Create.
	 */
	_applyProductRequiredCreate(id, add) {
		this._upsertLocalRequired(this._buildServerRequired(id, add));
	}

	/**
	 * @description Internal helper: Apply Product Required Update.
	 */
	_applyProductRequiredUpdate(id, edit) {
		this._upsertLocalRequired(this._buildServerRequired(id, edit));
	}

	/**
	 * @description Internal helper: Apply Product Required Delete.
	 */
	_applyProductRequiredDelete(id) {
		this._serverRequiredFromGraphql = this._serverRequiredFromGraphql.filter(p => p.Id !== id);
		this._serverRequiredFromRelatedList = this._serverRequiredFromRelatedList.filter(p => p.Id !== id);
		this._rebuildServerProductsRequired();
	}

	/**
	 * @description Internal helper: Upsert Local Required.
	 */
	_upsertLocalRequired(required) {
		this._serverRequiredFromRelatedList = [
			...this._serverRequiredFromRelatedList.filter(p => p.Id !== required.Id),
			required
		];
		this._rebuildServerProductsRequired();
	}

	/**
	 * @description Internal helper: First Save Error Message.
	 */
	_firstSaveErrorMessage(failedEdits, failedAdds) {
		for (const id of Object.keys(failedEdits)) {
			const msg = this.editErrors[id];
			if (msg) return msg;
		}
		for (const a of failedAdds) {
			const msg = this.editErrors[a._tempId];
			if (msg) return msg;
		}
		return null;
	}

	/**
	 * @description Internal helper: Error Message.
	 */
	_errorMessage(err) {
		return this._ldsErrorMessage(err) || this._serializeError(err) || 'Save failed.';
	}

	/**
	 * @description Internal helper: Serialize Error.
	 */
	_serializeError(err) {
		if (!err) return null;
		try {
			const payload = err.body ?? err;
			const text = typeof payload === 'string' ? payload : JSON.stringify(payload);
			return text && text !== '{}' ? text : null;
		} catch (e) {
			return err.message ?? null;
		}
	}

	/**
	 * @description Internal helper: Lds Error Message.
	 */
	_ldsErrorMessage(err) {
		if (!err) return null;
		let body = err.body;
		if (typeof body === 'string') {
			try { body = JSON.parse(body); } catch (e) { return body; }
		}
		if (body?.errorMessage) return body.errorMessage;
		if (body?.message) return body.message;
		const pageErrors = body?.pageErrors;
		if (Array.isArray(pageErrors) && pageErrors.length) {
			return pageErrors.map(e => e.message).filter(Boolean).join(' ');
		}
		const fieldErrors = body?.fieldErrors;
		if (fieldErrors && typeof fieldErrors === 'object') {
			const msgs = Object.values(fieldErrors).flat().map(e => e?.message).filter(Boolean);
			if (msgs.length) return msgs.join(' ');
		}
		return err.message ?? null;
	}

	/**
	 * @description Internal helper: Fmt Parts Meta.
	 */
	_fmtPartsMeta(qty, desc, returnableLabel, partsSource) {
		const parts = [`Qty ${qty}`];
		const sourceLabel = this._partsSourceLabel(partsSource);
		if (sourceLabel) parts.push(sourceLabel);
		if (returnableLabel) parts.push(`Returnable: ${returnableLabel}`);
		if (desc) parts.push(desc);
		return parts.join(' · ');
	}

	/**
	 * @description Label for a PartsSource__c API value.
	 */
	_partsSourceLabel(value) {
		if (!value) return '';
		return this.partsSourceOptions.find(option => option.value === value)?.label ?? value;
	}

	/**
	 * @description Internal helper: Fmt Parts Woli Meta.
	 */
	_fmtPartsWoliMeta(qty, desc, usagesException, billingType) {
		const parts = [`Unit Qty ${qty ?? ''}`];
		if (usagesException) parts.push("Usage's Exception");
		const billingTypeLabel = this._fmtBillingType(billingType);
		if (billingTypeLabel) parts.push(billingTypeLabel);
		if (desc) parts.push(desc);
		return parts.join(' · ');
	}

	/**
	 * @description Internal helper: Fmt Required Meta.
	 */
	_fmtRequiredMeta(qty, returnable) {
		const parts = [`Qty ${qty}`];
		if (returnable) parts.push(returnable);
		return parts.join(' · ');
	}

	/**
	 * @description Internal helper: Fmt Expense Meta.
	 */
	_fmtExpenseMeta(description, quantity, unitPrice, totalPrice) {
		const parts = [];
		if (description) parts.push(description);
		parts.push(`${quantity} × $${this._fmtMoney(unitPrice)} = $${totalPrice}`);
		return parts.join(' · ') || 'Expense';
	}

	/**
	 * @description True when Repair Code product name indicates Beyond Repair.
	 */
	_isBeyondRepairRepairCode(repairCodeId, knownName) {
		if (!repairCodeId && !knownName) return false;
		const name = knownName
			|| this._productMetaById[repairCodeId]?.name
			|| this._repairCodeNameById[repairCodeId]
			|| '';
		return BEYOND_REPAIR_PATTERN.test(name);
	}

	/**
	 * @description Resolves Service Code from the selected Instrument product only.
	 */
	_resolveServiceCode(instrumentId, line) {
		return line?.Instrument__r?.ServiceCode__c?.value
			|| this._productMetaById[instrumentId]?.serviceCode
			|| '';
	}

	/**
	 * @description Loads Product2 Name / Service Code via existing getRecord wires.
	 */
	_loadProductMeta(product2Id) {
		if (!product2Id) return;
		this._product2LookupId = product2Id;
		this._repairCodeLookupId = product2Id;
	}

	/**
	 * @description Seeds Instrument/Repair Code Service Code + name cache from GraphQL lines.
	 */
	_seedInstrumentProductMetaCache(lines) {
		for (const line of lines ?? []) {
			const instrumentId = line.Instrument__c?.value;
			const instrumentName = line.Instrument__r?.Name?.value;
			const instrumentServiceCode = line.Instrument__r?.ServiceCode__c?.value;
			if (instrumentId) {
				this._cacheProductMeta(instrumentId, {
					name: instrumentName,
					serviceCode: instrumentServiceCode
				});
			}
			const repairCodeId = line.RepairCode__c?.value;
			const repairName = line.RepairCode__r?.Name?.value;
			const repairServiceCode = line.RepairCode__r?.ServiceCode__c?.value;
			if (repairCodeId) {
				this._cacheProductMeta(repairCodeId, {
					name: repairName,
					serviceCode: repairServiceCode
				});
			}
			const deviceTypeId = line.Product2Id?.value ?? line.Product2?.Id;
			const deviceTypeCode = line.Product2?.ProductCode?.value;
			const deviceTypeName = line.Product2?.Name?.value;
			if (deviceTypeId) {
				this._cacheProductMeta(deviceTypeId, { name: deviceTypeName });
				if (deviceTypeCode) {
					this._productCodeByProduct2Id = {
						...this._productCodeByProduct2Id,
						[deviceTypeId]: deviceTypeCode
					};
				}
				if (deviceTypeName) {
					this._productNameByProduct2Id = {
						...this._productNameByProduct2Id,
						[deviceTypeId]: deviceTypeName
					};
				}
				const baseServiceCode = (line.Product2?.BaseServiceCode__c?.value ?? '').trim();
				if (baseServiceCode) {
					this._baseServiceCodeByProduct2Id = {
						...this._baseServiceCodeByProduct2Id,
						[deviceTypeId]: baseServiceCode
					};
				}
			}
		}
	}

	/**
	 * @description Caches Product2 service-code metadata for Instrument tab UI.
	 */
	_cacheProductMeta(product2Id, { name, serviceCode }) {
		if (!product2Id) return;
		const prev = this._productMetaById[product2Id] || {};
		const nextName = name ?? prev.name ?? '';
		const nextServiceCode = serviceCode ?? prev.serviceCode ?? '';
		if (prev.name === nextName && prev.serviceCode === nextServiceCode) return;
		this._productMetaById = {
			...this._productMetaById,
			[product2Id]: { name: nextName, serviceCode: nextServiceCode }
		};
		if (nextName) {
			this._productNameByProduct2Id = {
				...this._productNameByProduct2Id,
				[product2Id]: nextName
			};
			this._repairCodeNameById = {
				...this._repairCodeNameById,
				[product2Id]: nextName
			};
		}
		this.productMetaVersion += 1;
	}

	/**
	 * @description Internal helper: Fmt Travel Meta.
	 */
	_fmtTravelMeta(startDate, endDate) { return this._fmtDateRange(startDate, endDate); }
	/**
	 * @description Internal helper: Fmt Child Wo Labor Meta.
	 */
	_fmtChildWoLaborMeta(repairCode, productDescription, quantity) {
		return this._fmtChildWoTimeMeta('Labor', repairCode, productDescription, quantity);
	}

	/**
	 * @description Internal helper: Fmt Child Wo Time Meta.
	 */
	_fmtChildWoTimeMeta(lineType, repairCode, productDescription, quantity, startDate = '', endDate = '') {
		const parts = [];
		if (lineType) parts.push(lineType);
		if (repairCode) parts.push(repairCode);
		if (productDescription) parts.push(productDescription);
		if (quantity !== '' && quantity != null) parts.push(`Qty ${quantity}`);
		
		const range = this._fmtDateRange(startDate, endDate);
		if (range) parts.push(range);
		return parts.join(' · ');
	}

	/**
	 * @description Internal helper: Fmt Calibration Meta.
	 */
	_fmtCalibrationMeta(assetSerial) {
		return assetSerial ? `SN ${assetSerial}` : '';
	}

	/**
	 * @description Internal helper: Fmt Date Range.
	 */
	_fmtDateRange(startDate, endDate) {
		const s = this._fmtDateTime(startDate);
		const e = this._fmtDateTime(endDate);
		if (s && e) return `${s} → ${e}`;
		if (s) return s;
		if (e) return `→ ${e}`;
		return '';
	}

	/**
	 * @description Internal helper: Fmt Date Time.
	 */
	_fmtDateTime(iso) {
		if (!iso) return '';
		const d = new Date(iso);
		if (Number.isNaN(d.getTime())) return '';
		return d.toLocaleString(undefined, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
	}

	/**
	 * @description Internal helper: Fmt Money.
	 */
	_fmtMoney(n) {
		const num = Number(n);
		if (!Number.isFinite(num)) return '0.00';
		return num.toFixed(2);
	}

	/**
	 * @description Formats money when present; blank when null/undefined.
	 * @param {*} n Amount
	 * @return {string}
	 */
	_fmtOptionalMoney(n) {
		return n === null || n === undefined || n === '' ? '' : this._fmtMoney(n);
	}

	/**
	 * @description Internal helper: To Ms.
	 */
	_toMs(iso) {
		if (!iso) return null;
		const t = new Date(iso).getTime();
		return Number.isNaN(t) ? null : t;
	}

	/**
	 * @description GW-375 - Site visit work order that also receives every Mobile Device Picture.
	 * @return {string|null}
	 */
	_parentWorkOrderId() {
		return this._workOrder?.ParentWorkOrderId?.value
			|| this._accessWorkOrder?.ParentWorkOrderId?.value
			|| null;
	}

	/**
	 * @description GW-375 - Loads Mobile Device Pictures for the child work order and instrument lines.
	 */
	async _loadMobileDevicePictures() {
		if (!this.recordId) {
			return;
		}
		const recordIds = [];
		const workOrderId = this._apexId(this.recordId);
		if (workOrderId) {
			recordIds.push(workOrderId);
		}
		for (const line of this._serverLines) {
			if (!INSTRUMENT_TAB_LINE_TYPES.has(line.LineType__c?.value)) {
				continue;
			}
			const lineId = this._apexId(line.Id);
			if (lineId) {
				recordIds.push(lineId);
			}
		}
		if (!recordIds.length) {
			return;
		}
		const requestId = this._mobilePictureRequest + 1;
		this._mobilePictureRequest = requestId;
		try {
			const rows = await listMobileDevicePictures({ recordIdsCsv: recordIds.join(',') });
			if (this._mobilePictureRequest !== requestId) {
				return;
			}
			const byRecord = {};
			for (const row of rows || []) {
				if (!row?.linkedEntityId || !row.contentDocumentId) {
					continue;
				}
				const picture = {
					key: `${row.linkedEntityId}:${row.contentDocumentId}`,
					contentDocumentId: row.contentDocumentId,
					contentVersionId: row.contentVersionId,
					title: row.title || 'Mobile Device Picture',
					category: row.category || null,
					beforeAfter: row.beforeAfter || null,
					comment: row.comment || null,
					previewUrl: this._mobilePicturePreviewUrl(row.contentVersionId, row.contentDocumentId)
				};
				const recordKey = this._pictureRecordKey(row.linkedEntityId);
				if (!recordKey) {
					continue;
				}
				if (!byRecord[recordKey]) {
					byRecord[recordKey] = [];
				}
				byRecord[recordKey].push(picture);
			}
			Object.entries(this._mobilePicturesByRecordId).forEach(([recordKey, pictures]) => {
				const listed = new Set((byRecord[recordKey] || []).map(picture => picture.contentDocumentId));
				const notSynced = (pictures || []).filter(picture => picture.savedOnDevice && !listed.has(picture.contentDocumentId));
				if (notSynced.length) {
					byRecord[recordKey] = [...(byRecord[recordKey] || []), ...notSynced];
				}
			});
			this._mobilePicturesByRecordId = byRecord;
			this.mobilePictureVersion += 1;
		} catch (error) {
			if (this._mobilePictureRequest !== requestId) {
				return;
			}
			// eslint-disable-next-line no-console
			console.warn('woDebriefIMSchildWO listMobileDevicePictures failed', error);
		}
	}

	/**
	 * @description GW-375 - Picture fields used by the instrument line template.
	 * @param {string} lineId Salesforce or temporary line Id
	 * @param {Object[]} stagedPictures Pictures not yet saved
	 * @return {Object}
	 */
	_mobilePictureModel(lineId, stagedPictures) {
		void this.mobilePictureVersion;
		const saved = this._isSalesforceWoliId(lineId)
			? this._savedAndUnsavedPictures(lineId)
			: [];
		const pictures = [...saved, ...(stagedPictures || [])].map(picture => this._pictureView(picture));
		const count = pictures.length;
		return {
			mobilePictures: pictures,
			hasMobilePictures: count > 0,
			mobilePictureCount: count,
			mobilePictureCountLabel: this._pictureCountLabel(count),
			showMobilePictureCount: true
		};
	}

	/**
	 * @description GW-375 - Display label for a picture count.
	 * @param {number} count Picture count
	 * @return {string}
	 */
	_pictureCountLabel(count) {
		return count === 1 ? '1 picture' : `${count} pictures`;
	}

	/**
	 * @description GW-375 - Template row for a picture. Omits the image body.
	 * @param {Object} picture Stored picture
	 * @return {Object}
	 */
	_pictureView(picture) {
		const contentVersionId = picture?.contentVersionId;
		return {
			key: picture?.key || picture?.contentDocumentId || picture?.localId,
			contentDocumentId: picture?.contentDocumentId || null,
			contentVersionId: contentVersionId || null,
			localId: picture?.localId || null,
			title: picture?.title || 'Mobile Device Picture',
			detailLabel: [picture?.category, picture?.beforeAfter].filter(Boolean).join(' · '),
			comment: picture?.comment || '',
			previewUrl: picture?.previewUrl
				|| this._mobilePicturePreviewUrl(contentVersionId, picture?.contentDocumentId)
		};
	}

	/**
	 * @description GW-375 - Thumbnail address for a saved picture.
	 *              A rendition is an image response. The file download link is not, and the mobile app will not paint it.
	 * @param {string} contentVersionId ContentVersion Id
	 * @param {string} contentDocumentId ContentDocument Id
	 * @return {string}
	 */
	_mobilePicturePreviewUrl(contentVersionId, contentDocumentId) {
		if (!contentVersionId) {
			return '';
		}
		const content = contentDocumentId ? `&contentId=${contentDocumentId}` : '';
		return `/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=${contentVersionId}&operationContext=CHATTER${content}`;
	}

	/**
	 * @description GW-375 - Loads a saved picture as image bytes so the mobile preview can paint it.
	 * @param {string} contentVersionId ContentVersion Id
	 * @return {Promise<string>} Data url, or an empty string when there is no version
	 */
	_loadSavedPicturePreview(contentVersionId) {
		if (!contentVersionId) {
			return Promise.resolve('');
		}
		if (!this._pictureDataPromises[contentVersionId]) {
			this._pictureDataPromises[contentVersionId] = getMobileDevicePictureData({ contentVersionId })
				.then(base64 => {
					const dataUrl = `data:image/jpeg;base64,${base64}`;
					this._applyPictureDataUrl(contentVersionId, dataUrl);
					return dataUrl;
				})
				.catch(error => {
					delete this._pictureDataPromises[contentVersionId];
					throw error;
				});
		}
		return this._pictureDataPromises[contentVersionId];
	}

	/**
	 * @description GW-375 - Replaces a saved picture address with image bytes after the file link fails to paint.
	 * @param {Event} event Image error
	 */
	handlePicturePreviewError(event) {
		const versionId = event.currentTarget?.dataset?.versionId;
		if (!versionId || this._pictureDataPromises[versionId]) {
			return;
		}
		this._loadSavedPicturePreview(versionId).catch(error => {
			this._toast('Picture', this._errorMessage(error), 'error');
		});
	}

	/**
	 * @description GW-375 - Stores image bytes on the saved picture so the thumbnail and the preview use them.
	 * @param {string} contentVersionId ContentVersion Id
	 * @param {string} dataUrl Image data url
	 */
	_applyPictureDataUrl(contentVersionId, dataUrl) {
		if (!contentVersionId || !dataUrl) {
			return;
		}
		const next = {};
		let changed = false;
		Object.entries(this._mobilePicturesByRecordId).forEach(([recordId, pictures]) => {
			next[recordId] = (pictures || []).map(picture => {
				if (picture.contentVersionId === contentVersionId && picture.previewUrl !== dataUrl) {
					changed = true;
					return { ...picture, previewUrl: dataUrl };
				}
				return picture;
			});
		});
		if (changed) {
			this._mobilePicturesByRecordId = next;
			this.mobilePictureVersion += 1;
		}
	}

	/**
	 * @description GW-375 - Saved and staged pictures for one instrument line.
	 * @param {string} lineId Line Id
	 * @return {Object[]}
	 */
	_picturesForLine(lineId) {
		const saved = this._savedAndUnsavedPictures(lineId);
		const pending = this._pendingAdds.find(add => add._tempId === lineId);
		return [...saved, ...(pending?.mobilePictures || [])];
	}

	/**
	 * @description GW-375 - Finds a picture by the key rendered on its thumbnail.
	 * @param {string} scope tray, add, or line
	 * @param {string} lineId Line Id for a line-scope picture
	 * @param {string} key Thumbnail key
	 * @return {Object|undefined}
	 */
	_findMobilePicture(scope, lineId, key) {
		let pictures = [];
		if (scope === 'tray') {
			pictures = this._savedAndUnsavedPictures(this.recordId);
		} else if (scope === 'add') {
			pictures = this.addFormState?.mobilePictures || [];
		} else {
			pictures = this._picturesForLine(lineId);
		}
		return pictures.find(picture => (picture.key || picture.contentDocumentId || picture.localId) === key);
	}

	/**
	 * @description GW-375 - Reads the camera file and shrinks it before upload.
	 * @param {File} file Selected image
	 * @return {Promise<Object>}
	 */
	_fileToMobilePicture(file) {
		return this._compressImageFile(file).then(dataUrl => {
			_tempIdSeq += 1;
			const localId = `local_${_tempIdSeq}`;
			return {
				key: localId,
				localId,
				contentDocumentId: null,
				contentVersionId: null,
				title: 'Mobile Device Picture',
				previewUrl: dataUrl,
				base64Data: dataUrl,
				fileName: 'MobileDevicePicture.jpg'
			};
		});
	}

	/**
	 * @description GW-375 - Draws the photo to a smaller jpeg so the upload stays within Apex limits.
	 * @param {File} file Selected image
	 * @return {Promise<string>}
	 */
	_compressImageFile(file) {
		return new Promise((resolve, reject) => {
			const reader = new FileReader();
			reader.onerror = () => reject(new Error('The picture could not be read. Take it again.'));
			reader.onload = () => {
				this._compressImageDataUrl(reader.result).then(resolve, reject);
			};
			reader.readAsDataURL(file);
		});
	}

	/**
	 * @description Draws an image data url to a smaller jpeg so the upload stays within Apex limits.
	 * @param {string} source Image data url
	 * @return {Promise<string>}
	 */
	_compressImageDataUrl(source) {
		return new Promise((resolve, reject) => {
			const image = new Image();
			image.onerror = () => reject(new Error('The picture could not be read. Take it again.'));
			image.onload = () => {
				const maxEdge = 1600;
				const scale = Math.min(1, maxEdge / Math.max(image.width || 1, image.height || 1));
				const width = Math.max(1, Math.round((image.width || 1) * scale));
				const height = Math.max(1, Math.round((image.height || 1) * scale));
				const canvas = document.createElement('canvas');
				canvas.width = width;
				canvas.height = height;
				const context = canvas.getContext('2d');
				if (!context) {
					resolve(source);
					return;
				}
				context.drawImage(image, 0, 0, width, height);
				resolve(canvas.toDataURL('image/jpeg', 0.72));
			};
			image.src = source;
		});
	}

	/**
	 * @description GW-6340 - Turns a microscopic camera capture into a picture waiting for its details.
	 * @param {string} dataUrl PNG data url from the camera
	 * @return {Promise<Object>}
	 */
	_dataUrlToMicroscopePicture(dataUrl) {
		return this._compressImageDataUrl(dataUrl).then(compressed => {
			_tempIdSeq += 1;
			const localId = `local_${_tempIdSeq}`;
			return {
				key: localId,
				localId,
				contentDocumentId: null,
				contentVersionId: null,
				title: MICROSCOPE_PICTURE_TITLE,
				previewUrl: compressed,
				base64Data: compressed,
				fileName: 'MicroscopePicture.jpg'
			};
		});
	}

	/**
	 * @description GW-375 - Adds a saved picture to the record it was taken for.
	 * @param {string} recordId Child work order or instrument line Id
	 * @param {Object} saved Apex picture result
	 * @param {string} localPreviewUrl Image already on the device. Kept so the preview does not depend on the file link.
	 */
	_rememberMobilePicture(recordId, saved, localPreviewUrl) {
		if (!recordId || !saved?.contentDocumentId) {
			return;
		}
		const picture = {
			key: `${recordId}:${saved.contentDocumentId}`,
			contentDocumentId: saved.contentDocumentId,
			contentVersionId: saved.contentVersionId,
			title: saved.title || 'Mobile Device Picture',
			category: saved.category || null,
			beforeAfter: saved.beforeAfter || null,
			comment: saved.comment || null,
			previewUrl: localPreviewUrl || this._mobilePicturePreviewUrl(saved.contentVersionId, saved.contentDocumentId),
			savedOnDevice: true
		};
		const recordKey = this._pictureRecordKey(recordId);
		if (!recordKey) {
			return;
		}
		const current = this._mobilePicturesByRecordId[recordKey] || [];
		this._mobilePicturesByRecordId = {
			...this._mobilePicturesByRecordId,
			[recordKey]: [...current, picture]
		};
		this.mobilePictureVersion += 1;
		this._mobilePictureRequest += 1;
	}

	/**
	 * @description Saves the pictures taken on a line before Save All, right after the line itself is saved.
	 * @param {string} lineId Saved instrument line Id. Offline this is the draft line Id.
	 * @param {Object} source Staged line with mobilePictures
	 */
	async _saveStagedLinePictures(lineId, source) {
		const staged = (source?.mobilePictures || [])
			.filter(picture => picture?.base64Data && !picture.contentDocumentId);
		for (const picture of staged) {
			// eslint-disable-next-line no-await-in-loop
			await this._saveMobilePictureOrKeep(lineId, picture);
		}
	}

	/**
	 * @description Saves pictures that could not be saved earlier. Runs on Save All.
	 */
	async _retryUnsavedPictures() {
		const entries = Object.entries(this._unsavedPicturesByRecordId);
		this._unsavedPicturesByRecordId = {};
		for (const [, pictures] of entries) {
			for (const { recordId, picture } of pictures) {
				// eslint-disable-next-line no-await-in-loop
				await this._saveMobilePictureOrKeep(recordId, picture);
			}
		}
		this.mobilePictureVersion += 1;
	}

	/**
	 * @description Saves a Mobile Device Picture. When it cannot be saved, it stays on the record
	 *              and is saved again on the next Save All, so a picture is never lost.
	 * @param {string} recordId Work order or line Id
	 * @param {Object} picture Staged picture with base64Data
	 * @return {Promise<boolean>} True when saved
	 */
	async _saveMobilePictureOrKeep(recordId, picture) {
		try {
			const saved = await this._savePictureOnRecord(recordId, picture);
			this._rememberMobilePicture(recordId, saved, picture.previewUrl);
			return true;
		} catch (error) {
			this._keepUnsavedPicture(recordId, picture);
			this._toast(
				'Picture kept on the line',
				`${this._errorMessage(error)} It is saved again on Save All.`,
				'warning'
			);
			return false;
		}
	}

	/**
	 * @description Holds a picture that failed to save so it stays shown on its record.
	 * @param {string} recordId Work order or line Id
	 * @param {Object} picture Staged picture
	 */
	_keepUnsavedPicture(recordId, picture) {
		const recordKey = this._pictureRecordKey(recordId);
		if (!recordKey) {
			return;
		}
		const current = (this._unsavedPicturesByRecordId[recordKey] || [])
			.filter(item => item.picture.localId !== picture.localId);
		this._unsavedPicturesByRecordId = {
			...this._unsavedPicturesByRecordId,
			[recordKey]: [...current, { recordId, picture }]
		};
		this.mobilePictureVersion += 1;
	}

	/**
	 * @description Removes a picture that is waiting to be saved again.
	 * @param {string} localId Local picture Id
	 * @return {boolean} True when a picture was removed
	 */
	_dropUnsavedPicture(localId) {
		if (!localId) {
			return false;
		}
		let removed = false;
		const next = {};
		Object.entries(this._unsavedPicturesByRecordId).forEach(([recordKey, pictures]) => {
			const kept = pictures.filter(item => item.picture.localId !== localId);
			removed = removed || kept.length !== pictures.length;
			if (kept.length) {
				next[recordKey] = kept;
			}
		});
		this._unsavedPicturesByRecordId = next;
		return removed;
	}

	/**
	 * @description True when a picture is waiting to be saved again.
	 * @return {boolean}
	 */
	_hasUnsavedPictures() {
		return Object.keys(this._unsavedPicturesByRecordId).length > 0;
	}

	/**
	 * @description Saved pictures of a record followed by the ones waiting to be saved again.
	 * @param {string} recordId Work order or line Id
	 * @return {Object[]}
	 */
	_savedAndUnsavedPictures(recordId) {
		const recordKey = this._pictureRecordKey(recordId);
		return [
			...(this._mobilePicturesByRecordId[recordKey] || []),
			...(this._unsavedPicturesByRecordId[recordKey] || []).map(item => item.picture)
		];
	}

	/**
	 * @description Saves one Mobile Device Picture on a work order or line.
	 *              On the mobile app the file and its link are queued behind the line, so this works
	 *              offline and on a line that is not synced yet. Where the mobile file adapter is not
	 *              available, such as the desktop, the picture is saved through Apex.
	 * @param {string} recordId Work order or line Id
	 * @param {Object} picture Staged picture with base64Data
	 * @return {Promise<Object>} contentDocumentId, contentVersionId, and title
	 */
	async _savePictureOnRecord(recordId, picture) {
		const details = this._pictureDetailsJson(picture);
		const queued = await this._queuePictureFile(recordId, picture, {
			title: this._isMicroscopePicture(picture) ? MICROSCOPE_PICTURE_TITLE : MOBILE_DEVICE_PICTURE_TITLE,
			description: details
				? `${MOBILE_DEVICE_PICTURE_MARKER}${PICTURE_DETAILS_SEPARATOR}${details}`
				: MOBILE_DEVICE_PICTURE_MARKER
		});
		if (queued) {
			return {
				...queued,
				category: picture.category || null,
				beforeAfter: picture.beforeAfter || null,
				comment: picture.comment || null
			};
		}
		const primaryRecordId = this._apexId(recordId);
		if (!primaryRecordId) {
			throw new Error('Open the work order again, then take the picture.');
		}
		return saveMobileDevicePictureWithDetails({
			primaryRecordId,
			parentWorkOrderId: this._apexId(this._parentWorkOrderId()),
			base64Data: picture.base64Data,
			fileName: picture.fileName || 'MobileDevicePicture.jpg',
			pictureDetails: details
		});
	}

	/**
	 * @param {Object} picture Staged picture
	 * @return {string} Category, Before/After, comment, and the Microscope Picture title as JSON,
	 *                  or an empty string when none is set
	 */
	_pictureDetailsJson(picture) {
		const isMicroscope = this._isMicroscopePicture(picture);
		if (!picture?.category && !picture?.beforeAfter && !picture?.comment && !isMicroscope) {
			return '';
		}
		const details = {
			category: picture.category || null,
			beforeAfter: picture.beforeAfter || null,
			comment: picture.comment || null
		};
		if (isMicroscope) {
			details.title = MICROSCOPE_PICTURE_TITLE;
		}
		return JSON.stringify(details);
	}

	/**
	 * @param {Object} picture Staged picture
	 * @return {boolean} True when the picture was taken with the microscopic camera
	 */
	_isMicroscopePicture(picture) {
		return picture?.title === MICROSCOPE_PICTURE_TITLE;
	}

	/**
	 * @description Creates the file and its link with the mobile file adapter.
	 * @param {string} recordId Work order or line Id
	 * @param {Object} picture Staged picture with base64Data
	 * @param {{title: string, description: string}} details File title and description
	 * @return {Promise<Object|null>} Saved picture, or null when the adapter is not available here
	 */
	async _queuePictureFile(recordId, picture, { title, description }) {
		if (typeof createContentDocumentAndVersion !== 'function') {
			return null;
		}
		let created;
		try {
			created = await createContentDocumentAndVersion({
				title,
				description,
				fileData: this._pictureFile(picture)
			});
		} catch (error) {
			return null;
		}
		const contentDocumentId = created?.contentDocument?.id;
		if (!contentDocumentId) {
			return null;
		}
		await createRecord({
			apiName: CONTENT_DOCUMENT_LINK_OBJECT.objectApiName,
			fields: {
				LinkedEntityId: recordId,
				ContentDocumentId: contentDocumentId,
				ShareType: 'V'
			}
		});
		return {
			contentDocumentId,
			contentVersionId: created?.contentVersion?.id ?? null,
			title
		};
	}

	/**
	 * @description Turns a staged picture into the file the mobile file adapter uploads.
	 * @param {Object} picture Staged picture with a base64 data url
	 * @return {File}
	 */
	_pictureFile(picture) {
		const dataUrl = String(picture?.base64Data || '');
		const comma = dataUrl.indexOf(',');
		const header = comma >= 0 ? dataUrl.substring(0, comma) : '';
		const body = comma >= 0 ? dataUrl.substring(comma + 1) : dataUrl;
		const type = (header.match(/^data:([^;]+)/) || [])[1] || 'image/jpeg';
		const binary = atob(body);
		const bytes = new Uint8Array(binary.length);
		for (let i = 0; i < binary.length; i += 1) {
			bytes[i] = binary.charCodeAt(i);
		}
		return new File([bytes], picture?.fileName || 'Picture.jpg', { type });
	}

	/**
	 * @description GW-375 - Deletes a saved picture, or drops one that has not been saved yet.
	 * @param {string} scope tray, add, or line
	 * @param {string} lineId Line Id
	 * @param {string} key Thumbnail key
	 * @return {Promise<boolean>}
	 */
	async _deleteMobilePicture(scope, lineId, key) {
		const picture = this._findMobilePicture(scope, lineId, key);
		if (!picture) {
			return false;
		}
		const confirmed = await LightningConfirm.open({
			message: picture.contentDocumentId
				? 'Delete this Mobile Device Picture? It will be removed from this record and from the site visit work order.'
				: 'Remove this Mobile Device Picture?',
			variant: 'headerless',
			label: 'Delete picture'
		});
		if (!confirmed) {
			return false;
		}
		try {
			if (picture.contentDocumentId) {
				await deleteMobileDevicePicture({ contentDocumentId: picture.contentDocumentId });
				const next = {};
				Object.entries(this._mobilePicturesByRecordId).forEach(([recordId, pictures]) => {
					next[recordId] = pictures.filter(item => item.contentDocumentId !== picture.contentDocumentId);
				});
				this._mobilePicturesByRecordId = next;
				this.mobilePictureVersion += 1;
				this._mobilePictureRequest += 1;
			} else if (this._dropUnsavedPicture(picture.localId)) {
				this.mobilePictureVersion += 1;
			} else if (scope === 'add') {
				this.addFormState = {
					...this.addFormState,
					mobilePictures: (this.addFormState.mobilePictures || []).filter(
						item => item.localId !== picture.localId
					)
				};
				this.mobilePictureVersion += 1;
			} else {
				this._pendingAdds = this._pendingAdds.map(add => (
					add._tempId === lineId
						? {
							...add,
							mobilePictures: (add.mobilePictures || []).filter(
								item => item.localId !== picture.localId
							)
						}
						: add
				));
				this.mobilePictureVersion += 1;
			}
			return true;
		} catch (error) {
			this._toast('Picture was not deleted', this._errorMessage(error), 'error');
			return false;
		}
	}

	/**
	 * @description GW-312 - Completes the child work order. Lines missing a Service Code or a picture
	 *              block completion. Lines sent to the Repair Center need a confirmation first.
	 */
	async handleCompleteWorkOrder() {
		if (this.hasPendingChanges) {
			this._toast('Save first', 'Save All before completing the work order.', 'warning');
			return;
		}
		this._completingWorkOrder = true;
		try {
			const check = await getCompletionCheck({ workOrderId: this.recordId });
			const workOrderLabel = check?.workOrderNumber ? `Work Order ${check.workOrderNumber}` : 'The work order';
			if (check?.missingLines?.length) {
				await LightningAlert.open({
					label: 'Work order cannot be completed',
					message: `${workOrderLabel} cannot be completed.\n${check.missingLines.join('\n')}`,
					theme: 'error'
				});
				return;
			}
			if (check?.repairCenterLines?.length) {
				const confirmed = await LightningConfirm.open({
					label: 'Lines need a Return Order',
					message: 'These lines need to be sent to the Repair Center. Create a Return Order for them from '
						+ `Work Order Review - IMS Site Visit.\n${check.repairCenterLines.join('\n')}\n\n`
						+ 'Complete the work order?',
					theme: 'warning'
				});
				if (!confirmed) return;
			}
			await completeChildWorkOrder({ workOrderId: this.recordId });
			this._toast('Work order completed', `${workOrderLabel} is Completed.`, 'success');
			notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
			try { await refreshGraphQL(this.graphqlResult); } catch (e) { /* swallow */ }
		} catch (error) {
			this._toast('Work order was not completed', this._errorMessage(error), 'error');
		} finally {
			this._completingWorkOrder = false;
		}
	}

	/**
	 * @description Internal helper: Toast.
	 */
	_toast(title, message, variant) {
		this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
	}
}