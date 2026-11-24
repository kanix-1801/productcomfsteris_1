import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { getPicklistValues } from 'lightning/uiObjectInfoApi';
import { CloseActionScreenEvent } from 'lightning/actions';
import { FlowNavigationFinishEvent } from 'lightning/flowSupport';
import { getBarcodeScanner } from 'lightning/mobileCapabilities';
import USER_ID from '@salesforce/user/Id';
import SHIPMENT_TYPE_FIELD from '@salesforce/schema/ProductRequest.ShipmentType';

import getContext from '@salesforce/apex/CreateProductRequestController.getContext';
import getAddresses from '@salesforce/apex/CreateProductRequestController.getAddresses';
import searchParts from '@salesforce/apex/CreateProductRequestController.searchParts';
import createProductRequestFromJson from '@salesforce/apex/CreateProductRequestController.createProductRequestFromJson';
import submitProductRequest from '@salesforce/apex/CreateProductRequestController.submitProductRequest';
import getOracleSubmitPreview from '@salesforce/apex/CreateProductRequestController.getOracleSubmitPreview';

import deliveryDateRequired from '@salesforce/label/c.CreateProductRequest_DeliveryDateRequired';
import shipmentTypeRequired from '@salesforce/label/c.CreateProductRequest_ShipmentTypeRequired';
import addressRequired from '@salesforce/label/c.CreateProductRequest_AddressRequired';
import customerRequired from '@salesforce/label/c.CreateProductRequest_CustomerRequired';
import partsRequired from '@salesforce/label/c.CreateProductRequest_PartsRequired';
import unexpected from '@salesforce/label/c.CreateProductRequest_Unexpected';

const PARTS_SUMMARY = '{0} parts · {1} units';
const CREATED_MESSAGE = 'Product Request {0} was created.';

const SHIP_TO_MY_LOCATION = 'MyLocation';
const SHIP_TO_CUSTOMER = 'Customer';
const SCREEN_FORM = 'form';
const SCREEN_CONFIRM = 'confirm';
const SCREEN_ERP_BLOCKED = 'erpBlocked';
const SCREEN_ERP_CONFIRM = 'erpConfirm';
const SCREEN_ERP_SUCCESS = 'erpSuccess';
const SCREEN_ERP_FAIL = 'erpFail';
const SCREEN_ERP_FAULT = 'erpFault';
const DEFAULT_NEED_BY_HOUR = 8;

function isWorkOrderId(value) {
    return typeof value === 'string' && value.startsWith('0WO');
}

function isServiceResourceId(value) {
    return typeof value === 'string' && value.startsWith('0Hn');
}

function isSupportedRecordId(value) {
    return isWorkOrderId(value) || isServiceResourceId(value);
}

function defaultNeedByDate() {
    const eightAm = new Date();
    eightAm.setHours(DEFAULT_NEED_BY_HOUR, 0, 0, 0);
    return eightAm.toISOString();
}

