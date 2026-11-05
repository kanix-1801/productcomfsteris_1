import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CurrentPageReference } from 'lightning/navigation';
import { getRecord, getFieldValue, getRecordNotifyChange } from 'lightning/uiRecordApi';
import { registerRefreshHandler, unregisterRefreshHandler, RefreshEvent } from 'lightning/refresh';
import OPPORTUNITY_QUOTE_COUNT from '@salesforce/schema/Opportunity.Quote_Count__c';
import OPPORTUNITY_RECORD_TYPE from '@salesforce/schema/Opportunity.RecordType.DeveloperName';
import TRIAL_OPPORTUNITY from '@salesforce/schema/Trial__c.Opportunity__c';
import SAMPLE_OPPORTUNITY from '@salesforce/schema/Sample__c.RelatedOpportunity__c';
import {
    publish,
    subscribe,
    unsubscribe,
    MessageContext
} from 'lightning/messageService';
import GENERATE_QUOTE_REFRESH from '@salesforce/messageChannel/generateQuoteRefresh__c';
import getQuotes from '@salesforce/apex/GenerateQuoteController.getQuotes';
import refreshQuotes from '@salesforce/apex/GenerateQuoteController.refreshQuotes';
import createQuote from '@salesforce/apex/GenerateQuoteController.createQuote';
import copyQuote from '@salesforce/apex/GenerateQuoteController.copyQuote';
import mergeQuote from '@salesforce/apex/GenerateQuoteController.mergeQuote';
import validateQuoteAccess from '@salesforce/apex/GenerateQuoteController.validateQuoteAccess';
import getSalesConnectionQuoteUrl from '@salesforce/apex/GenerateQuoteController.getSalesConnectionQuoteUrl';
import syncQuoteForecastConfidence from '@salesforce/apex/GenerateQuoteController.syncQuoteForecastConfidence';
import getQuoteForecastConfidenceOptions from '@salesforce/apex/QuoteForecastConfidenceService.getActiveOptions';
import QUOTE_NUMBER_HELP_TEXT from '@salesforce/label/c.Quote_Number_Helptext';
import QUOTE_FORECAST_INELIGIBLE_HELP_TEXT from '@salesforce/label/c.QuoteForecastIneligibleHelptext';
import REFRESH_QUOTE_SUCCESS_MESSAGE from '@salesforce/label/c.RefreshQuoteSuccessMessage';
import { FlowNavigationFinishEvent } from 'lightning/flowSupport'; //GC-3609

const QUOTES_PAGE_SIZE = 5;
const OPPORTUNITY_RECORD_TYPE_GOODWILL = 'HC_Sales_Customer_Goodwill_Support';
const QUOTE_TYPE_GOODWILL = 'Goodwill Quote';
const QUOTE_TYPE_TRIAL = 'Trial Quote';
const QUOTE_TYPE_SAMPLE = 'Sample Quote';

export default class GenerateQuote extends LightningElement {
    @api recordId;
    @api isDealerPortal = false;
    @api opportunityRecordId;
    @api launchMode;
    /** Record-page context for Trial or Sample quote lists. Values: trial, sample. */
    @api recordPageContext;

    quoteIdHelpText = QUOTE_NUMBER_HELP_TEXT;
    forecastIneligibleHelpText = QUOTE_FORECAST_INELIGIBLE_HELP_TEXT;
    refreshQuoteSuccessMessage = REFRESH_QUOTE_SUCCESS_MESSAGE;

    @track allQuotes = [];
    @track modalQuotes = [];
    @track currentPage = 1;
    @track showExistingQuotesModal = false;
    @track isLoading = false;
    @track groupBySalesCategory = false;

    pageRef;
    pageRecordId;
    initialized = false;
    loadRequestId = 0;

    refreshHandlerId;
    refreshSubscription;
    messageContext;
    wiredOpportunity;
    wiredContextRecord;
    forecastConfidenceOptions = [];

    @wire(getQuoteForecastConfidenceOptions)
    wiredForecastConfidenceOptions({ data }) {
        if (!data) {
            return;
        }

        this.forecastConfidenceOptions = data.map((entry) => ({
            label: entry.label,
            value: entry.value
        }));
        this.allQuotes = this.allQuotes.map((quote) => this.withForecastSelectOptions(quote));
    }

    @wire(getRecord, {
        recordId: '$contextRecordId',
        fields: '$contextRecordFields'
    })
    wiredContextRecordValue(result) {
        this.wiredContextRecord = result;
        this.tryInitialize();
    }

    @wire(getRecord, {
        recordId: '$opportunityIdForQuoteOperations',
        fields: [OPPORTUNITY_QUOTE_COUNT, OPPORTUNITY_RECORD_TYPE]
    })
    wiredOpportunityRecord(result) {
        this.wiredOpportunity = result;
    }

    @wire(MessageContext)
    wiredMessageContext(context) {
        this.messageContext = context;
        this.trySubscribeRefreshChannel();
    }

    @wire(CurrentPageReference)
    wiredPageReference(pageRef) {
        this.pageRef = pageRef;
        if (pageRef?.state?.recordId) {
            this.pageRecordId = pageRef.state.recordId;
        }
        this.tryInitialize();
        this.trySubscribeRefreshChannel();
    }

    connectedCallback() {
        debugger;
        this.tryInitialize();
        this.refreshHandlerId = registerRefreshHandler(this, () => this.handleRegisteredRefresh());
    }

    disconnectedCallback() {
        if (this.refreshHandlerId) {
            unregisterRefreshHandler(this.refreshHandlerId);
        }

        if (this.refreshSubscription) {
            unsubscribe(this.refreshSubscription);
            this.refreshSubscription = null;
        }
    }

    trySubscribeRefreshChannel() {
        if (this.refreshSubscription || !this.messageContext || !this.pageRef || this.isQuickAction) {
            return;
        }

        this.refreshSubscription = subscribe(
            this.messageContext,
            GENERATE_QUOTE_REFRESH,
            (message) => this.handleRefreshMessage(message)
        );
    }

