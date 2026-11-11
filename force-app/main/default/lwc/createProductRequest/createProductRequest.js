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

import title from '@salesforce/label/c.CreateProductRequest_Title';
import requestDetails from '@salesforce/label/c.CreateProductRequest_RequestDetails';
import workOrder from '@salesforce/label/c.CreateProductRequest_WorkOrder';
import serviceResource from '@salesforce/label/c.CreateProductRequest_ServiceResource';
import requiredDeliveryDate from '@salesforce/label/c.CreateProductRequest_RequiredDeliveryDate';
import shipmentTypeLabel from '@salesforce/label/c.CreateProductRequest_ShipmentType';
import shipTo from '@salesforce/label/c.CreateProductRequest_ShipTo';
import myLocation from '@salesforce/label/c.CreateProductRequest_MyLocation';
import customer from '@salesforce/label/c.CreateProductRequest_Customer';
import address from '@salesforce/label/c.CreateProductRequest_Address';
import parts from '@salesforce/label/c.CreateProductRequest_Parts';
import addPart from '@salesforce/label/c.CreateProductRequest_AddPart';
import addSelected from '@salesforce/label/c.CreateProductRequest_AddSelected';
import substitutePart from '@salesforce/label/c.CreateProductRequest_SubstitutePart';
import scanPart from '@salesforce/label/c.CreateProductRequest_ScanPart';
import requiredOnWorkOrder from '@salesforce/label/c.CreateProductRequest_RequiredOnWorkOrder';
import quantity from '@salesforce/label/c.CreateProductRequest_Quantity';
import partsSummary from '@salesforce/label/c.CreateProductRequest_PartsSummary';
import noSearchTerm from '@salesforce/label/c.CreateProductRequest_NoSearchTerm';
import noProducts from '@salesforce/label/c.CreateProductRequest_NoProducts';
import cancel from '@salesforce/label/c.CreateProductRequest_Cancel';
import save from '@salesforce/label/c.CreateProductRequest_Save';
import submitQuestion from '@salesforce/label/c.CreateProductRequest_SubmitQuestion';
import yes from '@salesforce/label/c.CreateProductRequest_Yes';
import no from '@salesforce/label/c.CreateProductRequest_No';
import submitted from '@salesforce/label/c.CreateProductRequest_Submitted';
import created from '@salesforce/label/c.CreateProductRequest_Created';
import close from '@salesforce/label/c.CreateProductRequest_Close';
import loading from '@salesforce/label/c.CreateProductRequest_Loading';
import saving from '@salesforce/label/c.CreateProductRequest_Saving';
import removePart from '@salesforce/label/c.CreateProductRequest_RemovePart';
import decreaseQuantity from '@salesforce/label/c.CreateProductRequest_DecreaseQuantity';
import increaseQuantity from '@salesforce/label/c.CreateProductRequest_IncreaseQuantity';
import searchResults from '@salesforce/label/c.CreateProductRequest_SearchResults';
import scannerUnavailable from '@salesforce/label/c.CreateProductRequest_ScannerUnavailable';
import noAddresses from '@salesforce/label/c.CreateProductRequest_NoAddresses';
import deliveryDateRequired from '@salesforce/label/c.CreateProductRequest_DeliveryDateRequired';
import shipmentTypeRequired from '@salesforce/label/c.CreateProductRequest_ShipmentTypeRequired';
import shipSetLabel from '@salesforce/label/c.CreateProductRequest_ShipSet';
import addressRequired from '@salesforce/label/c.CreateProductRequest_AddressRequired';
import customerRequired from '@salesforce/label/c.CreateProductRequest_CustomerRequired';
import partsRequired from '@salesforce/label/c.CreateProductRequest_PartsRequired';
import unexpected from '@salesforce/label/c.CreateProductRequest_Unexpected';

const SHIP_TO_MY_LOCATION = 'MyLocation';
const SHIP_TO_CUSTOMER = 'Customer';
const SCREEN_FORM = 'form';
const SCREEN_CONFIRM = 'confirm';
const SCREEN_SUCCESS = 'success';
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
        title,
        requestDetails,
        workOrder,
        serviceResource,
        requiredDeliveryDate,
        shipmentType: shipmentTypeLabel,
        shipTo,
        myLocation,
        customer,
        address,
        parts,
        addPart,
        addSelected,
        substitutePart,
        scanPart,
        requiredOnWorkOrder,
        quantity,
        noSearchTerm,
        noProducts,
        cancel,
        save,
        submitQuestion,
        yes,
        no,
        submitted,
        close,
        loading,
        saving,
        removePart,
        decreaseQuantity,
        increaseQuantity,
        searchResults,
        scannerUnavailable,
        noAddresses,
        deliveryDateRequired,
        shipmentTypeRequired,
        shipSet: shipSetLabel,
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

    get showConfirm() {
        return this.screen === SCREEN_CONFIRM;
    }

    get showSuccess() {
        return this.screen === SCREEN_SUCCESS;
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
        return this.addresses.map((row) => ({ label: row.name, value: row.recordId }));
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
        return partsSummary.replace('{0}', String(this.partCount)).replace('{1}', String(this.unitCount));
    }

    get createdMessage() {
        return created.replace('{0}', this.productRequestNumber || '');
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
            shipSet: false
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
                requiredOnWorkOrder: part.requiredOnWorkOrder === true
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
            await submitProductRequest({ productRequestId: this.productRequestId });
            if (this.shouldOpenCreatedRequest) {
                this.openCreatedProductRequest();
                return;
            }
            this.screen = SCREEN_SUCCESS;
        } catch (error) {
            this.formError = this.errorMessage(error);
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