export default class CreateProductRequest extends NavigationMixin(LightningElement) {
    labels = {
        title: 'New product request',
        requestDetails: 'Request details',
        workOrder: 'Work order',
        serviceResource: 'Service Resource',
        requiredDeliveryDate: 'Need By Date',
        shipmentType: 'Shipment Type',
        shipTo: 'Ship To',
        myLocation: 'My location',
        customer: 'Customer',
        address: 'Address',
        parts: 'Parts',
        addPart: 'Add a part by name or code',
        addSelected: 'Add selected',
        substitutePart: 'This product has a substitute part:',
        oeNotes: 'This Part has OE notes',
        scanPart: 'Scan a part',
        requiredOnWorkOrder: 'Required on work order',
        quantity: 'Quantity',
        noSearchTerm: 'Enter a product name or item number.',
        noProducts: 'No products matched your search. Type a different search term.',
        cancel: 'Cancel',
        save: 'Save request',
        submitQuestion: 'Do you want to submit this Product Request to Oracle?',
        yes: 'Yes',
        no: 'No',
        close: 'Close',
        erpScreenTitle: 'Product Request - SCR - Submit to ERP',
        erpSubmitHeading: 'Submit Product Request to ERP',
        erpSubmitBody:
            'Product Request <b>{0}</b> will be marked <b>Submit Create</b>. The Oracle callout runs after that save, including when the field is set outside this screen.',
        erpSubmitContinue: 'Click <b>Submit</b> to continue.',
        erpPriorHeading: 'Prior integration result',
        erpStatus: 'Integration Status',
        erpMessage: 'Message',
        erpSubmit: 'Submit',
        erpSavedHeading: 'Submit Create saved',
        erpSavedBody:
            'The Oracle callout runs from this status change. When the callout returns, Submission to ERP changes to <b>Submitted</b> and Integration Status, Integration Message, and ERP Order Number are updated.',
        erpSavedBoomi: 'ERP submit failed. Fix the issue and submit again.',
        finish: 'Finish',
        cannotSubmit: 'This Parts Request cannot be submitted to Oracle.',
        loading: 'Loading',
        saving: 'Saving',
        removePart: 'Remove',
        decreaseQuantity: 'Decrease quantity',
        increaseQuantity: 'Increase quantity',
        searchResults: 'Matching parts',
        scannerUnavailable: 'The barcode scanner is not available on this device.',
        noAddresses: 'No addresses were found for your service resource location.',
        deliveryDateRequired,
        shipmentTypeRequired,
        shipSet: 'Ship Set',
        addressRequired,
        customerRequired,
        partsRequired,
        unexpected
    };

    @api userId;
    /** @description Set by a flow screen. Empty when this component is a browser screen action. */
    @api availableActions = [];

    recordIdValue;
    isConnected = false;
    contextKey;
    isLoading = true;
    isSaving = false;
    loadError;
    formError;
    screen = SCREEN_FORM;
    context;
    serviceResourceId;
    needByDate = defaultNeedByDate();
    shipmentType;
    shipSet = false;
    shipmentTypeOptions = [];
    shipToMode = SHIP_TO_MY_LOCATION;
    addressId;
    shipToAccountId;
    addresses = [];
    partsRows = [];
    searchTerm = '';
    searchMessage;
    searchResults = [];
    isSearching = false;
    productRequestId;
    productRequestNumber;
    oracleIntegrationStatus;
    oracleIntegrationMessage;
    erpOrderNumber;
    blockMessage;
    faultMessage;
    showPriorResult = false;
    searchTimer;

    @api
    get recordId() {
        return this.recordIdValue;
    }

    set recordId(value) {
        if (value && !isSupportedRecordId(value)) {
            return;
        }
        this.recordIdValue = value;
        this.loadContext();
    }

    @wire(getPicklistValues, {
        recordTypeId: '$productRequestRecordTypeId',
        fieldApiName: SHIPMENT_TYPE_FIELD
    })
    wiredShipmentType({ data, error }) {
        if (data) {
            this.shipmentTypeOptions = data.values.map((entry) => ({
                label: entry.label,
                value: entry.value
            }));
            if (!this.shipmentType && data.defaultValue) {
                this.shipmentType = data.defaultValue.value;
            }
        } else if (error) {
            this.formError = this.errorMessage(error);
        }
    }

    @wire(CurrentPageReference)
    setPageReference(pageRef) {
        const pageRecordId = pageRef?.state?.recordId || pageRef?.state?.c__recordId;
        if (pageRecordId && !this.recordIdValue && isSupportedRecordId(pageRecordId)) {
            this.recordId = pageRecordId;
        }
    }

    connectedCallback() {
        this.isConnected = true;
        this.loadContext();
    }

    disconnectedCallback() {
        this.isConnected = false;
        window.clearTimeout(this.searchTimer);
    }

    get productRequestRecordTypeId() {
        return this.context?.productRequestRecordTypeId;
    }