    handleRefreshMessage(message) {
        if (message?.recordId && message.recordId === this.opportunityIdForQuoteOperations) {
            this.loadData();
        }
    }

    notifyRecordPageRefresh() {
        if (!this.messageContext || !this.opportunityIdForQuoteOperations) {
            return;
        }

        publish(this.messageContext, GENERATE_QUOTE_REFRESH, {
            recordId: this.opportunityIdForQuoteOperations
        });
    }

    notifyOpportunityRecordRefresh() {
        if (!this.opportunityIdForQuoteOperations) {
            return;
        }

        getRecordNotifyChange([{ recordId: this.opportunityIdForQuoteOperations }]);
        this.dispatchEvent(new RefreshEvent());
    }

    scheduleOpportunityRecordRefresh() {
        window.setTimeout(() => {
            this.notifyOpportunityRecordRefresh();
            this.notifyRecordPageRefresh();
        }, 0);
    }

    handleRegisteredRefresh() {
        return new Promise((resolve) => {
            if (this.isQuickAction) {
                resolve(true);
                return;
            }

            this.loadData()
                .then(() => resolve(true))
                .catch(() => resolve(false));
        });
    }

    get effectiveRecordId() {
        return this.recordId || this.pageRecordId;
    }

    get effectiveRecordPageContext() {
        if (this.recordPageContext === 'trial' || this.recordPageContext === 'sample') {
            return this.recordPageContext;
        }

        const objectApiName = this.pageRef?.attributes?.objectApiName || '';
        if (objectApiName === 'Trial__c') {
            return 'trial';
        }
        if (objectApiName === 'Sample__c') {
            return 'sample';
        }

        return null;
    }

    get contextRecordId() {
        return this.effectiveRecordPageContext ? this.effectiveRecordId : null;
    }

    get contextRecordFields() {
        if (this.effectiveRecordPageContext === 'trial') {
            return [TRIAL_OPPORTUNITY];
        }
        if (this.effectiveRecordPageContext === 'sample') {
            return [SAMPLE_OPPORTUNITY];
        }
        return [];
    }

    get contextOpportunityId() {
        if (!this.effectiveRecordPageContext || !this.wiredContextRecord?.data) {
            return null;
        }

        if (this.effectiveRecordPageContext === 'trial') {
            return getFieldValue(this.wiredContextRecord.data, TRIAL_OPPORTUNITY);
        }
        if (this.effectiveRecordPageContext === 'sample') {
            return getFieldValue(this.wiredContextRecord.data, SAMPLE_OPPORTUNITY);
        }

        return null;
    }

    get isContextRecordLoading() {
        return (
            Boolean(this.effectiveRecordPageContext) &&
            !this.wiredContextRecord?.data &&
            !this.wiredContextRecord?.error
        );
    }

    get hasContextRecordError() {
        return Boolean(this.effectiveRecordPageContext) && Boolean(this.wiredContextRecord?.error);
    }

    get showRecordPageContextLoading() {
        return this.isContextRecordLoading;
    }

    get showRecordPageContextError() {
        if (!this.effectiveRecordPageContext || this.isContextRecordLoading) {
            return false;
        }

        return this.hasContextRecordError || !this.contextOpportunityId;
    }

    get recordPageContextErrorMessage() {
        if (this.effectiveRecordPageContext === 'trial') {
            return 'A related Opportunity is required on this Trial before quotes can be displayed.';
        }
        if (this.effectiveRecordPageContext === 'sample') {
            return 'A related Opportunity is required on this Sample before quotes can be displayed.';
        }

        return 'A related Opportunity is required before quotes can be displayed.';
    }

    get opportunityIdForQuoteOperations() {
        return this.opportunityRecordId || this.contextOpportunityId || this.effectiveRecordId;
    }

    get actionModeFromPageRef() {
        const apiName = this.pageRef?.attributes?.apiName || '';
        if (apiName.endsWith('GenerateTrialQuote') || apiName.endsWith('Generate_Trial_Quote')) {
            return 'generate_trial';
        }
        if (apiName.endsWith('GenerateSampleQuote') || apiName.endsWith('Generate_Sample_Quote')) {
            return 'generate_sample';
        }
        if (apiName.endsWith('Generate_Quote')) {
            return 'generate';
        }
        if (apiName.endsWith('CopyQuote')) {
            return 'copy';
        }
        if (apiName.endsWith('MergeQuote')) {
            return 'merge';
        }
        if (apiName.endsWith('Refresh_Quote')) {
            return 'refresh';
        }
        return null;
    }

    get quoteContextMode() {
        if (this.effectiveRecordPageContext === 'trial') {
            return 'generate_trial';
        }
        if (this.effectiveRecordPageContext === 'sample') {
            return 'generate_sample';
        }
        if (this.launchMode) {
            return this.launchMode;
        }

        return this.actionModeFromPageRef;
    }

    get quickActionMode() {
        return this.quoteContextMode;
    }

    get isGoodwillOpportunity() {
        if (!this.wiredOpportunity?.data) {
            return false;
        }

        return (
            getFieldValue(this.wiredOpportunity.data, OPPORTUNITY_RECORD_TYPE) ===
            OPPORTUNITY_RECORD_TYPE_GOODWILL
        );
    }

    get isGoodwillGenerateContext() {
        return this.quickActionMode === 'generate' && this.isGoodwillOpportunity;
    }

    get isTypedQuoteQuickAction() {
        return (
            this.quickActionMode === 'generate_trial' ||
            this.quickActionMode === 'generate_sample' ||
            this.isGoodwillGenerateContext
        );
    }

    get typedQuoteLabel() {
        if (this.quickActionMode === 'generate_trial') {
            return 'Trial';
        }
        if (this.quickActionMode === 'generate_sample') {
            return 'Sample';
        }
        if (this.isGoodwillGenerateContext) {
            return 'Goodwill';
        }
        return null;
    }

