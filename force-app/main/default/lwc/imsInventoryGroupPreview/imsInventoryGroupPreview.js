/**
 * @description GW-6456 - IMS Covered Equipment: preview panel inside the inventory group picker. Lists the devices
 * of one inventory group (50 rows per page, loaded as the rep scrolls) so the rep can recognise the group.
 */
import { LightningElement, api } from 'lwc';
import getGroupAssets from '@salesforce/apex/ImsAssetAssignmentController.getGroupAssets';

const PAGE = 50; // ImsAssetAssignmentService.PREVIEW_PAGE_SIZE
const MAX_ROWS = 2000; // SOQL OFFSET limit; the full list is searchable in Choose Assets

const COLUMNS = [
    { label: 'Serial Number', fieldName: 'serialNumber', initialWidth: 130 },
    { label: 'Asset Name', fieldName: 'name', initialWidth: 180 },
    { label: 'PFCL', fieldName: 'pfcl' },
    { label: 'Product Line', fieldName: 'productLine' },
    { label: 'Manufacturer', fieldName: 'manufacturer' },
    { label: 'Model', fieldName: 'model' },
    { label: 'Account', fieldName: 'accountName' }
];

export default class ImsInventoryGroupPreview extends LightningElement {
    @api opportunityId;
    @api deviceCount; // devices in the group, for the heading

    @api
    get groupName() {
        return this._group;
    }
    set groupName(value) {
        if (value === this._group) return;
        this._group = value;
        this.rows = [];
        this.done = false;
        this.error = null;
        this._request++;
        if (value) this.loadMore();
    }

    _group;
    _request = 0; // ignores a page that arrives after the group was changed
    columns = COLUMNS;
    rows = [];
    loading = false;
    done = false;
    error;

    get hasGroup() {
        return !!this._group;
    }

    get canLoadMore() {
        return !this.done && !this.error && this.rows.length < MAX_ROWS;
    }

    get capped() {
        return this.rows.length >= MAX_ROWS;
    }

    get heading() {
        return this.deviceCount ? `${this._group} · ${this.deviceCount} devices` : this._group;
    }

    get isEmpty() {
        return this.done && !this.rows.length;
    }

    async loadMore() {
        if (this.loading || !this.canLoadMore || !this._group) return;
        const request = this._request;
        this.loading = true;
        try {
            const page = await getGroupAssets({
                opportunityId: this.opportunityId,
                groupName: this._group,
                offset: this.rows.length
            });
            if (request !== this._request) return;
            this.rows = [...this.rows, ...(page || [])];
            this.done = !page || page.length < PAGE;
        } catch (e) {
            if (request === this._request) this.error = e?.body?.message || 'Unable to load the devices in this group.';
        } finally {
            if (request === this._request) this.loading = false;
        }
    }

    handleLoadMore() {
        this.loadMore();
    }
}
