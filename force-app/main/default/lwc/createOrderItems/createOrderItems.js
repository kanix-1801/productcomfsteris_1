import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getInitialContext from '@salesforce/apex/CreateReturnOrderController.getInitialContext';
import getAssetsForAccount from '@salesforce/apex/CreateReturnOrderController.getAssetsForAccount';
import getContactsForAccount from '@salesforce/apex/CreateReturnOrderController.getContactsForAccount';
import getShipToAddressesForAccount from '@salesforce/apex/CreateReturnOrderController.getShipToAddressesForAccount';
import getDepartmentsForAccount from '@salesforce/apex/CreateReturnOrderController.getDepartmentsForAccount';
import getProductsForReturnOrderLine from '@salesforce/apex/CreateReturnOrderController.getProductsForReturnOrderLine';
import getProductDetails from '@salesforce/apex/CreateReturnOrderController.getProductDetails';
import createAccountContact from '@salesforce/apex/CreateReturnOrderController.createAccountContact';

const ITEM_TYPE_SERIALIZED = 'serialized';
const ESTIMATE_REQUIRED_QUOTE_VALUE = 'Estimate Required';
const ESTIMATE_OPTION_PRE_APPROVED = 'Pre-Approved';
const MEDIA_ACCEPT =
    '.png,.jpg,.jpeg,.gif,.bmp,.webp,.heic,.mp4,.mov,.avi,.wmv,.mkv,.webm,.m4v,.3gp,image/*,video/*';

const PRIORITY_OPTIONS = [
    { label: 'Low', value: 'Low' },
    { label: 'Medium', value: 'Medium' },
    { label: 'High', value: 'High' }
];

const YES_NO_OPTIONS = [
    { label: 'Yes', value: 'Yes' },
    { label: 'No', value: 'No' }
];

const FALLBACK_ESTIMATE_REQUIRED_OPTIONS = [
    { label: ESTIMATE_REQUIRED_QUOTE_VALUE, value: ESTIMATE_REQUIRED_QUOTE_VALUE },
    { label: ESTIMATE_OPTION_PRE_APPROVED, value: ESTIMATE_OPTION_PRE_APPROVED }
];

const UI_ONLY_ITEM_FIELDS = new Set([
    'showAssetResults',
    'showProductResults',
    'productOptions',
    'assetOptions',
    'productSearchLookupClass',
    'assetSearchLookupClass',
    'assetSearchDropdownStyle',
    'productSearchDropdownStyle'
]);

let itemKeyCounter = 0;
let itemNumberCounter = 0;
const productSearchTimers = {};

function nextItemKey() {
    itemKeyCounter += 1;
    return `item-${itemKeyCounter}`;
}

function nextItemNumber() {
    itemNumberCounter += 1;
    return itemNumberCounter;
}

function resetItemCounters() {
    itemKeyCounter = 0;
    itemNumberCounter = 0;
}

/**
 * @description Serialized line editor for Create Order product-details step (GW-4348 / GW-5996).
 */
export default class CreateOrderItems extends LightningElement {
    _accountId = '';
    _initialContextLoaded = false;
    _boundRepositionOpenDropdowns;

    items = [];
    activeSections = [];

    accountAssets = [];
    shipToAddresses = [];
    departmentOptions = [];
    eligibleContactIds = [];
    contactEmailById = {};
    contactNameById = {};

    disinfectedOptions = [];
    estimateRequiredOptions = [...FALLBACK_ESTIMATE_REQUIRED_OPTIONS];

    showNewContactModal = false;
    newContactTargetType = 'contact';
    newContactItemKey = '';
    newContactFirstName = '';
    newContactLastName = '';
    newContactEmail = '';
    newContactPhone = '';
    newContactTitle = '';
    isCreatingContact = false;

    @api accountName = '';

    @api
    get accountId() {
        return this._accountId;
    }

    set accountId(value) {
        const nextAccountId = value || '';
        if (nextAccountId === this._accountId) {
            return;
        }
        this._accountId = nextAccountId;
        void this.refreshAccountDependencies();
    }

    connectedCallback() {
        void this.loadInitialContextOnce();
    }

    get hasItems() {
        return (this.items || []).length > 0;
    }

    get priorityOptions() {
        return PRIORITY_OPTIONS;
    }

    get yesNoOptions() {
        return YES_NO_OPTIONS;
    }

    get mediaAccept() {
        return MEDIA_ACCEPT;
    }

    get shipToComboboxOptions() {
        return (this.shipToAddresses || []).map((option) => ({
            label: option.label || option.name,
            value: option.id
        }));
    }

    get defaultShipToAccountId() {
        const addresses = this.shipToAddresses || [];
        const primary = addresses.find((option) => option.isPrimary);
        if (primary?.id) {
            return primary.id;
        }
        return addresses[0]?.id || '';
    }

    get isContactSearchDisabled() {
        return !this.accountId || !this.eligibleContactIds.length;
    }