    get resolvedQuoteType() {
        if (this.quickActionMode === 'generate_trial') {
            return 'Trial Quote';
        }
        if (this.quickActionMode === 'generate_sample') {
            return 'Sample Quote';
        }
        if (this.isGoodwillGenerateContext) {
            return QUOTE_TYPE_GOODWILL;
        }

        return 'Normal Quote';
    }

    get generateActionLabel() {
        if (this.typedQuoteLabel) {
            return `Generate ${this.typedQuoteLabel} Quote`;
        }

        return 'Generate Quote';
    }

    get quoteTypeFilter() {
        if (this.quickActionMode === 'generate_trial') {
            return 'Trial Quote';
        }
        if (this.quickActionMode === 'generate_sample') {
            return 'Sample Quote';
        }
        if (this.isGoodwillGenerateContext) {
            return QUOTE_TYPE_GOODWILL;
        }

        return null;
    }

    get trialIdFilter() {
        return this.quickActionMode === 'generate_trial' ? this.recordId : null;
    }

    get sampleIdFilter() {
        return this.quickActionMode === 'generate_sample' ? this.recordId : null;
    }

    get excludeForecastIneligibleForModal() {
        return !this.isTypedQuoteQuickAction;
    }

    get existingQuotesModalHeading() {
        if (this.typedQuoteLabel) {
            return `${this.typedQuoteLabel} Quotes Already Exist for This Opportunity`;
        }

        return 'Quotes Already Exist for This Opportunity';
    }

    get existingQuotesModalSubtext() {
        if (this.typedQuoteLabel) {
            const quoteLabel = this.typedQuoteLabel.toLowerCase();
            return `One or more ${quoteLabel} quotes already exist for this Opportunity. You can generate another ${quoteLabel} quote or cancel.`;
        }

        return 'One or more quotes already exist for this Opportunity. You can generate another quote or cancel.';
    }

    get existingQuotesModalIntro() {
        if (this.typedQuoteLabel) {
            return `This opportunity already has associated ${this.typedQuoteLabel.toLowerCase()} quote(s).`;
        }

        return 'This opportunity already has associated quote(s).';
    }

    get generateNewQuoteButtonLabel() {
        if (this.typedQuoteLabel) {
            return `Generate New ${this.typedQuoteLabel} Quote`;
        }

        return 'Generate New Quote';
    }

    get isQuickAction() {
        return Boolean(this.launchMode) || this.actionModeFromPageRef !== null;
    }

    get modalShellClass() {
        return this.isQuickAction ? 'qa-panel' : 'slds-modal slds-fade-in-open';
    }

    get modalHeaderClass() {
        return this.isQuickAction ? 'qa-panel__header' : 'slds-modal__header';
    }

    get existingQuotesContainerClass() {
        return this.isQuickAction
            ? 'qa-panel__container existing-quotes-modal'
            : 'slds-modal__container existing-quotes-modal';
    }

    get existingQuotesBodyClass() {
        const padding = 'slds-p-around_large';
        return this.isQuickAction
            ? `qa-panel__body ${padding} existing-quotes-modal-content`
            : `slds-modal__content ${padding} existing-quotes-modal-content`;
    }

    get existingQuotesFooterClass() {
        return this.isQuickAction
            ? 'qa-panel__footer existing-quotes-modal-footer'
            : 'slds-modal__footer existing-quotes-modal-footer';
    }

    get quickActionRootClass() {
        return this.isQuickAction ? 'quick-action-content' : '';
    }

    get showQuickActionLoading() {
        return this.isQuickAction && this.isLoading && !this.showExistingQuotesModal;
    }

    tryInitialize() {
        if (this.initialized) {
            return;
        }

        if (this.effectiveRecordPageContext) {
            if (this.isContextRecordLoading || this.hasContextRecordError || !this.contextOpportunityId) {
                return;
            }
        } else if (!this.opportunityIdForQuoteOperations) {
            return;
        }

        if (this.isQuickAction) {
            this.initialized = true;
            this.runQuickActionEntryPoint();
            return;
        }

        this.initialized = true;
        this.loadQuotesForRecordPage();
    }

    loadQuotesForRecordPage() {
        this.loadData().catch((error) => {
            this.showToast('Error', this.reduceError(error), 'error');
        });
    }

    async runQuickActionEntryPoint() {
        try {
            if (this.quickActionMode === 'refresh') {
                if (!(await this.ensureQuoteAccess())) {
                    return;
                }

                await this.refreshQuotesFromIntegration(true);
                this.closeQuickActionPanel();
                return;
            }

            if (
                this.quickActionMode === 'generate' ||
                this.quickActionMode === 'generate_trial' ||
                this.quickActionMode === 'generate_sample'
            ) {
                await this.handleGenerateQuote();
                return;
            }

            if (this.quickActionMode === 'copy' || this.quickActionMode === 'merge') {
                await this.handleShellQuoteRequest();
            }
        } catch (error) {
            this.showToast('Error', this.reduceError(error), 'error');
            if (this.isQuickAction) {
                this.closeQuickActionPanel(false);
            }
        }
    }

    closeQuickActionPanel(refreshRecordPage = true) {
        if (!this.isQuickAction) {
            return;
        }

        if (refreshRecordPage) {
            this.notifyOpportunityRecordRefresh();
            this.notifyRecordPageRefresh();
        }

        this.dispatchEvent(
            new CustomEvent('closequickaction', {
                bubbles: true,
                composed: true,
                detail: { refresh: refreshRecordPage }
            })
        );
        if (this.launchMode && !this.actionModeFromPageRef) {
            this.dispatchEvent(new FlowNavigationFinishEvent());
        }
    }

    get quoteCount() {
        return this.allQuotes.length;
    }

    get paginatedQuotes() {
        const startIndex = (this.currentPage - 1) * QUOTES_PAGE_SIZE;
        return this.allQuotes.slice(startIndex, startIndex + QUOTES_PAGE_SIZE);
    }