    get showForm() {
        return !this.isLoading && !this.loadError && !this.context?.blockMessage && this.screen === SCREEN_FORM;
    }

    get showBlocked() {
        return !this.isLoading && !this.loadError && this.context?.blockMessage;
    }

    get showPageTitle() {
        return !this.showErpBlocked
            && !this.showErpConfirm
            && !this.showErpSuccess
            && !this.showErpFail
            && !this.showErpFault;
    }

    get showConfirm() {
        return this.screen === SCREEN_CONFIRM;
    }

    get showErpBlocked() {
        return this.screen === SCREEN_ERP_BLOCKED;
    }

    get showErpConfirm() {
        return this.screen === SCREEN_ERP_CONFIRM;
    }

    get showErpSuccess() {
        return this.screen === SCREEN_ERP_SUCCESS;
    }

    get showErpFail() {
        return this.screen === SCREEN_ERP_FAIL;
    }

    get showErpFault() {
        return this.screen === SCREEN_ERP_FAULT;
    }

    get erpSubmitBodyHtml() {
        return (this.labels.erpSubmitBody || '').replace('{0}', this.escapeHtml(this.productRequestNumber || ''));
    }

    get hasWorkOrder() {
        return this.context?.hasWorkOrder === true;
    }

    get showServiceResourcePicker() {
        const resourceCount = (this.context?.serviceResources || []).length;
        if (this.hasWorkOrder) {
            return resourceCount > 0;
        }
        return resourceCount > 1;
    }

    get serviceResourceOptions() {
        return (this.context?.serviceResources || []).map((resource) => ({
            label: resource.name,
            value: resource.recordId
        }));
    }

    get shipToOptions() {
        const options = [{ label: this.labels.myLocation, value: SHIP_TO_MY_LOCATION }];
        if (this.hasWorkOrder) {
            options.push({ label: this.labels.customer, value: SHIP_TO_CUSTOMER });
        }
        return options;
    }

    get showMyLocation() {
        return this.shipToMode === SHIP_TO_MY_LOCATION;
    }

    get showCustomer() {
        return this.hasWorkOrder && this.shipToMode === SHIP_TO_CUSTOMER;
    }

    get addressOptions() {
        return this.addresses.map((row) => ({
            label: [row.name, row.addressID].filter((part) => part).join(' - '),
            value: row.recordId
        }));
    }

    get shipToAccountOptions() {
        return (this.context?.shipToAccounts || []).map((row) => ({
            label: row.name,
            value: row.recordId
        }));
    }

    get showNoAddresses() {
        return this.showMyLocation && this.addresses.length === 0;
    }

    get partCount() {
        return this.partsRows.length;
    }

    get unitCount() {
        return this.partsRows.reduce((total, row) => total + this.quantityValue(row.quantity), 0);
    }

    get partsSummaryText() {
        return PARTS_SUMMARY.replace('{0}', String(this.partCount)).replace('{1}', String(this.unitCount));
    }

    get createdMessage() {
        return CREATED_MESSAGE.replace('{0}', this.productRequestNumber || '');
    }

    get isSaveDisabled() {
        return this.isSaving || this.isLoading;
    }

    get hasSearchResults() {
        return this.searchResults.length > 0;
    }

    get isAddSelectedDisabled() {
        return !this.searchResults.some((row) => row.selected);
    }

    async loadContext() {
        if (!this.isConnected) {
            return;
        }
        const key = `${this.recordIdValue || ''}:${this.userId || USER_ID}`;
        if (this.contextKey === key) {
            return;
        }
        this.contextKey = key;
        this.isLoading = true;
        this.loadError = undefined;
        try {
            const data = await getContext({
                workOrderId: this.recordIdValue || null,
                userId: this.userId || USER_ID
            });
            if (this.contextKey !== key) {
                return;
            }
            this.applyContext(data);
        } catch (error) {
            if (this.contextKey === key) {
                this.loadError = this.errorMessage(error);
            }
        } finally {
            if (this.contextKey === key) {
                this.isLoading = false;
            }
        }
    }

