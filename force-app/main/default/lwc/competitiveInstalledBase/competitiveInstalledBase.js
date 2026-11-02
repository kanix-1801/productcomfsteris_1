import { LightningElement, api, wire } from 'lwc';
import getCompetitiveInstalledBase from '@salesforce/apex/CompetitiveInstalledBaseController.getCompetitiveInstalledBase';

/**
 * @author Ujwala Patil
 * @date 2026/08/12
 *
 * @description
 * GC-2860 - Competitive Installed base
 * Displays rolled-up competitive assets and competitor summary for facility,
 * customer parent, IDN, and GPO account contexts on the Customer 360 tab.
 * Supports client-side pagination for the asset detail datatable.
 */

// Datatable column definitions for rolled-up competitive asset detail.
const ASSET_COLUMNS = [
    {
        label: 'Asset Name',
        fieldName: 'assetUrl',
        type: 'url',
        initialWidth: 220,
        wrapText: true,
        typeAttributes: {
            label: { fieldName: 'name' },
            target: '_blank'
        }
    },
    {
        label: 'Customer/Facility',
        fieldName: 'facilityAccountUrl',
        type: 'url',
        initialWidth: 240,
        wrapText: true,
        typeAttributes: {
            label: { fieldName: 'facilityAccountName' },
            target: '_blank'
        }
    },
    { label: 'Competitor', fieldName: 'competitorName', initialWidth: 180, wrapText: true },
    { label: 'Product', fieldName: 'productName', initialWidth: 220, wrapText: true },
    { label: 'Status', fieldName: 'status', initialWidth: 120, wrapText: true },
    { label: 'Value', fieldName: 'assetValue', type: 'currency', initialWidth: 130 },
    {
        label: 'Oracle Address Id',
        fieldName: 'facilityOracleAddressId',
        initialWidth: 200,
        wrapText: true
    }
];

/**
 * Resolves the competitor label from Product2 manufacturer or family.
 *
 * @param {Object} assetRecord Apex Asset row returned by Competitive Installed Base.
 * @returns {String} Competitor name used for summary grouping and display.
 */
function resolveCompetitorName(assetRecord) {
    const product = assetRecord?.Product2;

    if (product?.Manufacturer__c) {
        return product.Manufacturer__c;
    }

    if (product?.Family) {
        return product.Family;
    }

    return '';
}

/**
 * Maps an Apex Asset row to the datatable-friendly shape used by the UI.
 *
 * @param {Object} assetRecord Apex Asset row returned by Competitive Installed Base.
 * @returns {Object} Client-side asset row for lightning-datatable rendering.
 */
function mapAssetRecord(assetRecord) {
    return {
        id: assetRecord.Id,
        name: assetRecord.Name,
        status: assetRecord.Status,
        assetValue: assetRecord.AssetValue__c,
        competitorName: resolveCompetitorName(assetRecord),
        productName: assetRecord.Product2?.Name,
        facilityAccountName: assetRecord.Account?.Name,
        facilityOracleAddressId: assetRecord.Account?.OracleAddressId__c,
        assetUrl: assetRecord.Id ? `/${assetRecord.Id}` : null,
        facilityAccountUrl: assetRecord.AccountId ? `/${assetRecord.AccountId}` : null
    };
}

export default class CompetitiveInstalledBase extends LightningElement {
    @api recordId;

    assetColumns = ASSET_COLUMNS;

    // Competitive installed base metrics and detail rows returned from Apex.
    assets = [];
    competitorSummaries = [];
    totalAssetCount = 0;
    totalAssetValue = 0;
    assetDetailHeading = 'Asset Detail';
    error;
    isLoading = true;

    // Client-side pagination state for asset detail datatable.
    assetPageNumber = 1;
    assetPageSize = 25;

    // Page size options dropdown for asset detail pagination.
    pageSizeOptions = [
        { label: '25', value: '25' },
        { label: '50', value: '50' },
        { label: '100', value: '100' },
        { label: '150', value: '150' }
    ];

    /**
     * Loads competitive installed base data for the current account context.
     * Resets pagination whenever fresh Apex data is received.
     */
    @wire(getCompetitiveInstalledBase, { accountId: '$recordId' })
    wiredCompetitiveInstalledBase({ data, error }) {
        this.isLoading = false;

        if (data) {
            this.error = undefined;
            this.competitorSummaries = data.competitorSummaries || [];
            this.totalAssetCount = data.totalAssetCount || 0;
            this.totalAssetValue = data.totalAssetValue || 0;
            this.assetDetailHeading = data.assetDetailHeading || 'Asset Detail';
            this.assets = (data.assets || []).map(mapAssetRecord);
            this.assetPageNumber = 1;
        } else if (error) {
            this.assets = [];
            this.competitorSummaries = [];
            this.totalAssetCount = 0;
            this.totalAssetValue = 0;
            this.assetDetailHeading = 'Asset Detail';
            this.assetPageNumber = 1;
            this.error = error;
        }
    }

    get hasAssets() {
        return this.assets.length > 0;
    }

    // Client-side pagination getters for asset detail datatable.
    get paginatedAssets() {
        const startIndex = (this.assetPageNumber - 1) * this.assetPageSize;
        return this.assets.slice(startIndex, startIndex + this.assetPageSize);
    }

    get assetPageSizeValue() {
        return String(this.assetPageSize);
    }

    get assetTotalPages() {
        return Math.max(Math.ceil(this.assets.length / this.assetPageSize), 1);
    }

    get disablePreviousAssetPage() {
        return this.assetPageNumber <= 1;
    }

    get disableNextAssetPage() {
        return this.assetPageNumber >= this.assetTotalPages;
    }

    // Handle client-side pagination for asset detail datatable.
    handlePreviousAssetPage() {
        if (this.assetPageNumber > 1) {
            this.assetPageNumber--;
        }
    }

    handleNextAssetPage() {
        if (this.assetPageNumber < this.assetTotalPages) {
            this.assetPageNumber++;
        }
    }

    handleAssetPageSizeChange(event) {
        this.assetPageSize = Number(event.detail.value);
        this.assetPageNumber = 1;
    }

    get hasSummary() {
        return this.competitorSummaries.length > 0;
    }

    /**
     * Formats competitor summary rows for the summary table display.
     */
    get formattedCompetitorSummaries() {
        return this.competitorSummaries.map((summary) => ({
            competitorName: summary.competitorName,
            assetCount: summary.assetCount,
            formattedTotalValue: this.formatCurrency(summary.totalValue)
        }));
    }

    formatCurrency(value) {
        if (value === null || value === undefined) {
            return '';
        }

        return new Intl.NumberFormat(undefined, {
            style: 'currency',
            currency: 'USD'
        }).format(value);
    }

    get hasError() {
        return this.error !== undefined;
    }

    /**
     * Formats total asset value for display in the summary header.
     */
    get formattedTotalValue() {
        return this.formatCurrency(this.totalAssetValue);
    }
}