    get hasQuotes() {
        return this.allQuotes.length > 0;
    }

    get showRefreshQuoteButton() {
        if (!this.wiredOpportunity?.data) {
            return false;
        }

        const quoteCount = getFieldValue(this.wiredOpportunity.data, OPPORTUNITY_QUOTE_COUNT);
        return Number(quoteCount || 0) > 0;
    }

    get totalPages() {
        return Math.max(1, Math.ceil(this.allQuotes.length / QUOTES_PAGE_SIZE));
    }

    get showPagination() {
        return this.allQuotes.length > QUOTES_PAGE_SIZE;
    }

    get disablePreviousPage() {
        return this.currentPage <= 1;
    }

    get disableNextPage() {
        return this.currentPage >= this.totalPages;
    }

    get paginationSummary() {
        if (!this.hasQuotes) {
            return '';
        }

        const startIndex = (this.currentPage - 1) * QUOTES_PAGE_SIZE + 1;
        const endIndex = Math.min(this.currentPage * QUOTES_PAGE_SIZE, this.allQuotes.length);
        return `Showing ${startIndex}-${endIndex} of ${this.allQuotes.length}`;
    }

    get showHeaderActions() {
        return this.isDealerPortal !== true;
    }

    get headerColumnCount() {
        return this.isDealerPortal === true ? 6 : 8;
    }

    get groupColumnLabel() {
        return this.groupBySalesCategory ? 'Sales Category' : 'Product Subgroup Detail Name';
    }

    get psamGroupingButtonClass() {
        return this.groupBySalesCategory
            ? 'slds-button slds-button_neutral grouping-toggle-btn'
            : 'slds-button slds-button_brand grouping-toggle-btn';
    }

    get salesCategoryGroupingButtonClass() {
        return this.groupBySalesCategory
            ? 'slds-button slds-button_brand grouping-toggle-btn'
            : 'slds-button slds-button_neutral grouping-toggle-btn';
    }

    handleSelectPsamGrouping() {
        if (!this.groupBySalesCategory) {
            return;
        }

        this.groupBySalesCategory = false;
        this.allQuotes = this.allQuotes.map((quote) => this.applyActiveGroupingSummary(quote));
    }

    handleSelectSalesCategoryGrouping() {
        if (this.groupBySalesCategory) {
            return;
        }

        this.groupBySalesCategory = true;
        this.allQuotes = this.allQuotes.map((quote) => this.applyActiveGroupingSummary(quote));
    }

    enrichGroupingSummary(quote, summaryRows, summaryPrefix, showPricing) {
        return (summaryRows || []).map((subgroup, subgroupIndex) => {
            const quoteLines = (subgroup.quoteLines || []).map((line, lineIndex) => {
                const recordId = line.id || null;

                return {
                    ...line,
                    rowKey:
                        recordId ||
                        `${subgroup.id || quote.id}-${summaryPrefix}-${subgroupIndex}-line-${lineIndex}`,
                    recordId,
                    productCode: line.productCode || '',
                    recordUrl: this.buildQuoteLineRecordUrl(recordId),
                    hasRecordLink: this.isDealerPortal === true ? false : !!recordId,
                    uomDisplay: this.formatUom(line.uom),
                    quantityFormatted: this.formatQuantity(line.quantity),
                    unitPriceFormatted: showPricing ? this.formatCurrency(line.unitPrice) : '',
                    lineTotalFormatted: showPricing ? this.formatCurrency(line.lineTotal) : ''
                };
            });

            return {
                ...subgroup,
                id: subgroup.id || `${quote.id}-${summaryPrefix}-${subgroupIndex}`,
                // GC-3292: default to expanded when quotes are (re)loaded
                isExpanded: true,
                lineIcon: 'utility:chevrondown',
                totalUnitPriceFormatted: showPricing ? this.formatCurrency(subgroup.totalUnitPrice) : '',
                quoteLines,
                hasQuoteLines: quoteLines.length > 0,
                linesKey: subgroup.linesKey || `${quote.id}-${summaryPrefix}-${subgroupIndex}-lines`
            };
        });
    }

    applyActiveGroupingSummary(quote) {
        const activeSummary = this.groupBySalesCategory
            ? quote.salesCategorySummary
            : quote.psamSubgroupSummary;

        // GC-3292: default to expanded when switching between Product Subgroup / Sales Category
        const expandedSummary = (activeSummary || []).map((subgroup) => ({
            ...subgroup,
            isExpanded: true,
            lineIcon: 'utility:chevrondown'
        }));

        return {
            ...quote,
            isExpanded: true,
            icon: 'utility:chevrondown',
            productSubgroupSummary: expandedSummary,
            hasNoProductSubgroupSummary: !activeSummary || activeSummary.length === 0
        };
    }