    applyContext(data) {
        this.context = data;
        this.serviceResourceId = data.selectedServiceResourceId;
        this.addresses = data.addresses || [];
        this.addressId = data.defaultAddressId;
        this.shipToAccountId = data.defaultShipToAccountId;
        this.shipToMode = SHIP_TO_MY_LOCATION;
        this.partsRows = (data.requiredParts || []).map((row) => ({
            ...row,
            quantity: row.quantity || 1,
            shipSet: false,
            oeNotesExpanded: false,
            oeNotesIcon: 'utility:chevronright'
        }));
    }

    handleServiceResourceChange(event) {
        this.serviceResourceId = event.detail.value;
        this.loadAddresses();
    }

    async loadAddresses() {
        this.isSaving = true;
        this.formError = undefined;
        try {
            const result = await getAddresses({
                serviceResourceId: this.serviceResourceId,
                userId: this.userId || USER_ID,
                workOrderId: isSupportedRecordId(this.recordIdValue) ? this.recordIdValue : null
            });
            this.addresses = result.addresses || [];
            this.addressId = result.defaultAddressId;
        } catch (error) {
            this.formError = this.errorMessage(error);
        } finally {
            this.isSaving = false;
        }
    }

    handleNeedByDateChange(event) {
        this.needByDate = event.detail?.value ?? event.target.value;
    }

    handleShipmentTypeChange(event) {
        this.shipmentType = event.detail.value;
    }

    handleShipToChange(event) {
        this.shipToMode = event.detail.value;
        this.formError = undefined;
    }

    handleAddressChange(event) {
        this.addressId = event.detail.value;
    }

    handleShipToAccountChange(event) {
        this.shipToAccountId = event.detail.value;
    }

    handleSearchInput(event) {
        this.searchTerm = event.detail?.value ?? event.target.value;
        window.clearTimeout(this.searchTimer);
        this.searchTimer = window.setTimeout(() => {
            this.runSearch();
        }, 300);
    }

    async runSearch() {
        const term = (this.searchTerm || '').trim();
        if (!term) {
            this.searchResults = [];
            this.searchMessage = undefined;
            return;
        }
        this.isSearching = true;
        this.searchMessage = undefined;
        try {
            const rows = await searchParts({ searchTerm: term });
            this.searchResults = (rows || []).map((row) => ({
                ...row,
                selected: false,
                choiceLabel: [row.name, row.productCode].filter((part) => part).join(' · ')
            }));
            this.searchMessage = this.searchResults.length === 0 ? this.labels.noProducts : undefined;
        } catch (error) {
            this.searchResults = [];
            this.searchMessage = this.errorMessage(error);
        } finally {
            this.isSearching = false;
        }
    }

    async handleScan() {
        const scanner = getBarcodeScanner();
        if (!scanner || !scanner.isAvailable()) {
            this.formError = this.labels.scannerUnavailable;
            return;
        }
        try {
            const value = await this.captureBarcode(scanner);
            if (!value) {
                return;
            }
            this.searchTerm = value;
            await this.runSearch();
            if (this.searchResults.length === 1) {
                this.addPart(this.searchResults[0]);
                this.searchResults = [];
                this.searchTerm = '';
            }
        } catch (error) {
            if (error?.code !== 'userDismissedScanner') {
                this.formError = error?.message || this.labels.scannerUnavailable;
            }
        }
    }

    async captureBarcode(scanner) {
        let first;
        if (typeof scanner.scan === 'function') {
            const results = await scanner.scan({
                instructionText: this.labels.scanPart,
                successText: this.labels.scanPart
            });
            first = Array.isArray(results) ? results[0] : results;
        } else {
            first = await scanner.beginCapture({
                instructionText: this.labels.scanPart,
                successText: this.labels.scanPart
            });
        }
        const value = typeof first === 'string' ? first : first?.value;
        return (value || '').trim();
    }

