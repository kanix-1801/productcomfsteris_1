/**
 * @description GW-6456 - IMS Covered Equipment card for the RCA product configurator (IMS Service Agreement):
 * which devices the service covers.
 * - Toggle "Include the opportunity's devices": the inventory groups uploaded for the quote's opportunity
 *   (OpportunityAsset__c) are covered.
 * - Manage: step 1 picks the groups (imsInventoryGroupPicker), step 2 unticks devices / adds account assets
 *   (imsAssetPicker).
 * The selection is written into the configuration as JSON (QuoteLineItem.ImsAssetSelection__c via a ContextFields
 * update, like imsProductConfigurator does with ModelQtyCoverage__c), so it is saved with the configuration and
 * Cancel throws it away. ContractAsset__c rows are built from it later, at contract creation
 * (ImsAssetAssignmentService.buildContractAssets).
 */
import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { publish, subscribe, unsubscribe, MessageContext, APPLICATION_SCOPE } from 'lightning/messageService';
import CONFIGURATOR_CHANNEL from '@salesforce/messageChannel/lightning__productConfigurator_notification';
import getAttributeIds from '@salesforce/apex/EsServiceProductConfigController.getAttributeIds';
import getAssignmentContext from '@salesforce/apex/ImsAssetAssignmentController.getAssignmentContext';
import ImsInventoryGroupPicker from 'c/imsInventoryGroupPicker';
import ImsAssetPicker from 'c/imsAssetPicker';
import { formatCount } from 'c/assetPickerUtils';

const SELECTION_FIELD = 'ImsAssetSelection__c';
const SELECTION_VERSION = 1;

// A real, saved Quote Line Item Id. New lines in the configurator have temporary "ref_" Ids.
const isSavedLineId = (id) => typeof id === 'string' && id.startsWith('0QL') && (id.length === 15 || id.length === 18);
const lower = (value) => String(value ?? '').trim().toLowerCase();
const reduceError = (e) => e?.body?.message || e?.message || 'Unexpected error.';

export default class ImsCoveredEquipment extends LightningElement {
    // configuratorContext > transactionLineId: the configuration's root line
    @api rootTransactionLineId;
    // configuratorContext > transactionId: the Quote
    @api transactionId;
    // S01_DataManager > header > id (kept for flow mapping parity with imsProductConfigurator)
    @api currentProductId;
    // S01_DataManager > header > name: the product on screen
    @api currentProductName;
    // Comma-separated product names the card is shown for (blank = every product). Keep the component visible in
    // the flow and filter here: it must stay on the screen to receive the configurator's "navigate" messages.
    @api allowedProducts;

    // configuratorContext > currentTransactionLineId: the line the configurator opened on
    @api
    get currentTransactionLineId() {
        return this._currentLineId;
    }
    set currentTransactionLineId(value) {
        this._currentLineId = value;
        this.loadLine(this.lineId);
    }

    _currentLineId;
    currentKey; // line path from the configurator's "navigate" messages
    subscription;
    attributeId;

    context; // quote / opportunity / inventory groups (same for every line)
    savedByLine = {}; // selection JSON saved on the record, by line id (null = nothing saved)
    sessionByLine = {}; // selections committed this session (saved with the configuration)
    loadingLines = {};
    isManaging = false;
    errorMessage;

    @wire(MessageContext) messageContext;

    connectedCallback() {
        if (!this.subscription) {
            this.subscription = subscribe(
                this.messageContext,
                CONFIGURATOR_CHANNEL,
                (message) => this.handleMessage(message),
                { scope: APPLICATION_SCOPE }
            );
        }
        this.loadAttributeId();
        this.loadLine(this.lineId);
    }

    disconnectedCallback() {
        unsubscribe(this.subscription);
        this.subscription = null;
    }

    handleMessage(message) {
        if (message?.action === 'navigate' && Array.isArray(message.key) && message.key.length) {
            this.currentKey = [...message.key];
            this.loadLine(this.lineId);
        }
    }

    /* =====================  LINE ON SCREEN  ===================== */

    // Path of line ids to the line on screen: [root] or [root, child line] (same rules as imsProductConfigurator)
    get key() {
        if (this.currentKey?.length) return this.currentKey;
        const root = this.rootTransactionLineId;
        const current = this._currentLineId;
        if (root && current && current !== root) return [root, current];
        const only = current || root;
        return only ? [only] : [];
    }