    buildQuoteViewModel(quote) {
        const salesConnectionUrl = this.isDealerPortal === true ? '' : (quote.salesConnectionUrl || '');
        const showPricing = this.isDealerPortal !== true || this.isApprovedStatus(quote.approvalStatus);
        const psamSubgroupSummary = this.enrichGroupingSummary(
            quote,
            quote.productSubgroupSummary,
            'psam-subgroup',
            showPricing
        );
        const salesCategorySummary = this.enrichGroupingSummary(
            quote,
            quote.salesCategorySummary,
            'sales-category',
            showPricing
        );
        const activeSummary = this.groupBySalesCategory ? salesCategorySummary : psamSubgroupSummary;

        const isForecastIneligible =
            quote.isForecastIneligible === true ||
            quote.IsForecastIneligible__c === true;
        const hideQuoteForecastConfidence = this.shouldHideQuoteForecastConfidence(quote);
        const forecastIneligibleClass = isForecastIneligible ? ' quote-row--forecast-ineligible' : '';

        const mappedQuote = {
            id: quote.id,
            childKey: `${quote.id}_child`,
            quoteId: quote.salesConnectionViewQuoteNumber || '',
            salesConnectionViewQuoteNumber: quote.salesConnectionViewQuoteNumber || '',
            salesConnectionQuoteId: quote.salesConnectionQuoteId || '',
            quoteName: quote.quoteName || '',
            description: quote.description || '',
            status: quote.status || '—',
            approvalStatus: quote.approvalStatus || '—',
            showPricing,
            lineDetailColspan: showPricing ? 2 : 1,
            totalWithoutFreight: showPricing ? this.formatCurrency(quote.quoteTotalWithoutFreight) : '',
            currencyCode: quote.currencyIsoCode || '',
            lastModifiedDate: this.formatDateTime(quote.lastModifiedDate),
            isForecastIneligible,
            hideQuoteForecastConfidence,
            quoteType: quote.quoteType || '',
            rowClass: `slds-hint-parent${forecastIneligibleClass}`,
            childRowClass: `child-row${forecastIneligibleClass}`,
            // GC-3292: default to expanded when quotes are (re)loaded
            isExpanded: true,
            icon: 'utility:chevrondown',
            salesConnectionUrl,
            hasSalesConnectionUrl: !!salesConnectionUrl,
            psamSubgroupSummary,
            salesCategorySummary,
            productSubgroupSummary: activeSummary,
            hasNoProductSubgroupSummary: activeSummary.length === 0,
            quoteForecastConfidence: quote.quoteForecastConfidence || '',
            savedQuoteForecastConfidence: quote.quoteForecastConfidence || '',
            opportunityForecastConfidence: quote.opportunityForecastConfidence || '',
            forecastConfidenceDirty: false,
            isSyncingForecastConfidence: false,
            saveForecastConfidenceDisabled: false,
            cancelForecastConfidenceDisabled: true
        };
        return this.withForecastSelectOptions(mappedQuote);
    }

    mapOpportunityForecastToQuoteConfidence(opportunityValue) {
        const normalized = String(opportunityValue || '').trim();
        if (!normalized) {
            return '';
        }
        if (normalized.toLowerCase() === 'make it') {
            return 'Make-It';
        }

        const options = this.forecastConfidenceOptions || [];
        const matchedOption = options.find(
            (option) =>
                option.value.toLowerCase() === normalized.toLowerCase() ||
                option.label.toLowerCase() === normalized.toLowerCase()
        );
        return matchedOption ? matchedOption.value : normalized;
    }

    resolveStoredQuoteForecastConfidence(quote) {
        if (quote?.savedQuoteForecastConfidence !== undefined && quote?.savedQuoteForecastConfidence !== null) {
            return String(quote.savedQuoteForecastConfidence).trim();
        }
        return String(quote?.quoteForecastConfidence ?? '').trim();
    }

    resolveQuoteForecastConfidenceBaseline(quote) {
        const stored = this.resolveStoredQuoteForecastConfidence(quote);
        if (stored) {
            return stored;
        }
        return this.mapOpportunityForecastToQuoteConfidence(quote?.opportunityForecastConfidence);
    }

    resolveQuoteForecastConfidenceForDisplay(quote) {
        if (quote?.hideQuoteForecastConfidence) {
            return '';
        }
        return this.resolveQuoteForecastConfidenceBaseline(quote);
    }

    shouldHideQuoteForecastConfidence(quote) {
        const quoteType = String(quote?.quoteType || '').trim();
        return (
            quoteType === QUOTE_TYPE_TRIAL ||
            quoteType === QUOTE_TYPE_SAMPLE ||
            quoteType === QUOTE_TYPE_GOODWILL
        );
    }

    buildForecastConfidenceSelectOptions(selectedValue) {
        const normalizedSelected = String(selectedValue || '').trim();
        const options = (this.forecastConfidenceOptions || []).map((option) => ({
            value: option.value,
            label: option.label,
            isSelected: option.value === normalizedSelected
        }));

        if (!normalizedSelected) {
            return options;
        }

        const hasSelected = options.some((option) => option.value === normalizedSelected);
        if (!hasSelected) {
            options.push({
                value: normalizedSelected,
                label: normalizedSelected,
                isSelected: true
            });
        }

        return options;
    }

    withForecastSelectOptions(quote) {
        if (quote.hideQuoteForecastConfidence) {
            return {
                ...quote,
                quoteForecastConfidence: '',
                forecastConfidenceSelectKey: `${quote.id}-forecast-hidden`,
                forecastConfidenceSelectOptions: [],
                forecastConfidenceDirty: false,
                saveForecastConfidenceDisabled: true,
                cancelForecastConfidenceDisabled: true
            };
        }

        const storedValue = this.resolveStoredQuoteForecastConfidence(quote);
        const displayValue = quote.forecastConfidenceDirty
            ? String(quote.quoteForecastConfidence ?? '').trim()
            : this.resolveQuoteForecastConfidenceForDisplay({
                  ...quote,
                  savedQuoteForecastConfidence: storedValue || quote.savedQuoteForecastConfidence
              });
        const optionsLength = (this.forecastConfidenceOptions || []).length;
        const selectRevision = quote.forecastConfidenceSelectRevision ?? 0;

        return {
            ...quote,
            quoteForecastConfidence: displayValue,
            savedQuoteForecastConfidence: storedValue,
            forecastConfidenceSelectKey: `${quote.id}-${displayValue}-${optionsLength}-${selectRevision}`,
            forecastConfidenceSelectOptions: this.buildForecastConfidenceSelectOptions(displayValue)
        };
    }

