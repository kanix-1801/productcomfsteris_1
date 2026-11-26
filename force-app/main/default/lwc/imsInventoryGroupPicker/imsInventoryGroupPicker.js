/**
 * @description GW-6456 - IMS Covered Equipment, step 1 (modal): pick the inventory group(s) uploaded for the quote's
 * opportunity and whether their devices are included. The preview panel lists a group's devices.
 * Closes with { groups, includeOpportunityAssets } on "Next - Asset Assignment", or with nothing on Cancel.
 */
import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import { formatCount } from 'c/assetPickerUtils';

export default class ImsInventoryGroupPicker extends LightningModal {
    @api opportunityId;
    @api opportunityName;
    @api groups = []; // [{ name, deviceCount, uploadedOn }]
    @api selectedGroups; // names chosen before; empty/undefined = all groups
    @api includeOpportunityAssets;

    chosen = new Set();
    include = true;
    previewGroup;

    connectedCallback() {
        const names = (this.groups || []).map((g) => g.name);
        const before = (this.selectedGroups || []).filter((n) => names.includes(n));
        this.chosen = new Set(before.length ? before : names);
        this.include = this.hasGroups && this.includeOpportunityAssets !== false;
        this.previewGroup = names.length === 1 ? names[0] : null;
    }

    get hasGroups() {
        return !!(this.groups && this.groups.length);
    }

    get subtitle() {
        return this.opportunityName ? `Opportunity ${this.opportunityName}` : 'No opportunity on this quote';
    }

    get rows() {
        return (this.groups || []).map((g) => ({
            ...g,
            key: `group-${g.name}`,
            checked: this.chosen.has(g.name),
            disabled: !this.include,
            countLabel: formatCount(g.deviceCount),
            uploadedLabel: g.uploadedOn
                ? new Intl.DateTimeFormat(undefined, { year: 'numeric', month: 'short', day: 'numeric' }).format(
                      new Date(g.uploadedOn)
                  )
                : '',
            rowClass: g.name === this.previewGroup ? 'group-row group-row-active' : 'group-row',
            previewLabel: `Preview ${g.name}`
        }));
    }

    get previewDeviceCount() {
        return (this.groups || []).find((g) => g.name === this.previewGroup)?.deviceCount;
    }

    get chosenDeviceCount() {
        return formatCount(
            (this.groups || []).filter((g) => this.chosen.has(g.name)).reduce((sum, g) => sum + (g.deviceCount || 0), 0)
        );
    }

    get chosenSummary() {
        if (!this.include) return 'The opportunity’s devices are not included. Pick assets individually in the next step.';
        return `${this.chosen.size} of ${this.groups.length} groups · ${this.chosenDeviceCount} devices`;
    }

    get nextDisabled() {
        return this.include && this.chosen.size === 0;
    }

    handleInclude(event) {
        this.include = event.target.checked;
    }

    handleCheck(event) {
        const name = event.target.dataset.name;
        const next = new Set(this.chosen);
        if (event.target.checked) next.add(name);
        else next.delete(name);
        this.chosen = next;
    }

    handlePreview(event) {
        this.previewGroup = event.currentTarget.dataset.name;
    }

    handleCancel() {
        this.close(null);
    }

    handleNext() {
        // keep the groups' order
        const groups = (this.groups || []).map((g) => g.name).filter((n) => this.chosen.has(n));
        this.close({ groups, includeOpportunityAssets: this.include });
    }
}