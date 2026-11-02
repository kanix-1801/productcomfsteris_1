import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import findAssetsBySerial from '@salesforce/apex/CreateReturnOrderController.findAssetsBySerial';

export default class ScanSerialReturnOrder extends LightningElement {
    serialInput = '';
    matchedAssets = [];
    selectedAssetId = '';
    selectedAssetIds = [];
    accountErrorMessage = '';
    scanErrorMessage = '';
    isSearching = false;
    showWizard = false;

    get hasMatchedAssets() {
        return this.matchedAssets.length > 0;
    }

    get hasMultipleMatches() {
        return this.matchedAssets.length > 1;
    }

    get isSearchDisabled() {
        return this.isSearching || !String(this.serialInput || '').trim();
    }

    get matchedAssetsDisplay() {
        return (this.matchedAssets || []).map((asset) => ({
            ...asset,
            rowKey: asset.id,
            displayLabel: this.buildAssetLabel(asset)
        }));
    }

    buildAssetLabel(asset) {
        const serial = asset.serialNumber || 'No Serial';
        const product = asset.productName || 'Unknown Product';
        const account = asset.accountName || 'Unknown Account';
        const model = asset.model ? ` | Model: ${asset.model}` : '';
        return `${serial} | ${product}${model} | ${account}`;
    }

    handleSerialChange(event) {
        this.serialInput = event.target.value;
        this.scanErrorMessage = '';
        this.accountErrorMessage = '';
        this.matchedAssets = [];
        this.selectedAssetId = '';
    }

    handleSerialKeyUp(event) {
        if (event.key === 'Enter') {
            event.preventDefault();
            this.handleSearchSerial();
        }
    }

    async handleSearchSerial() {
        const serialNumber = String(this.serialInput || '').trim();
        if (!serialNumber) {
            this.scanErrorMessage = 'Enter or scan a serial number.';
            return;
        }

        this.isSearching = true;
        this.scanErrorMessage = '';
        this.accountErrorMessage = '';
        this.matchedAssets = [];
        this.selectedAssetId = '';
        this.showWizard = false;
        this.selectedAssetIds = [];

        try {
            const assets = await findAssetsBySerial({ serialNumber });
            this.matchedAssets = assets || [];

            if (this.matchedAssets.length === 0) {
                this.scanErrorMessage = `No assets found for serial "${serialNumber}".`;
                return;
            }

            if (this.matchedAssets.length === 1) {
                await this.launchReturnOrderForAsset(this.matchedAssets[0]);
            }
        } catch (error) {
            this.showError('Failed to search assets', error);
        } finally {
            this.isSearching = false;
        }
    }

    async handleSelectAsset(event) {
        const assetId = event.currentTarget.dataset.id;
        const asset = (this.matchedAssets || []).find((row) => row.id === assetId);
        if (!asset) {
            return;
        }
        await this.launchReturnOrderForAsset(asset);
    }

    async launchReturnOrderForAsset(asset) {
        this.selectedAssetId = asset.id;
        this.accountErrorMessage = '';
        this.showWizard = false;
        this.selectedAssetIds = [];

        if (!asset.accountId) {
            this.accountErrorMessage =
                'This asset is not linked to an account. Link the asset to an account before creating a return order.';
            return;
        }

        this.selectedAssetIds = [asset.id];
        this.showWizard = true;
    }

    handleExitWizard() {
        this.resetWizard();
    }

    resetWizard() {
        this.showWizard = false;
        this.selectedAssetIds = [];
        this.selectedAssetId = '';
        this.serialInput = '';
        this.matchedAssets = [];
        this.scanErrorMessage = '';
        this.accountErrorMessage = '';
    }

    showError(title, error) {
        const message =
            error?.body?.message ||
            error?.message ||
            (typeof error === 'string' ? error : 'Unknown error');
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant: 'error'
            })
        );
    }
}