    get lineId() {
        const k = this.key;
        return k.length ? k[k.length - 1] : null;
    }

    get isAllowedProduct() {
        const allowed = (this.allowedProducts || '')
            .split(',')
            .map((name) => lower(name))
            .filter(Boolean);
        return !allowed.length || allowed.includes(lower(this.currentProductName));
    }

    async loadAttributeId() {
        try {
            const ids = await getAttributeIds({ fieldNames: [SELECTION_FIELD] });
            this.attributeId = ids?.[SELECTION_FIELD];
        } catch {
            // Non-fatal: commit shows "Missing context attribute Id" if it is still unset.
        }
    }

    // Context (once) and the selection saved on the line (once per saved line)
    async loadLine(lineId) {
        if (!this.transactionId) return;
        const key = lineId || '';
        const needsLine = isSavedLineId(lineId) && !(lineId in this.savedByLine);
        if ((this.context && !needsLine) || this.loadingLines[key]) return;
        this.loadingLines = { ...this.loadingLines, [key]: true };
        this.errorMessage = null;
        try {
            const ctx = await getAssignmentContext({
                quoteId: this.transactionId,
                lineId: isSavedLineId(lineId) ? lineId : null
            });
            this.context = ctx;
            if (isSavedLineId(lineId)) {
                this.savedByLine = { ...this.savedByLine, [lineId]: ctx?.savedSelection || null };
            }
        } catch (e) {
            this.errorMessage = reduceError(e);
        } finally {
            const next = { ...this.loadingLines };
            delete next[key];
            this.loadingLines = next;
        }
    }

    get isLoading() {
        return !this.context && Object.keys(this.loadingLines).length > 0;
    }

    /* =====================  SELECTION  ===================== */

    get groups() {
        return this.context?.groups || [];
    }

    // Default before the rep changes anything: opportunity devices included, every group, nothing removed/added
    get defaultSelection() {
        return {
            version: SELECTION_VERSION,
            opportunityId: this.context?.opportunityId || null,
            includeOpportunityAssets: true,
            groups: this.groups.map((g) => g.name),
            removedAssetIds: [],
            addedAssetIds: []
        };
    }

    // This session's value first, then the JSON saved on the line, then the default
    get selection() {
        const lineId = this.lineId;
        const session = lineId ? this.sessionByLine[lineId] : null;
        if (session) return session;
        const raw = lineId ? this.savedByLine[lineId] : null;
        if (raw) {
            try {
                const parsed = JSON.parse(raw);
                return {
                    ...this.defaultSelection,
                    ...parsed,
                    groups: Array.isArray(parsed.groups) ? parsed.groups : [],
                    removedAssetIds: Array.isArray(parsed.removedAssetIds) ? parsed.removedAssetIds : [],
                    addedAssetIds: Array.isArray(parsed.addedAssetIds) ? parsed.addedAssetIds : [],
                    includeOpportunityAssets: parsed.includeOpportunityAssets !== false
                };
            } catch {
                // unreadable JSON: show the default
            }
        }
        return this.defaultSelection;
    }

    get isPendingSave() {
        return !!(this.lineId && this.sessionByLine[this.lineId]);
    }

    get hasOpportunity() {
        return !!this.context?.opportunityId;
    }

    get hasGroups() {
        return this.groups.length > 0;
    }

    // Devices in the chosen groups (as uploaded)
    get groupDeviceCount() {
        const chosen = new Set(this.selection.groups);
        return this.groups.filter((g) => chosen.has(g.name)).reduce((sum, g) => sum + (g.deviceCount || 0), 0);
    }

    get counts() {
        const s = this.selection;
        const opportunity = s.includeOpportunityAssets
            ? Math.max(this.groupDeviceCount - s.removedAssetIds.length, 0)
            : 0;
        const added = s.addedAssetIds.length;
        return { opportunity, added, total: opportunity + added };
    }

    get opportunityAssetsLabel() {
        return formatCount(this.counts.opportunity);
    }

    get addedAssetsLabel() {
        return formatCount(this.counts.added);
    }

    get totalAssetsLabel() {
        return formatCount(this.counts.total);
    }