    get contactRecordFilter() {
        if (!this.accountId || !this.eligibleContactIds.length) {
            return null;
        }

        return {
            criteria: [
                {
                    fieldPath: 'Id',
                    operator: 'in',
                    value: this.eligibleContactIds
                }
            ]
        };
    }

    get isNewContactEmailRequired() {
        return this.newContactTargetType === 'estimate';
    }

    get newContactModalDescription() {
        const accountLabel = this.accountName || 'the selected account';
        if (this.newContactTargetType === 'estimate') {
            return `Estimate Contact will be linked to ${accountLabel}. Email is required.`;
        }
        return `Contact will be linked to ${accountLabel} and available on this item.`;
    }

    get itemDisplayRows() {
        return (this.items || []).map((item) => ({
            ...item,
            serialNumber: this.normalizeUppercaseText(item.serialNumber),
            model: this.normalizeUppercaseText(item.model),
            make: this.normalizeUppercaseText(item.make),
            sectionLabel: this.buildSectionLabel(item),
            showEstimateContact: item.estimateRequired === ESTIMATE_REQUIRED_QUOTE_VALUE,
            showWarrantyNotes: item.repairWarranty === 'Yes',
            shipToAddressDisplay: this.resolveShipToAddressDisplay(item.shipToAccountId),
            attachmentItems: item.attachments || [],
            hasAttachments: (item.attachments || []).length > 0,
            assetOptions: this.filterAccountAssets(item.assetSearchText),
            isAssetSearchDisabled: !this.accountId || !(this.accountAssets || []).length,
            isProductSearchDisabled: !this.accountId,
            productSearchLookupClass: item.showProductResults
                ? 'product-search-lookup slds-form-element product-search-lookup--open'
                : 'product-search-lookup slds-form-element',
            assetSearchLookupClass: item.showAssetResults
                ? 'product-search-lookup slds-form-element product-search-lookup--open'
                : 'product-search-lookup slds-form-element'
        }));
    }

    @api
    ensureSerializedItem() {
        if ((this.items || []).length > 0) {
            return;
        }
        const item = this.buildEmptyItem();
        this.items = [item];
        this.expandItemSection(item.key, { collapseOthers: true });
    }

    @api
    addSerializedItem() {
        const item = this.buildEmptyItem();
        this.items = [item, ...(this.items || [])];
        this.expandItemSection(item.key, { collapseOthers: true });
    }

    @api
    validate() {
        if (!(this.items || []).length) {
            this.showToast('Validation', 'Add at least one item.', 'error');
            return false;
        }

        const requiredInputs = this.template.querySelectorAll(
            'lightning-input[required], lightning-combobox[required], lightning-record-picker[required], lightning-textarea[required]'
        );
        let inputsValid = true;

        requiredInputs.forEach((input) => {
            if (!input.reportValidity()) {
                inputsValid = false;
            }
        });

        if (!inputsValid) {
            this.showToast('Validation', 'Complete all required fields.', 'error');
            return false;
        }

        for (let index = 0; index < this.items.length; index++) {
            const item = this.items[index];
            const itemNumber = item.itemNumber || index + 1;

            if (!item.product2Id) {
                this.showToast('Validation', `Product is required on Item ${itemNumber}.`, 'error');
                return false;
            }

            if (!item.productLine) {
                this.showToast(
                    'Validation',
                    `Product Line is required on Item ${itemNumber}.`,
                    'error'
                );
                return false;
            }

            if (!String(item.serialNumber || '').trim()) {
                this.showToast(
                    'Validation',
                    `Serial Number is required on Item ${itemNumber}.`,
                    'error'
                );
                return false;
            }

            if (!String(item.model || '').trim()) {
                this.showToast('Validation', `Model is required on Item ${itemNumber}.`, 'error');
                return false;
            }

            if (!item.disinfected) {
                this.showToast('Validation', `Disinfected is required on Item ${itemNumber}.`, 'error');
                return false;
            }

            if (!item.estimateRequired) {
                this.showToast(
                    'Validation',
                    `Estimate Required is required on Item ${itemNumber}.`,
                    'error'
                );
                return false;
            }

            if (!String(item.reportedProblem || '').trim()) {
                this.showToast(
                    'Validation',
                    `Reported Problem is required on Item ${itemNumber}.`,
                    'error'
                );
                return false;
            }

            if (
                item.repairWarranty === 'Yes' &&
                !String(item.warrantyNotes || '').trim()
            ) {
                this.showToast(
                    'Validation',
                    `Warranty Notes is required on Item ${itemNumber} when Repair Warranty is Yes.`,
                    'error'
                );
                return false;
            }

            if (!item.departmentId) {
                this.showToast(
                    'Validation',
                    `Department is required on Item ${itemNumber}.`,
                    'error'
                );
                return false;
            }

            if (!item.contactId) {
                this.showToast('Validation', `Contact is required on Item ${itemNumber}.`, 'error');
                return false;
            }

            if (this.shipToComboboxOptions.length > 0 && !item.shipToAccountId) {
                this.showToast('Validation', `Ship-To is required on Item ${itemNumber}.`, 'error');
                return false;
            }

            if (
                item.estimateRequired === ESTIMATE_REQUIRED_QUOTE_VALUE &&
                !item.estimateContactId
            ) {
                this.showToast(
                    'Validation',
                    `Estimate Contact is required on Item ${itemNumber}.`,
                    'error'
                );
                return false;
            }
        }

        return true;
    }