    handleToggleResult(event) {
        const productId = event.target.name;
        const selected = event.target.checked;
        this.searchResults = this.searchResults.map((row) => (
            row.productId === productId ? { ...row, selected } : row
        ));
    }

    handleAddSelected() {
        this.searchResults.filter((row) => row.selected).forEach((row) => this.addPart(row));
        this.searchResults = this.searchResults.map((row) => ({ ...row, selected: false }));
    }

    addPart(part) {
        const existing = this.partsRows.find((row) => row.productId === part.productId);
        if (existing) {
            existing.quantity = this.quantityValue(existing.quantity) + 1;
            this.partsRows = [...this.partsRows];
            return;
        }
        this.partsRows = [
            ...this.partsRows,
            {
                ...part,
                key: part.key || part.productId,
                quantity: 1,
                shipSet: this.shipSet === true,
                requiredOnWorkOrder: part.requiredOnWorkOrder === true,
                oeNotesExpanded: false,
                oeNotesIcon: 'utility:chevronright'
            }
        ];
    }

    handleDecreaseQuantity(event) {
        this.changeQuantity(event.currentTarget.dataset.key, -1);
    }

    handleIncreaseQuantity(event) {
        this.changeQuantity(event.currentTarget.dataset.key, 1);
    }

    changeQuantity(key, delta) {
        this.partsRows = this.partsRows.map((row) => {
            if (row.key !== key) {
                return row;
            }
            const nextQuantity = this.quantityValue(row.quantity) + delta;
            return { ...row, quantity: nextQuantity > 0 ? nextQuantity : 1 };
        });
    }

    handleShipSetChange(event) {
        const checked = event.detail.checked === true;
        this.shipSet = checked;
        this.partsRows = this.partsRows.map((row) => ({ ...row, shipSet: checked }));
    }

    handleLineShipSetChange(event) {
        const key = event.target.name;
        const checked = event.detail.checked === true;
        this.partsRows = this.partsRows.map((row) => (
            row.key === key ? { ...row, shipSet: checked } : row
        ));
        if (!checked) {
            this.shipSet = false;
        }
    }

    handleToggleOeNotes(event) {
        const key = event.currentTarget.dataset.key;
        this.partsRows = this.partsRows.map((row) => {
            if (row.key !== key) {
                return row;
            }
            const expanded = row.oeNotesExpanded !== true;
            return {
                ...row,
                oeNotesExpanded: expanded,
                oeNotesIcon: expanded ? 'utility:chevrondown' : 'utility:chevronright'
            };
        });
    }

    handleRemovePart(event) {
        const key = event.currentTarget.dataset.key;
        this.partsRows = this.partsRows.filter((row) => row.key !== key);
    }

    async handleSave() {
        this.formError = this.validateForm();
        if (this.formError) {
            return;
        }
        this.isSaving = true;
        try {
            const result = await createProductRequestFromJson({
                requestJson: JSON.stringify(this.buildRequest())
            });
            this.productRequestId = result.productRequestId;
            this.productRequestNumber = result.productRequestNumber;
            this.screen = SCREEN_CONFIRM;
        } catch (error) {
            this.formError = this.errorMessage(error);
        } finally {
            this.isSaving = false;
        }
    }

    buildRequest() {
        const lines = this.partsRows
            .map((row) => ({
                productId: row.productId,
                quantity: this.quantityValue(row.quantity),
                shipSet: row.shipSet === true
            }))
            .filter((line) => line.productId && line.quantity > 0);
        return {
            workOrderId: isSupportedRecordId(this.recordIdValue) ? this.recordIdValue : null,
            userId: this.userId || USER_ID,
            serviceResourceId: this.serviceResourceId,
            needByDate: this.needByDate,
            shipmentType: this.shipmentType,
            shipSet: this.shipSet === true,
            shipToMode: this.hasWorkOrder ? this.shipToMode : SHIP_TO_MY_LOCATION,
            addressId: this.showMyLocation ? this.addressId : null,
            shipToAccountId: this.showCustomer ? this.shipToAccountId : null,
            lines,
            linesJson: JSON.stringify(lines)
        };
    }