    get subtitle() {
        if (!this.context) return '';
        if (!this.hasOpportunity) return 'No opportunity on this quote · add assets with Manage';
        const devices = formatCount(this.context.opportunityDeviceCount);
        return `Opportunity ${this.context.opportunityName} · ${devices} devices on the list`;
    }

    get includeChecked() {
        return this.hasGroups && this.selection.includeOpportunityAssets;
    }

    get toggleDisabled() {
        return !this.hasGroups || this.isManaging || this.isLoading;
    }

    get manageDisabled() {
        return this.isManaging || this.isLoading || !this.context;
    }

    get helpText() {
        if (!this.hasGroups) {
            return 'No inventory has been uploaded for this opportunity. Use Manage to pick assets individually.';
        }
        return this.selection.includeOpportunityAssets
            ? 'The opportunity’s devices are assigned. Use Manage to remove some or add other assets.'
            : 'The opportunity’s devices are not assigned. Only assets added with Manage are covered.';
    }

    /* =====================  ACTIONS  ===================== */

    handleToggle(event) {
        this.commit({ ...this.selection, includeOpportunityAssets: event.target.checked });
    }

    async handleManage() {
        if (this.manageDisabled) return;
        this.isManaging = true;
        try {
            const current = this.selection;
            // Step 1: inventory groups (skipped when the opportunity has none)
            let step1 = { groups: [], includeOpportunityAssets: false };
            if (this.hasGroups) {
                step1 = await ImsInventoryGroupPicker.open({
                    size: 'large',
                    description: 'Assign inventory group',
                    opportunityId: this.context.opportunityId,
                    opportunityName: this.context.opportunityName,
                    groups: this.groups,
                    selectedGroups: current.groups,
                    includeOpportunityAssets: current.includeOpportunityAssets
                });
                if (!step1) return;
            }
            // Step 2: Choose Assets (opened after step 1 closes: modals are not nested)
            const step2 = await ImsAssetPicker.open({
                size: 'full',
                description: 'Choose assets',
                quoteId: this.transactionId,
                opportunityId: this.context.opportunityId,
                opportunityName: this.context.opportunityName,
                productName: this.currentProductName || 'SERVICE AGREEMENT',
                groups: step1.groups,
                includeOpportunityAssets: step1.includeOpportunityAssets,
                removedAssetIds: current.removedAssetIds,
                addedAssetIds: current.addedAssetIds
            });
            if (!step2) return;
            this.commit({
                ...current,
                groups: step1.groups,
                includeOpportunityAssets: step1.includeOpportunityAssets,
                removedAssetIds: step2.removedAssetIds || [],
                addedAssetIds: step2.addedAssetIds || []
            });
        } catch (e) {
            this.errorMessage = reduceError(e);
        } finally {
            this.isManaging = false;
        }
    }

    // Writes the selection into the configuration (ContextFields update on the line on screen)
    commit(selection) {
        const lineId = this.lineId;
        if (!lineId) {
            this.errorMessage = 'The quote line is not known yet. Close this window and try again.';
            return;
        }
        if (!this.attributeId) {
            this.errorMessage = `Missing context attribute Id for ${SELECTION_FIELD}. Check the context definition.`;
            return;
        }
        this.errorMessage = null;
        const value = {
            version: SELECTION_VERSION,
            opportunityId: this.context?.opportunityId || null,
            includeOpportunityAssets: !!selection.includeOpportunityAssets,
            groups: [...(selection.groups || [])],
            removedAssetIds: [...new Set(selection.removedAssetIds || [])],
            addedAssetIds: [...new Set(selection.addedAssetIds || [])]
        };
        this.sessionByLine = { ...this.sessionByLine, [lineId]: value };
        value.counts = { ...this.counts }; // display only; Apex recomputes from the Ids

        publish(this.messageContext, CONFIGURATOR_CHANNEL, {
            action: 'valueChanged',
            data: [
                {
                    key: [...this.key],
                    field: 'ContextFields',
                    attributeId: this.attributeId,
                    fieldName: SELECTION_FIELD,
                    value: JSON.stringify(value)
                }
            ]
        });
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Covered equipment updated',
                message: 'The devices are stored when the configuration is saved.',
                variant: 'success'
            })
        );
    }
}