    handleForecastConfidenceChange(event) {
        const quoteId = event.currentTarget?.dataset?.id;
        const selectedValue = event.detail?.value || event.currentTarget?.value || '';

        if (!quoteId) {
            return;
        }

        this.allQuotes = this.allQuotes.map((quote) => {
            if (!this.isSameRecordId(quote.id, quoteId)) {
                return quote;
            }

            if (quote.hideQuoteForecastConfidence) {
                return quote;
            }

            const baselineValue = this.resolveQuoteForecastConfidenceBaseline(quote);
            const isDirty = selectedValue !== baselineValue;
            return this.withForecastSelectOptions({
                ...quote,
                quoteForecastConfidence: selectedValue,
                pendingQuoteForecastConfidence: selectedValue,
                forecastConfidenceDirty: isDirty,
                cancelForecastConfidenceDisabled: !isDirty
            });
        });
    }

    handleCancelForecastConfidence(event) {
        const quoteId = event.currentTarget?.dataset?.id;

        if (!quoteId) {
            return;
        }

        this.allQuotes = this.allQuotes.map((quote) => {
            if (!this.isSameRecordId(quote.id, quoteId)) {
                return quote;
            }

            const selectRevision = (quote.forecastConfidenceSelectRevision ?? 0) + 1;
            const baselineValue = this.resolveQuoteForecastConfidenceBaseline(quote);

            return this.withForecastSelectOptions({
                ...quote,
                quoteForecastConfidence: baselineValue,
                pendingQuoteForecastConfidence: undefined,
                forecastConfidenceDirty: false,
                cancelForecastConfidenceDisabled: true,
                saveForecastConfidenceDisabled: false,
                forecastConfidenceSelectRevision: selectRevision
            });
        });
    }

    async handleSaveForecastConfidence(event) {
        const quoteId = event.currentTarget?.dataset?.id;
        const opportunityId = this.opportunityIdForQuoteOperations;

        if (!quoteId || !opportunityId) {
            return;
        }

        const quoteRow = this.allQuotes.find((quote) => this.isSameRecordId(quote.id, quoteId));
        if (!quoteRow) {
            return;
        }

        if (quoteRow.hideQuoteForecastConfidence) {
            return;
        }

        const valueToSave =
            quoteRow.pendingQuoteForecastConfidence ?? quoteRow.quoteForecastConfidence ?? '';
        if (!valueToSave) {
            this.showToast('Error', 'Select a Quote Forecast Confidence value.', 'error');
            return;
        }

        this.setQuoteRowSyncState(quoteId, true);

        try {
            const updatedQuote = await syncQuoteForecastConfidence({
                opportunityId,
                quoteId,
                quoteForecastConfidence: valueToSave,
                syncFromOpportunity: false
            });

            if (!updatedQuote) {
                this.showToast('Error', 'Quote Forecast Confidence could not be saved.', 'error');
                return;
            }

            this.allQuotes = this.allQuotes.map((quote) => {
                if (!this.isSameRecordId(quote.id, quoteId)) {
                    return quote;
                }

                const savedValue = updatedQuote.quoteForecastConfidence || valueToSave;
                return this.withForecastSelectOptions({
                    ...quote,
                    quoteForecastConfidence: savedValue,
                    savedQuoteForecastConfidence: savedValue,
                    pendingQuoteForecastConfidence: undefined,
                    opportunityForecastConfidence: updatedQuote.opportunityForecastConfidence || '',
                    forecastConfidenceDirty: false,
                    cancelForecastConfidenceDisabled: true
                });
            });

            this.showToast('Success', 'Quote Forecast Confidence was saved.', 'success');
        } catch (error) {
            this.showToast('Error', this.reduceError(error), 'error');
        } finally {
            this.setQuoteRowSyncState(quoteId, false);
        }
    }

    setQuoteRowSyncState(quoteId, isSyncing) {
        this.allQuotes = this.allQuotes.map((quote) => {
            const confidenceActionDisabled = isSyncing;

            if (!this.isSameRecordId(quote.id, quoteId)) {
                return {
                    ...quote,
                    saveForecastConfidenceDisabled: confidenceActionDisabled,
                    cancelForecastConfidenceDisabled:
                        confidenceActionDisabled || !quote.forecastConfidenceDirty
                };
            }

            return {
                ...quote,
                isSyncingForecastConfidence: isSyncing,
                saveForecastConfidenceDisabled: confidenceActionDisabled,
                cancelForecastConfidenceDisabled:
                    confidenceActionDisabled || !quote.forecastConfidenceDirty
            };
        });
    }

    isSameRecordId(firstId, secondId) {
        if (!firstId || !secondId) {
            return false;
        }

        return String(firstId).toLowerCase() === String(secondId).toLowerCase();
    }

    // GC-3292 START: Expand/Collapse All controls for Quote and Product Subgroup accordion rows
    get disableExpandCollapseControls() {
        return this.isLoading || !this.hasQuotes;
    }

    get isFullyExpanded() {
        return (
            this.hasQuotes &&
            this.allQuotes.every(
                (quote) =>
                    quote.isExpanded &&
                    (quote.productSubgroupSummary || []).every((subgroup) => subgroup.isExpanded)
            )
        );
    }

    get isFullyCollapsed() {
        return (
            this.hasQuotes &&
            this.allQuotes.every(
                (quote) =>
                    !quote.isExpanded &&
                    (quote.productSubgroupSummary || []).every((subgroup) => !subgroup.isExpanded)
            )
        );
    }

    get disableExpandAll() {
        return this.disableExpandCollapseControls || this.isFullyExpanded;
    }

    get disableCollapseAll() {
        return this.disableExpandCollapseControls || this.isFullyCollapsed;
    }

    handleExpandAll() {
        this.allQuotes = this.allQuotes.map((quote) => this.setQuoteExpansion(quote, true));
    }

    handleCollapseAll() {
        this.allQuotes = this.allQuotes.map((quote) => this.setQuoteExpansion(quote, false));
    }

    setQuoteExpansion(quote, expanded) {
        return {
            ...quote,
            isExpanded: expanded,
            icon: expanded ? 'utility:chevrondown' : 'utility:chevronright',
            productSubgroupSummary: (quote.productSubgroupSummary || []).map((subgroup) => ({
                ...subgroup,
                isExpanded: expanded,
                lineIcon: expanded ? 'utility:chevrondown' : 'utility:chevronright'
            }))
        };
    }
    // GC-3292 END