    @api
    getValues() {
        return {
            items: (this.items || []).map((item) => this.snapshotItem(item))
        };
    }

    @api
    reset() {
        this.items = [];
        this.activeSections = [];
        this.accountAssets = [];
        this.shipToAddresses = [];
        this.departmentOptions = [];
        this.eligibleContactIds = [];
        this.contactEmailById = {};
        this.contactNameById = {};
        resetItemCounters();
    }

    buildEmptyItem() {
        const defaultShipTo = this.defaultShipToAccountId;
        return {
            key: nextItemKey(),
            itemNumber: nextItemNumber(),
            itemType: ITEM_TYPE_SERIALIZED,
            assetId: '',
            assetSearchText: '',
            showAssetResults: false,
            assetSearchDropdownStyle: '',
            product2Id: '',
            productSearchText: '',
            showProductResults: false,
            productSearchDropdownStyle: '',
            productOptions: [],
            assetOptions: [],
            serialNumber: '',
            model: '',
            make: '',
            productLine: '',
            priority: 'Medium',
            disinfected: '',
            estimateRequired: '',
            estimateContactId: '',
            reportedProblem: '',
            loanerRequested: false,
            isLoanerAsset: false,
            departmentId: '',
            contactId: '',
            customerPo: '',
            customerReference: '',
            shipToAccountId: defaultShipTo,
            shipToAddressDisplay: this.resolveShipToAddressDisplay(defaultShipTo),
            repairWarranty: '',
            warrantyNotes: '',
            attachments: [],
            productSearchLookupClass: 'product-search-lookup slds-form-element',
            assetSearchLookupClass: 'product-search-lookup slds-form-element'
        };
    }

    snapshotItem(item) {
        const snapshot = {};
        Object.keys(item).forEach((field) => {
            if (UI_ONLY_ITEM_FIELDS.has(field)) {
                return;
            }
            if (field === 'attachments') {
                snapshot.attachments = (item.attachments || []).map((attachment) => ({
                    contentDocumentId: attachment.contentDocumentId,
                    name: attachment.name
                }));
                return;
            }
            snapshot[field] = item[field];
        });
        snapshot.shipToAddressDisplay = this.resolveShipToAddressDisplay(item.shipToAccountId);
        return snapshot;
    }

    buildSectionLabel(item) {
        const itemNumber = item.itemNumber;
        const productLine = String(item.productLine || '').trim() || '[PRODUCT LINE]';
        const serial = String(item.serialNumber || '').trim() || '[Serial #]';
        const model = String(item.model || '').trim() || '[Model #]';
        return `Item ${itemNumber}: ${productLine} - Serial #${serial} | Model #${model}`;
    }

    normalizeUppercaseText(value) {
        return String(value || '')
            .trim()
            .toUpperCase();
    }

    resolveShipToAddressDisplay(shipToAccountId) {
        const selected = (this.shipToAddresses || []).find((option) => option.id === shipToAccountId);
        return selected?.addressDisplay || '';
    }

    async loadInitialContextOnce() {
        if (this._initialContextLoaded) {
            return;
        }

        try {
            const ctx = await getInitialContext({
                recordId: null,
                objectApiName: null,
                recordIds: null
            });
            this.disinfectedOptions = ctx.disinfectedOptions || [];
            this.estimateRequiredOptions = this.resolveEstimateRequiredOptions(
                ctx.estimateRequiredOptions || ctx.estReqOptions || []
            );
            this._initialContextLoaded = true;
        } catch (error) {
            this.showError('Failed to load picklist options', error);
        }
    }

    resolveEstimateRequiredOptions(sourceOptions) {
        const allowed = new Set([ESTIMATE_REQUIRED_QUOTE_VALUE, ESTIMATE_OPTION_PRE_APPROVED]);
        const filtered = (sourceOptions || []).filter((option) => allowed.has(option.value));
        return filtered.length > 0 ? filtered : [...FALLBACK_ESTIMATE_REQUIRED_OPTIONS];
    }

    async refreshAccountDependencies() {
        await Promise.all([
            this.loadAccountAssets(),
            this.loadEligibleContacts(),
            this.loadShipToAddresses(),
            this.loadDepartments()
        ]);
    }