    validateForm() {
        if (!this.needByDate) {
            return this.labels.deliveryDateRequired;
        }
        if (!this.shipmentType) {
            return this.labels.shipmentTypeRequired;
        }
        if (this.showMyLocation && !this.addressId) {
            return this.labels.addressRequired;
        }
        if (this.showCustomer && !this.shipToAccountId) {
            return this.labels.customerRequired;
        }
        const hasQuantity = this.partsRows.some((row) => this.quantityValue(row.quantity) > 0);
        if (!hasQuantity) {
            return this.labels.partsRequired;
        }
        return undefined;
    }

    async handleSubmitYes() {
        this.isSaving = true;
        this.formError = undefined;
        try {
            const preview = await getOracleSubmitPreview({ productRequestId: this.productRequestId });
            if (!preview?.eligible) {
                this.blockMessage = preview?.blockMessage || this.labels.cannotSubmit;
                this.screen = SCREEN_ERP_BLOCKED;
                return;
            }
            this.oracleIntegrationStatus = preview.integrationStatus;
            this.oracleIntegrationMessage = preview.integrationMessage;
            this.showPriorResult = preview.showPriorResult === true;
            this.screen = SCREEN_ERP_CONFIRM;
        } catch (error) {
            this.faultMessage = this.errorMessage(error);
            this.screen = SCREEN_ERP_FAULT;
        } finally {
            this.isSaving = false;
        }
    }

    async handleErpSubmit() {
        this.isSaving = true;
        this.formError = undefined;
        try {
            // Set Submit Create. The after-save flow makes the one Oracle call.
            const result = await submitProductRequest({ productRequestId: this.productRequestId });
            this.oracleIntegrationStatus = result?.integrationStatus;
            this.oracleIntegrationMessage = result?.integrationMessage;
            this.erpOrderNumber = result?.erpOrderNumber;
            this.screen = result?.success === true ? SCREEN_ERP_SUCCESS : SCREEN_ERP_FAIL;
        } catch (error) {
            this.faultMessage = this.errorMessage(error);
            this.screen = SCREEN_ERP_FAULT;
        } finally {
            this.isSaving = false;
        }
    }

    handleClose() {
        if (this.productRequestId && this.shouldOpenCreatedRequest) {
            this.openCreatedProductRequest();
            return;
        }
        this.dispatchEvent(new CloseActionScreenEvent());
        this.dispatchEvent(new FlowNavigationFinishEvent());
    }

    get shouldOpenCreatedRequest() {
        const inFlow = Array.isArray(this.availableActions) && this.availableActions.length > 0;
        const inMobileApp = typeof navigator !== 'undefined'
            && /SalesforceMobileSDK/i.test(navigator.userAgent || '');
        return !inFlow && !inMobileApp;
    }

    openCreatedProductRequest() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.productRequestId,
                objectApiName: 'ProductRequest',
                actionName: 'view'
            }
        });
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    escapeHtml(value) {
        return String(value)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    quantityValue(value) {
        const quantityNumber = Number(value);
        return Number.isFinite(quantityNumber) ? quantityNumber : 0;
    }

    errorMessage(error) {
        const body = error?.body;
        const pageError = Array.isArray(body?.pageErrors) ? body.pageErrors[0]?.message : undefined;
        const outputError = body?.output?.errors?.[0]?.message;
        const fieldErrors = body?.output?.fieldErrors;
        const firstField = fieldErrors ? Object.values(fieldErrors)[0] : undefined;
        const fieldError = Array.isArray(firstField) ? firstField[0]?.message : undefined;
        const bodyMessage = Array.isArray(body) ? body[0]?.message : body?.message;
        return bodyMessage || pageError || outputError || fieldError || error?.message || this.labels.unexpected;
    }
}