    toggleRow(event) {
        const id = event.currentTarget.dataset.id;

        this.allQuotes = this.allQuotes.map((quote) => {
            if (quote.id !== id) {
                return quote;
            }

            const expanded = !quote.isExpanded;
            return {
                ...quote,
                isExpanded: expanded,
                icon: expanded ? 'utility:chevrondown' : 'utility:chevronright'
            };
        });
    }

    toggleSubgroup(event) {
        const quoteId = event.currentTarget.dataset.quoteId;
        const subgroupId = event.currentTarget.dataset.subgroupId;

        this.allQuotes = this.allQuotes.map((quote) => {
            if (quote.id !== quoteId) {
                return quote;
            }

            return {
                ...quote,
                productSubgroupSummary: quote.productSubgroupSummary.map((subgroup) => {
                    if (subgroup.id !== subgroupId) {
                        return subgroup;
                    }

                    const expanded = !subgroup.isExpanded;
                    return {
                        ...subgroup,
                        isExpanded: expanded,
                        lineIcon: expanded ? 'utility:chevrondown' : 'utility:chevronright'
                    };
                })
            };
        });
    }

    async loadData(options = {}) {
        const { showSpinner = true } = options;

        if (!this.opportunityIdForQuoteOperations) {
            return;
        }

        const requestId = ++this.loadRequestId;

        if (showSpinner) {
            this.isLoading = true;
        }

        try {
            const result = await getQuotes({
                opportunityId: this.opportunityIdForQuoteOperations,
                quoteTypeFilter: null,
                excludeForecastIneligible: false,
                trialIdFilter: this.trialIdFilter,
                sampleIdFilter: this.sampleIdFilter,
                forDealerPortal: this.isDealerPortal === true
            });

            if (requestId !== this.loadRequestId) {
                return;
            }

            this.setQuotesFromResult(result || []);
            this.notifyOpportunityRecordRefresh();
        } catch (error) {
            if (requestId === this.loadRequestId) {
                this.showToast('Error', this.reduceError(error), 'error');
            }
            throw error;
        } finally {
            if (showSpinner && requestId === this.loadRequestId) {
                this.isLoading = false;
            }
        }
    }

    async loadModalQuotes() {
        if (!this.opportunityIdForQuoteOperations) {
            this.modalQuotes = [];
            return;
        }

        const result = await getQuotes({
            opportunityId: this.opportunityIdForQuoteOperations,
            quoteTypeFilter: this.quoteTypeFilter,
            excludeForecastIneligible: this.excludeForecastIneligibleForModal,
            trialIdFilter: this.trialIdFilter,
            sampleIdFilter: this.sampleIdFilter,
            forDealerPortal: this.isDealerPortal === true
        });

        this.modalQuotes = (result || []).map((quote) => this.buildQuoteViewModel(quote));
    }

    async handleGenerateQuote() {
        if (!(await this.ensureQuoteAccess())) {
            return;
        }

        this.isLoading = true;

        try {
            await this.loadModalQuotes();

            if (this.modalQuotes.length > 0) {
                this.showExistingQuotesModal = true;
                return;
            }

            await this.generateQuoteRecord();
        } finally {
            this.isLoading = false;
        }
    }

    async handleGenerateNewQuote() {
        this.showExistingQuotesModal = false;
        await this.generateQuoteRecord();
    }

    async handleShellQuoteRequest() {
        if (!(await this.ensureQuoteAccess())) {
            return;
        }

        this.isLoading = true;

        try {
            const apexMethod = this.quickActionMode === 'merge' ? mergeQuote : copyQuote;
            const result = await apexMethod({
                opportunityId: this.opportunityIdForQuoteOperations
            });

            if (this.isQuickAction) {
                this.notifyRecordPageRefresh();
            }

            if (result?.salesConnectionUrl) {
                this.openUrlInNewTab(result.salesConnectionUrl);
                if (this.isQuickAction) {
                    this.closeQuickActionPanel();
                }
            } else {
                this.showToast(
                    'Error',
                    'Sales Connection URL is not available. Verify endpoint settings and the Account Oracle Address Id.',
                    'error'
                );
                if (this.isQuickAction) {
                    this.closeQuickActionPanel(false);
                }
            }
        } catch (error) {
            this.showToast('Error', this.reduceError(error), 'error');
            if (this.isQuickAction) {
                this.closeQuickActionPanel(false);
            }
        } finally {
            this.isLoading = false;
        }
    }

    async generateQuoteRecord() {
        this.isLoading = true;

        try {
            const result = await createQuote({
                opportunityId: this.opportunityIdForQuoteOperations,
                quoteType: this.resolvedQuoteType,
                trialId: this.trialIdFilter,
                sampleId: this.sampleIdFilter
            });

            if (result.salesConnectionUrl) {
                this.openUrlInNewTab(result.salesConnectionUrl);
                if (this.isQuickAction) {
                    this.notifyRecordPageRefresh();
                    this.closeQuickActionPanel();
                }
            } else {
                this.showToast(
                    'Error',
                    'Sales Connection URL is not available. Verify the Sales Connection Quote Id and endpoint settings, or the Account Oracle Address Id for new quotes.',
                    'error'
                );
                if (this.isQuickAction) {
                    this.closeQuickActionPanel(false);
                }
            }
        } catch (error) {
            this.showToast('Error', this.reduceError(error), 'error');
            if (this.isQuickAction) {
                this.closeQuickActionPanel(false);
            }
        } finally {
            this.isLoading = false;
        }
    }

    async handleRefreshQuote() {
        if (!(await this.ensureQuoteAccess())) {
            return;
        }

        await this.refreshQuotesFromIntegration(true);
    }