    async loadAccountAssets() {
        if (!this.accountId) {
            this.accountAssets = [];
            return;
        }

        try {
            this.accountAssets = await getAssetsForAccount({ accountId: this.accountId });
        } catch (error) {
            this.accountAssets = [];
            this.showError('Failed to load assets', error);
        }
    }

    async loadEligibleContacts() {
        if (!this.accountId) {
            this.eligibleContactIds = [];
            this.contactEmailById = {};
            this.contactNameById = {};
            return;
        }

        try {
            const contacts = await getContactsForAccount({ accountId: this.accountId });
            this.eligibleContactIds = (contacts || []).map((contact) => contact.Id);
            const emailById = {};
            const nameById = {};
            (contacts || []).forEach((contact) => {
                emailById[contact.Id] = contact.Email || '';
                nameById[contact.Id] = contact.Name || '';
            });
            this.contactEmailById = emailById;
            this.contactNameById = nameById;
        } catch (error) {
            this.eligibleContactIds = [];
            this.contactEmailById = {};
            this.contactNameById = {};
            this.showError('Failed to load contacts', error);
        }
    }

    async loadShipToAddresses() {
        if (!this.accountId) {
            this.shipToAddresses = [];
            return;
        }

        try {
            this.shipToAddresses =
                (await getShipToAddressesForAccount({ accountId: this.accountId })) || [];
            const defaultShipToId = this.defaultShipToAccountId;
            this.items = (this.items || []).map((item) => {
                if (item.shipToAccountId) {
                    return {
                        ...item,
                        shipToAddressDisplay: this.resolveShipToAddressDisplay(item.shipToAccountId)
                    };
                }
                return {
                    ...item,
                    shipToAccountId: defaultShipToId,
                    shipToAddressDisplay: this.resolveShipToAddressDisplay(defaultShipToId)
                };
            });
        } catch (error) {
            this.shipToAddresses = [];
            this.showError('Failed to load Ship-To addresses', error);
        }
    }

    getAdditionalDepartmentIds() {
        return [
            ...new Set(
                (this.items || []).map((item) => item.departmentId).filter((departmentId) => !!departmentId)
            )
        ];
    }

    async loadDepartments() {
        if (!this.accountId) {
            this.departmentOptions = [];
            return;
        }

        try {
            this.departmentOptions = await getDepartmentsForAccount({
                accountId: this.accountId,
                additionalDepartmentIds: this.getAdditionalDepartmentIds()
            });
        } catch (error) {
            this.departmentOptions = [];
            this.showError('Failed to load departments', error);
        }
    }

    async ensureDepartmentOptionAvailable(departmentId) {
        if (!departmentId || !this.accountId) {
            return;
        }

        if ((this.departmentOptions || []).some((option) => option.value === departmentId)) {
            return;
        }

        try {
            this.departmentOptions = await getDepartmentsForAccount({
                accountId: this.accountId,
                additionalDepartmentIds: [departmentId]
            });
        } catch (error) {
            this.showError('Failed to load department', error);
        }
    }

    buildAssetDisplayLabel(asset) {
        if (!asset) {
            return '';
        }
        const parts = [asset.name, asset.productName, asset.model].filter((part) =>
            Boolean(String(part || '').trim())
        );
        return parts.length > 0 ? parts.join(' · ') : asset.id;
    }

    filterAccountAssets(searchTerm) {
        const assets = this.accountAssets || [];
        const term = String(searchTerm || '').trim().toLowerCase();
        const filtered = !term
            ? assets
            : assets.filter((asset) => {
                  const assetName = String(asset.name || '').toLowerCase();
                  const productName = String(asset.productName || '').toLowerCase();
                  const model = String(asset.model || '').toLowerCase();
                  const serial = String(asset.serialNumber || '').toLowerCase();
                  return (
                      assetName.includes(term) ||
                      productName.includes(term) ||
                      model.includes(term) ||
                      serial.includes(term)
                  );
              });
        return filtered.slice(0, 20).map((asset) => ({
            label: this.buildAssetDisplayLabel(asset),
            value: asset.serialNumber || asset.id
        }));
    }

    findAssetByValue(assetValue) {
        if (!assetValue) {
            return null;
        }

        const normalizedSerial = this.normalizeUppercaseText(assetValue);
        return (this.accountAssets || []).find((asset) => {
            if (asset.id === assetValue) {
                return true;
            }
            return this.normalizeUppercaseText(asset.serialNumber || asset.id) === normalizedSerial;
        });
    }

    /**
     * Clears the Account Asset link only (keeps Serial Number).
     */
    clearAssetLink(item) {
        item.assetId = '';
        item.assetSearchText = '';
        return item;
    }

    /**
     * Clears product fields that Account Asset / Product selection populate.
     */
    clearProductDerivedFields(item) {
        item.product2Id = '';
        item.productSearchText = '';
        item.productLine = '';
        item.model = '';
        item.make = '';
        return item;
    }