    async refreshQuotesFromIntegration(showSuccessToast = false) {
        if (!this.opportunityIdForQuoteOperations) {
            return;
        }

        const requestId = ++this.loadRequestId;
        this.isLoading = true;

        try {
            await refreshQuotes({ opportunityId: this.opportunityIdForQuoteOperations });

            if (requestId !== this.loadRequestId) {
                return;
            }

            if (showSuccessToast) {
                this.showToast('Success', this.refreshQuoteSuccessMessage, 'success');
            }
        } catch (error) {
            if (requestId === this.loadRequestId) {
                this.showToast('Error', this.reduceError(error), 'error');
            }
            throw error;
        } finally {
            if (requestId === this.loadRequestId) {
                this.isLoading = false;
            }
        }
    }

    async ensureQuoteAccess() {
        if (!this.opportunityIdForQuoteOperations) {
            if (this.isQuickAction) {
                this.closeQuickActionPanel(false);
            }
            return false;
        }

        try {
            await validateQuoteAccess({ opportunityId: this.opportunityIdForQuoteOperations });
            return true;
        } catch (error) {
            this.showToast('Error', this.reduceError(error), 'error');
            if (this.isQuickAction) {
                this.closeQuickActionPanel(false);
            }
            return false;
        }
    }

    async closeExistingQuotesModal() {
        this.showExistingQuotesModal = false;
        await this.loadData().catch(() => {});
        this.closeQuickActionPanel();
    }

    setQuotesFromResult(quotesResult, options = {}) {
        const { resetPage = true } = options;
        const rawQuotes = quotesResult || [];

        this.allQuotes = rawQuotes.map((quote) => this.buildQuoteViewModel(quote));

        if (resetPage) {
            this.currentPage = 1;
        } else {
            this.currentPage = this.clampPage(this.currentPage);
        }
    }

    clampPage(page) {
        return Math.min(Math.max(1, page), this.totalPages);
    }

    handlePreviousPage() {
        if (!this.disablePreviousPage) {
            this.currentPage -= 1;
        }
    }

    handleNextPage() {
        if (!this.disableNextPage) {
            this.currentPage += 1;
        }
    }

    findQuoteRecord(quoteId) {
        return (
            (this.modalQuotes || []).find((quote) => quote.id === quoteId) ||
            (this.allQuotes || []).find((quote) => quote.id === quoteId)
        );
    }

    async handleQuoteLinkClick(event) {
        const quoteId = event.currentTarget.dataset.id;
        const quoteRecord = this.findQuoteRecord(quoteId);

        if (quoteRecord?.salesConnectionUrl) {
            this.openUrlInNewTab(quoteRecord.salesConnectionUrl);
            return;
        }

        if (quoteRecord?.salesConnectionQuoteId) {
            try {
                const salesConnectionUrl = await getSalesConnectionQuoteUrl({
                    salesConnectionQuoteId: quoteRecord.salesConnectionQuoteId
                });

                if (salesConnectionUrl) {
                    this.openUrlInNewTab(salesConnectionUrl);
                    return;
                }
            } catch (error) {
                this.showToast('Error', this.reduceError(error), 'error');
                return;
            }
        }

        this.showToast(
            'Error',
            'Sales Connection URL is not available. Verify the Sales Connection Quote Id and endpoint settings, or the Account Oracle Address Id for new quotes.',
            'error'
        );
    }

    buildQuoteLineRecordUrl(recordId) {
        if (!recordId) {
            return null;
        }

        const recordPath = `/lightning/r/QuoteLineItem/${recordId}/view`;

        if (typeof window !== 'undefined' && window.location?.origin) {
            return `${window.location.origin}${recordPath}`;
        }

        return recordPath;
    }

    handleSalesConnectionLinkClick(event) {
        event.preventDefault();
        const targetUrl = event.currentTarget.dataset.url;

        if (!targetUrl) {
            this.showToast(
                'Error',
                'Sales Connection URL is not available. Verify the Sales Connection Quote Id and endpoint settings, or the Account Oracle Address Id for new quotes.',
                'error'
            );
            return;
        }

        this.openUrlInNewTab(targetUrl);
    }

    openUrlInNewTab(url) {
        if (!url) {
            return;
        }

        const resolvedUrl =
            url.startsWith('http://') || url.startsWith('https://')
                ? url
                : `${window.location.origin}${url.startsWith('/') ? '' : '/'}${url}`;

        window.open(resolvedUrl, '_blank', 'noopener,noreferrer');
    }

    formatUom(value) {
        if (value === null || value === undefined || value === '') {
            return '—';
        }

        return value;
    }

    formatDateTime(dateValue) {
        if (!dateValue) {
            return '—';
        }

        try {
            const dt = new Date(dateValue);
            return new Intl.DateTimeFormat('en-US', {
                year: 'numeric',
                month: 'numeric',
                day: 'numeric',
                hour: 'numeric',
                minute: '2-digit',
                hour12: true
            }).format(dt);
        } catch (e) {
            return dateValue;
        }
    }

    formatCurrency(value) {
        if (value === null || value === undefined || value === '') {
            return '—';
        }

        const num = Number(value);
        if (Number.isNaN(num)) {
            return value;
        }

        return new Intl.NumberFormat('en-US', {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        }).format(num);
    }

    isApprovedStatus(approvalStatus) {
        return String(approvalStatus || '').trim().toLowerCase() === 'approved';
    }

    formatQuantity(value) {
        const num = Number(value);
        if (Number.isNaN(num) || num <= 0) {
            return '1';
        }

        return new Intl.NumberFormat('en-US', {
            maximumFractionDigits: 2
        }).format(num);
    }

    reduceError(error) {
        if (!error) {
            return 'Unknown error';
        }

        if (Array.isArray(error.body)) {
            return error.body.map((e) => e.message).join(', ');
        }

        if (error.body && typeof error.body.message === 'string') {
            return error.body.message;
        }

        if (typeof error.message === 'string') {
            return error.message;
        }

        return 'Unexpected error occurred';
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
}