    /**
     * Clears Account Asset and every field it auto-populated, including Serial Number.
     */
    clearAssetSelection(item) {
        this.clearAssetLink(item);
        this.clearProductDerivedFields(item);
        item.serialNumber = '';
        return item;
    }

    /**
     * If an Account Asset is linked to a different Product, drop the asset link.
     * Serial Number is kept so the user can correct product for the same unit.
     */
    clearAssetLinkIfProductMismatch(item, product2Id) {
        if (!item.assetId) {
            return item;
        }
        const asset = this.findAssetByValue(item.assetId);
        const assetProductId = asset?.product2Id || '';
        if (assetProductId && product2Id && assetProductId === product2Id) {
            return item;
        }
        return this.clearAssetLink(item);
    }

    applyAssetToItem(item, asset) {
        if (!asset) {
            // Serial/no-match: drop Asset. Clear Product only when it came from that Asset.
            const hadAsset = Boolean(item.assetId);
            this.clearAssetLink(item);
            if (hadAsset) {
                this.clearProductDerivedFields(item);
            }
            return item;
        }

        item.assetId = asset.id;
        item.product2Id = asset.product2Id || '';
        item.model = this.normalizeUppercaseText(asset.model || '');
        item.make = this.normalizeUppercaseText(asset.make || '');
        item.productLine = asset.productLine || '';
        item.productSearchText = asset.productName || '';
        item.serialNumber = this.normalizeUppercaseText(asset.serialNumber || '');
        item.assetSearchText = this.buildAssetDisplayLabel(asset);
        if (asset.departmentId) {
            item.departmentId = asset.departmentId;
        }
        return item;
    }

    expandItemSection(sectionKey, options = {}) {
        const { collapseOthers = false } = options;
        const nextSections = collapseOthers
            ? [sectionKey]
            : [...new Set([...(this.activeSections || []), sectionKey])];
        this.activeSections = [];
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => {
            this.activeSections = nextSections;
        }, 0);
    }

    handleSectionToggle(event) {
        this.activeSections = event.detail.openSections;
    }

    handleRemoveItem(event) {
        event.stopPropagation();
        const itemKey = event.currentTarget.dataset.key;
        if (!itemKey) {
            return;
        }
        this.items = (this.items || []).filter((item) => item.key !== itemKey);
        this.activeSections = (this.activeSections || []).filter((section) => section !== itemKey);
    }

    handleItemFieldChange(event) {
        const { key, field } = event.target.dataset;
        let value =
            event.target.type === 'checkbox' ? event.target.checked : event.detail.value;

        if (field === 'serialNumber' || field === 'model' || field === 'make') {
            value = this.normalizeUppercaseText(value);
        }

        this.items = (this.items || []).map((item) => {
            if (item.key !== key) {
                return item;
            }

            const updated = { ...item, [field]: value };

            if (field === 'serialNumber') {
                this.applyAssetToItem(updated, this.findAssetByValue(value));
            }

            if (field === 'estimateRequired') {
                if (value === ESTIMATE_REQUIRED_QUOTE_VALUE) {
                    updated.estimateContactId =
                        updated.estimateContactId || updated.contactId || '';
                } else {
                    updated.estimateContactId = '';
                }
            }

            if (field === 'repairWarranty' && value !== 'Yes') {
                updated.warrantyNotes = '';
            }

            if (field === 'shipToAccountId') {
                updated.shipToAddressDisplay = this.resolveShipToAddressDisplay(value);
            }

            return updated;
        });

        if (field === 'serialNumber') {
            const updatedItem = (this.items || []).find((item) => item.key === key);
            if (updatedItem?.departmentId) {
                void this.ensureDepartmentOptionAvailable(updatedItem.departmentId);
            }
        }

        if (field === 'departmentId' && value) {
            void this.ensureDepartmentOptionAvailable(value);
        }
    }

    handleItemContactChange(event) {
        const key = event.target.dataset.key;
        const contactId = event.detail.recordId || '';

        this.items = (this.items || []).map((item) => {
            if (item.key !== key) {
                return item;
            }

            const defaultEstimateContact =
                item.estimateRequired === ESTIMATE_REQUIRED_QUOTE_VALUE &&
                !item.estimateContactId
                    ? contactId
                    : item.estimateContactId;

            return {
                ...item,
                contactId,
                estimateContactId: defaultEstimateContact
            };
        });
    }

    handleItemEstimateContactChange(event) {
        const key = event.target.dataset.key;
        const estimateContactId = event.detail.recordId || '';

        this.items = (this.items || []).map((item) => {
            if (item.key !== key) {
                return item;
            }

            const contactId = item.contactId || estimateContactId;
            return {
                ...item,
                estimateContactId,
                contactId
            };
        });
    }

    handleAssetSearchFocus(event) {
        const itemKey = event.target.dataset.key;
        if (!this.accountId || !(this.accountAssets || []).length) {
            return;
        }

        this.items = (this.items || []).map((item) =>
            item.key === itemKey ? { ...item, showAssetResults: true } : item
        );
        this.scheduleDropdownPosition(itemKey, 'asset');
    }

    handleAssetSearchInput(event) {
        const itemKey = event.target.dataset.key;
        const searchTerm = event.target.value || '';

        this.items = (this.items || []).map((item) => {
            if (item.key !== itemKey) {
                return item;
            }

            const updated = {
                ...item,
                assetSearchText: searchTerm,
                showAssetResults: true
            };

            // Clearing or editing away from a selected asset drops asset-driven fields.
            if (item.assetId) {
                this.clearAssetSelection(updated);
                updated.assetSearchText = searchTerm;
                updated.showAssetResults = true;
            }

            return updated;
        });
        this.scheduleDropdownPosition(itemKey, 'asset');
    }

    handleAssetSearchBlur(event) {
        const itemKey = event.target.dataset.key;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => {
            this.items = (this.items || []).map((item) =>
                item.key === itemKey
                    ? { ...item, showAssetResults: false, assetSearchDropdownStyle: '' }
                    : item
            );
            this.removeDropdownViewportListenersIfIdle();
        }, 200);
    }

    handleAssetOptionSelect(event) {
        event.preventDefault();
        const itemKey = event.currentTarget.dataset.key;
        const assetValue = event.currentTarget.dataset.value || '';

        this.items = (this.items || []).map((item) => {
            if (item.key !== itemKey) {
                return item;
            }

            const updated = {
                ...item,
                showAssetResults: false,
                assetSearchDropdownStyle: ''
            };
            this.applyAssetToItem(updated, this.findAssetByValue(assetValue));
            return updated;
        });
        this.removeDropdownViewportListenersIfIdle();

        const updatedItem = (this.items || []).find((item) => item.key === itemKey);
        if (updatedItem?.departmentId) {
            void this.ensureDepartmentOptionAvailable(updatedItem.departmentId);
        }
    }

    handleProductSearchFocus(event) {
        const itemKey = event.target.dataset.key;
        const item = (this.items || []).find((row) => row.key === itemKey);
        if (!item || !this.accountId) {
            return;
        }

        const searchTerm = item.productSearchText || '';
        void this.loadProductOptionsForItem(itemKey, searchTerm, true);
    }

    handleProductSearchInput(event) {
        const itemKey = event.target.dataset.key;
        const searchTerm = event.target.value || '';

        this.items = (this.items || []).map((item) => {
            if (item.key !== itemKey) {
                return item;
            }

            const updated = {
                ...item,
                productSearchText: searchTerm,
                showProductResults: true
            };
            // Clearing/editing Product drops asset-driven fields including Serial Number.
            if (item.product2Id || item.assetId) {
                this.clearAssetSelection(updated);
                updated.productSearchText = searchTerm;
                updated.showProductResults = true;
            }
            return updated;
        });

        this.scheduleProductSearch(itemKey, searchTerm);
        this.scheduleDropdownPosition(itemKey, 'product');
    }

    handleProductSearchBlur(event) {
        const itemKey = event.target.dataset.key;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => {
            this.items = (this.items || []).map((item) =>
                item.key === itemKey
                    ? { ...item, showProductResults: false, productSearchDropdownStyle: '' }
                    : item
            );
            this.removeDropdownViewportListenersIfIdle();
        }, 200);
    }

    scheduleProductSearch(itemKey, searchTerm) {
        if (productSearchTimers[itemKey]) {
            clearTimeout(productSearchTimers[itemKey]);
        }

        // eslint-disable-next-line @lwc/lwc/no-async-operation
        productSearchTimers[itemKey] = window.setTimeout(() => {
            void this.loadProductOptionsForItem(itemKey, searchTerm, true);
        }, 300);
    }

    async loadProductOptionsForItem(itemKey, searchTerm, showResults) {
        const item = (this.items || []).find((row) => row.key === itemKey);
        if (!item || !this.accountId) {
            return;
        }

        try {
            const products = await getProductsForReturnOrderLine({
                productLine: '',
                requireServiceAssetType: true,
                searchTerm: searchTerm || '',
                deviceType: ''
            });
            const productOptions = (products || []).map((product) => ({
                label: product.label,
                value: product.value,
                model: product.model || '',
                description: product.description || ''
            }));

            this.items = (this.items || []).map((row) =>
                row.key === itemKey
                    ? { ...row, productOptions, showProductResults: showResults }
                    : row
            );
            if (showResults) {
                this.scheduleDropdownPosition(itemKey, 'product');
            }
        } catch (error) {
            this.showError('Failed to load products', error);
        }
    }

    async handleProductOptionSelect(event) {
        event.preventDefault();
        const itemKey = event.currentTarget.dataset.key;
        const product2Id = event.currentTarget.dataset.value || '';
        const item = (this.items || []).find((row) => row.key === itemKey);
        const selectedOption = (item?.productOptions || []).find(
            (option) => option.value === product2Id
        );

        this.items = (this.items || []).map((row) => {
            if (row.key !== itemKey) {
                return row;
            }

            const updated = {
                ...row,
                product2Id,
                productSearchText: selectedOption?.label || '',
                model: product2Id
                    ? this.normalizeUppercaseText(selectedOption?.model || '')
                    : '',
                make: product2Id ? row.make : '',
                productLine: product2Id ? row.productLine : '',
                showProductResults: false,
                productSearchDropdownStyle: ''
            };

            if (!product2Id) {
                // Explicit Product clear — also clear Asset and Serial Number.
                this.clearAssetSelection(updated);
                return updated;
            }

            // Keep asset only when it still points at the selected product.
            this.clearAssetLinkIfProductMismatch(updated, product2Id);
            return updated;
        });
        this.removeDropdownViewportListenersIfIdle();

        if (!product2Id) {
            return;
        }

        try {
            const product = await getProductDetails({
                productId: product2Id,
                requireServiceAssetType: true
            });
            const manufacturer = product?.Manufacturer__c || product?.manufacturer__c || '';
            this.items = (this.items || []).map((row) => {
                if (row.key !== itemKey) {
                    return row;
                }

                const updated = {
                    ...row,
                    productLine: product?.ProductLine__c || row.productLine,
                    model: product?.Model__c
                        ? this.normalizeUppercaseText(product.Model__c)
                        : row.model,
                    make: manufacturer ? this.normalizeUppercaseText(manufacturer) : row.make
                };
                this.clearAssetLinkIfProductMismatch(updated, product2Id);
                return updated;
            });
        } catch (error) {
            this.showError('Failed to load product details', error);
        }
    }

    scheduleDropdownPosition(itemKey, kind) {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => {
            if (kind === 'asset') {
                this.updateAssetSearchDropdownPosition(itemKey);
            } else {
                this.updateProductSearchDropdownPosition(itemKey);
            }
            this.ensureDropdownViewportListeners();
        }, 0);
    }

    updateAssetSearchDropdownPosition(itemKey) {
        const control = this.template.querySelector(
            `[data-asset-search-control="${itemKey}"]`
        );
        if (!control) {
            return;
        }
        const dropdownStyle = this.buildFixedDropdownStyle(control);
        this.items = (this.items || []).map((item) =>
            item.key === itemKey ? { ...item, assetSearchDropdownStyle: dropdownStyle } : item
        );
    }

    updateProductSearchDropdownPosition(itemKey) {
        const control = this.template.querySelector(
            `[data-product-search-control="${itemKey}"]`
        );
        if (!control) {
            return;
        }
        const dropdownStyle = this.buildFixedDropdownStyle(control);
        this.items = (this.items || []).map((item) =>
            item.key === itemKey ? { ...item, productSearchDropdownStyle: dropdownStyle } : item
        );
    }

    buildFixedDropdownStyle(control) {
        const rect = control.getBoundingClientRect();
        const top = Math.round(rect.bottom + 2);
        const left = Math.max(8, Math.round(rect.left));
        const viewportWidth = window.innerWidth || document.documentElement.clientWidth || 0;
        const maxWidth = viewportWidth > 0 ? Math.max(viewportWidth - left - 8, 200) : 480;
        const width = Math.min(Math.max(Math.round(rect.width), 280), maxWidth);
        // Inline transform:none so SLDS dropdown utilities cannot re-center the menu.
        return `top: ${top}px; left: ${left}px; width: ${width}px; transform: none;`;
    }

    ensureDropdownViewportListeners() {
        if (this._boundRepositionOpenDropdowns) {
            return;
        }
        this._boundRepositionOpenDropdowns = () => this.repositionOpenDropdowns();
        window.addEventListener('scroll', this._boundRepositionOpenDropdowns, true);
        window.addEventListener('resize', this._boundRepositionOpenDropdowns);
    }

    removeDropdownViewportListenersIfIdle() {
        const hasOpen = (this.items || []).some(
            (item) => item.showAssetResults || item.showProductResults
        );
        if (hasOpen || !this._boundRepositionOpenDropdowns) {
            return;
        }
        window.removeEventListener('scroll', this._boundRepositionOpenDropdowns, true);
        window.removeEventListener('resize', this._boundRepositionOpenDropdowns);
        this._boundRepositionOpenDropdowns = undefined;
    }

    repositionOpenDropdowns() {
        (this.items || []).forEach((item) => {
            if (item.showAssetResults) {
                this.updateAssetSearchDropdownPosition(item.key);
            }
            if (item.showProductResults) {
                this.updateProductSearchDropdownPosition(item.key);
            }
        });
    }

    disconnectedCallback() {
        if (this._boundRepositionOpenDropdowns) {
            window.removeEventListener('scroll', this._boundRepositionOpenDropdowns, true);
            window.removeEventListener('resize', this._boundRepositionOpenDropdowns);
            this._boundRepositionOpenDropdowns = undefined;
        }
    }

    handleFileUploadFinished(event) {
        const itemKey = event.target.dataset.key;
        const uploadedFiles = event.detail.files || [];
        if (!itemKey || uploadedFiles.length === 0) {
            return;
        }

        const newAttachments = uploadedFiles.map((file) => ({
            contentDocumentId: file.documentId,
            name: file.name
        }));

        this.items = (this.items || []).map((item) =>
            item.key === itemKey
                ? {
                      ...item,
                      attachments: [...(item.attachments || []), ...newAttachments]
                  }
                : item
        );
    }

    handleRemoveAttachment(event) {
        const itemKey = event.target.dataset.key;
        const contentDocumentId = event.target.dataset.documentId;
        if (!itemKey || !contentDocumentId) {
            return;
        }

        this.items = (this.items || []).map((item) =>
            item.key === itemKey
                ? {
                      ...item,
                      attachments: (item.attachments || []).filter(
                          (attachment) => attachment.contentDocumentId !== contentDocumentId
                      )
                  }
                : item
        );
    }

    handleOpenNewContact(event) {
        const itemKey = event.currentTarget.dataset.key;
        const contactTarget = event.currentTarget.dataset.contactTarget || 'contact';
        this.openNewContactModal(itemKey, contactTarget);
    }

    openNewContactModal(itemKey, contactTarget = 'contact') {
        if (!this.accountId) {
            this.showToast('Validation', 'Select an account before creating a contact.', 'error');
            return;
        }

        this.newContactTargetType = contactTarget === 'estimate' ? 'estimate' : 'contact';
        this.newContactItemKey = itemKey;
        this.newContactFirstName = '';
        this.newContactLastName = '';
        this.newContactEmail = '';
        this.newContactPhone = '';
        this.newContactTitle = '';
        this.showNewContactModal = true;
    }

    handleCloseNewContactModal() {
        this.showNewContactModal = false;
        this.newContactTargetType = 'contact';
        this.newContactItemKey = '';
    }

    handleNewContactFieldChange(event) {
        const field = event.target.dataset.field;
        this[field] = event.detail.value;
    }

    validateNewContactForm() {
        const inputs = this.template.querySelectorAll(
            'lightning-input[data-form="new-contact"][required]'
        );
        let isValid = true;

        inputs.forEach((input) => {
            if (!input.reportValidity()) {
                isValid = false;
            }
        });

        return isValid;
    }

    cacheContactDetails(contactId, contactName, contactEmail) {
        if (!contactId) {
            return;
        }

        this.contactEmailById = {
            ...this.contactEmailById,
            [contactId]: contactEmail || ''
        };
        if (contactName) {
            this.contactNameById = {
                ...this.contactNameById,
                [contactId]: contactName
            };
        }
    }

    async handleSaveNewContact() {
        if (!this.validateNewContactForm()) {
            return;
        }

        this.isCreatingContact = true;
        try {
            const result = await createAccountContact({
                accountId: this.accountId,
                firstName: this.newContactFirstName,
                lastName: this.newContactLastName,
                email: this.newContactEmail,
                phone: this.newContactPhone,
                title: this.newContactTitle,
                requireEmail: this.isNewContactEmailRequired
            });

            this.cacheContactDetails(
                result.contactId,
                result.contactName,
                result.contactEmail || this.newContactEmail
            );
            if (!this.eligibleContactIds.includes(result.contactId)) {
                this.eligibleContactIds = [...this.eligibleContactIds, result.contactId];
            }

            const itemKey = this.newContactItemKey;
            if (this.newContactTargetType === 'estimate') {
                this.items = (this.items || []).map((item) => {
                    if (item.key !== itemKey) {
                        return item;
                    }

                    return {
                        ...item,
                        estimateContactId: result.contactId,
                        contactId: item.contactId || result.contactId
                    };
                });
                this.handleCloseNewContactModal();
                this.showToast(
                    'Success',
                    `Estimate Contact ${result.contactName} was created and selected.`,
                    'success'
                );
                return;
            }

            this.items = (this.items || []).map((item) => {
                if (item.key !== itemKey) {
                    return item;
                }

                const defaultEstimateContact =
                    item.estimateRequired === ESTIMATE_REQUIRED_QUOTE_VALUE &&
                    !item.estimateContactId
                        ? result.contactId
                        : item.estimateContactId;

                return {
                    ...item,
                    contactId: result.contactId,
                    estimateContactId: defaultEstimateContact
                };
            });

            this.handleCloseNewContactModal();
            this.showToast(
                'Success',
                `Contact ${result.contactName} was created and selected for this item.`,
                'success'
            );
        } catch (error) {
            this.showError('Failed to create contact', error);
        } finally {
            this.isCreatingContact = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    showError(title, error) {
        const message =
            error?.body?.message || error?.message || 'An unexpected error occurred.';
        this.showToast(title, message, 'error');
    }
}