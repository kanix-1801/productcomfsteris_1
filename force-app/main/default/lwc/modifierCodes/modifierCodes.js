import { LightningElement, api, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { getObjectInfo, getPicklistValues } from "lightning/uiObjectInfoApi";
import WORK_ORDER_LINE_ITEM from "@salesforce/schema/WorkOrderLineItem";
import MODIFIER_REASON_CODE from "@salesforce/schema/WorkOrderLineItem.ModifierReasonCode__c";
import getWorkspace from "@salesforce/apex/ModifierCodesController.getWorkspace";
import getPricingModifierOptions from "@salesforce/apex/ModifierCodesController.getPricingModifierOptions";
import getPriorWorkOrders from "@salesforce/apex/ModifierCodesController.getPriorWorkOrders";
import saveModifier from "@salesforce/apex/ModifierCodesController.saveModifier";
import removeModifier from "@salesforce/apex/ModifierCodesController.removeModifier";

const KIND_ITEM = "item";
const KIND_SERVICE = "service";
const LEVEL_ITEM_AND_SERVICE = "Item and Service";
const PENDING_LINE_TYPES = new Set([
  "Service Code",
  "Category Code",
  "Special Pricing"
]);

/**
 * GW-3458 - Modifier Codes tables shared by Device Evaluation and Instrument Evaluation.
 */
export default class ModifierCodes extends LightningElement {
  @api workOrderId;
  @api variant = "device";
  /** Selected service, category, and special pricing lines that are not saved yet. */
  @api pendingLines;

  workspace;
  isLoading = true;
  isActing = false;
  errorMessage = "";

  isModalOpen = false;
  optionsLoading = false;
  modalTitle = "Add Modifier";
  targetLineId;
  targetAssetId;
  targetKind = KIND_ITEM;
  isEdit = false;
  pricingModifierId = "";
  reasonCodeId = "";
  orderReferenceId = "";
  modifierOptions = [];
  reasonCodeOptions = [];
  workOrderOptions = [];

  reasonRecordTypeId;

  connectedCallback() {
    this.loadWorkspace();
  }

  /**
   * Modifier Reason Code is a restricted picklist, so the dialog reads it
   * from the line object instead of a custom Apex query.
   */
  @wire(getObjectInfo, { objectApiName: WORK_ORDER_LINE_ITEM })
  wiredLineItemInfo({ data, error }) {
    if (data) {
      this.reasonRecordTypeId = data.defaultRecordTypeId;
    } else if (error) {
      this.reasonCodeOptions = [];
    }
  }

  @wire(getPicklistValues, {
    recordTypeId: "$reasonRecordTypeId",
    fieldApiName: MODIFIER_REASON_CODE
  })
  wiredReasonCodes({ data, error }) {
    if (data) {
      this.reasonCodeOptions = data.values.map((entry) => ({
        label: entry.label,
        value: entry.value
      }));
    } else if (error) {
      this.toastError(
        this.messageFrom(error) || "Unable to load modifier reason codes."
      );
    }
  }

  get isDevice() {
    return this.variant !== "instrument";
  }

  /**
   * GW-3458 - Match the evaluation header tracks so the tables end at column 2.
   */
  get rootClass() {
    return this.isDevice
      ? "modifier-codes modifier-codes_device"
      : "modifier-codes modifier-codes_instrument";
  }

  get showOrderReference() {
    return this.workspace?.showOrderReference !== false && this.isDevice;
  }

  get itemRows() {
    return this.workspace?.items || [];
  }

  get serviceRows() {
    return this.workspace?.services || [];
  }

  get groups() {
    return this.workspace?.groups || [];
  }

  get hasItems() {
    return this.itemRows.length > 0;
  }

  get hasServices() {
    return this.serviceRows.length > 0;
  }

  get hasGroups() {
    return this.groups.length > 0;
  }

  get isSaveDisabled() {
    return this.isActing || this.optionsLoading || !this.pricingModifierId;
  }

  get modalIntro() {
    return this.targetKind === KIND_SERVICE
      ? "Choose the pricing modifier for this service."
      : "Choose the pricing modifier for this item.";
  }

  async loadWorkspace() {
    if (!this.workOrderId) {
      this.workspace = null;
      this.isLoading = false;
      this.errorMessage = "Work Order is required.";
      return;
    }
    this.isLoading = true;
    this.errorMessage = "";
    try {
      const workspace = await getWorkspace({
        workOrderId: this.workOrderId,
        variant: this.variant
      });
      this.mergePendingLines(workspace);
      this.workspace = workspace;
    } catch (error) {
      this.workspace = null;
      this.errorMessage = this.messageFrom(error);
    } finally {
      this.isLoading = false;
    }
  }

  handleAdd(event) {
    this.openModal(this.rowFromEvent(event), false);
  }

  handleEdit(event) {
    this.openModal(this.rowFromEvent(event), true);
  }

  rowFromEvent(event) {
    if (event.detail && event.detail.id) {
      return {
        lineId: event.detail.id,
        assetId: event.detail.assetId,
        kind: event.detail.kind,
        pending: event.detail.pending,
        pricingModifierId: event.detail.pricingModifierId,
        reasonCodeId: event.detail.modifierReasonCode,
        orderReferenceId: event.detail.orderReferenceId
      };
    }
    const dataset = event.currentTarget?.dataset || {};
    return {
      lineId: dataset.lineId,
      assetId: dataset.assetId,
      kind: dataset.kind,
      pricingModifierId: dataset.pricingModifierId,
      reasonCodeId: dataset.reasonCodeId,
      orderReferenceId: dataset.orderReferenceId
    };
  }

  async openModal(source, isEdit) {
    this.targetLineId = source.lineId;
    this.targetAssetId = source.assetId || null;
    this.targetKind = source.kind || KIND_ITEM;
    this.isEdit = isEdit;
    this.modalTitle = isEdit ? "Edit Modifier" : "Add Modifier";
    this.pricingModifierId = isEdit ? source.pricingModifierId || "" : "";
    this.reasonCodeId = isEdit ? source.reasonCodeId || "" : "";
    this.orderReferenceId = isEdit ? source.orderReferenceId || "" : "";
    this.modifierOptions = [];
    this.workOrderOptions = [];
    this.setModalOpen(true);
    this.optionsLoading = true;
    try {
      const modifierRequest = getPricingModifierOptions({
        appliesTo: this.targetKind
      });
      const workOrderRequest =
        this.showOrderReference && this.targetAssetId
          ? getPriorWorkOrders({
              assetId: this.targetAssetId,
              workOrderId: this.workOrderId
            })
          : Promise.resolve([]);
      const [modifiers, workOrders] = await Promise.all([
        modifierRequest,
        workOrderRequest
      ]);
      this.modifierOptions = modifiers || [];
      this.workOrderOptions = (workOrders || []).filter(
        (option) => !this.sameId(option.value, this.workOrderId)
      );
    } catch (error) {
      this.setModalOpen(false);
      this.toastError(this.messageFrom(error));
    } finally {
      this.optionsLoading = false;
    }
  }

  /**
   * GW-3458 - The dialog lives in the scrolling panel. Tell the evaluation
   * header to drop behind it, the same way parts and photos do.
   * @param {Boolean} open true while the pricing modifier dialog is open
   */
  setModalOpen(open) {
    this.isModalOpen = open;
    this.dispatchEvent(
      new CustomEvent("modalchange", {
        bubbles: true,
        composed: true,
        detail: { open }
      })
    );
  }

  disconnectedCallback() {
    if (this.isModalOpen) {
      this.setModalOpen(false);
    }
  }

  handlePricingModifierChange(event) {
    this.pricingModifierId = event.detail.value;
  }

  handleReasonChange(event) {
    this.reasonCodeId = event.detail.value;
  }

  handleOrderReferenceChange(event) {
    this.orderReferenceId = event.detail.value;
  }

  handleCancel() {
    if (this.isActing) {
      return;
    }
    this.setModalOpen(false);
  }

  async handleSave() {
    if (this.isSaveDisabled) {
      return;
    }
    if (!this.targetLineId) {
      this.toastError("Work Order Line is required.");
      return;
    }
    const choice = {
      pricingModifierId: this.pricingModifierId,
      modifierName: this.selectedModifierName(),
      modifierReasonCode: this.reasonCodeId || null,
      orderReferenceId: this.showOrderReference
        ? this.orderReferenceId || null
        : null,
      cleared: false
    };
    if (this.isPendingLine(this.targetLineId)) {
      this.applyPendingChoice(this.targetLineId, choice);
      this.setModalOpen(false);
      return;
    }
    this.isActing = true;
    try {
      await saveModifier({
        workOrderLineItemId: this.targetLineId,
        pricingModifierId: choice.pricingModifierId,
        modifierReasonCode: choice.modifierReasonCode,
        orderReferenceId: choice.orderReferenceId,
        applyOrderReference: this.showOrderReference
      });
      this.setModalOpen(false);
      await this.loadWorkspace();
    } catch (error) {
      this.toastError(this.messageFrom(error));
    } finally {
      this.isActing = false;
    }
  }

  async handleRemove(event) {
    const row = this.rowFromEvent(event);
    if (!row.lineId || this.isActing) {
      return;
    }
    if (row.pending === true || this.isPendingLine(row.lineId)) {
      this.applyPendingChoice(row.lineId, { cleared: true });
      return;
    }
    this.isActing = true;
    try {
      await removeModifier({ workOrderLineItemId: row.lineId });
      await this.loadWorkspace();
    } catch (error) {
      this.toastError(this.messageFrom(error));
    } finally {
      this.isActing = false;
    }
  }

  isPendingLine(lineId) {
    return String(lineId || "").startsWith("pending-");
  }

  selectedModifierName() {
    const option = (this.modifierOptions || []).find(
      (item) => item.value === this.pricingModifierId
    );
    return option?.label || "";
  }

  /**
   * A code that is not saved yet still gets edit and delete.
   * The choice is kept on the row and sent to the evaluation so save can stamp it.
   * @param {string} lineId Pending row id
   * @param {object} choice Modifier to show, or cleared true to remove it
   */
  applyPendingChoice(lineId, choice) {
    let detail = null;
    const stamp = (row) => {
      if (row?.id !== lineId) {
        return row;
      }
      const hasModifier = choice.cleared !== true && !!choice.pricingModifierId;
      const next = {
        ...row,
        hasModifier,
        canAdd: !hasModifier,
        canEdit: hasModifier,
        canRemove: hasModifier,
        modifierName: hasModifier ? choice.modifierName || "" : "",
        pricingModifierId: hasModifier ? choice.pricingModifierId : null,
        modifierReasonCode: hasModifier ? choice.modifierReasonCode : null,
        orderReferenceId: hasModifier ? choice.orderReferenceId : null,
        modifierChoice: choice
      };
      detail = {
        productId: next.productId,
        parentLineId: next.parentLineId,
        cleared: choice.cleared === true,
        pricingModifierId: next.pricingModifierId,
        modifierName: next.modifierName,
        modifierReasonCode: next.modifierReasonCode,
        orderReferenceId: next.orderReferenceId
      };
      return next;
    };
    const services = (this.workspace?.services || []).map(stamp);
    const groups = (this.workspace?.groups || []).map((group) => ({
      ...group,
      services: (group.services || []).map(stamp)
    }));
    this.workspace = { ...this.workspace, services, groups };
    if (!detail?.productId) {
      return;
    }
    this.dispatchEvent(
      new CustomEvent("linemodifier", {
        bubbles: true,
        composed: true,
        detail
      })
    );
  }

  /**
   * The other tabs own which codes are selected. Show those codes here,
   * including ones that are not saved yet, and drop a code as soon as it is unchecked.
   * An Item and Service modifier on the item is copied onto a new code.
   * @param {object} workspace Modifier tables loaded from the server
   */
  mergePendingLines(workspace) {
    if (!workspace || !Array.isArray(this.pendingLines)) {
      return;
    }
    const pending = this.pendingLines.filter(
      (line) => line?.productId && PENDING_LINE_TYPES.has(line.lineType)
    );
    const parents = workspace.items?.length
      ? workspace.items
      : workspace.groups || [];
    const singleParent = parents.length === 1 ? parents[0] : null;
    const selectedKeys = new Set();
    pending.forEach((line) => {
      const parent = this.parentForPending(
        parents,
        singleParent,
        line.parentLineId
      );
      const parentId = parent?.id || line.parentLineId || "";
      selectedKeys.add(this.lineKey(parentId, line.productId));
    });
    const isSelected = (row) => {
      if (!row?.productId) {
        return true;
      }
      return (
        selectedKeys.has(this.lineKey(row.parentLineId, row.productId)) ||
        selectedKeys.has(this.lineKey(singleParent?.id, row.productId)) ||
        selectedKeys.has(this.lineKey("", row.productId))
      );
    };
    workspace.services = (workspace.services || []).filter(isSelected);
    (workspace.groups || []).forEach((group) => {
      group.services = (group.services || []).filter(isSelected);
      group.hasServices = group.services.length > 0;
    });

    const savedKeys = new Set();
    const remember = (row) => {
      if (!row?.productId) {
        return;
      }
      savedKeys.add(this.lineKey(row.parentLineId, row.productId));
      savedKeys.add(this.lineKey(singleParent?.id, row.productId));
    };
    (workspace.services || []).forEach(remember);
    (workspace.groups || []).forEach((group) =>
      (group.services || []).forEach(remember)
    );

    pending.forEach((line) => {
      const parent = this.parentForPending(
        parents,
        singleParent,
        line.parentLineId
      );
      const parentId = parent?.id || line.parentLineId || "";
      const key = this.lineKey(parentId, line.productId);
      if (savedKeys.has(key)) {
        return;
      }
      savedKeys.add(key);
      const row = this.pendingRow(line, parent);
      workspace.services = [...(workspace.services || []), row];
      const group = (workspace.groups || []).find((itemGroup) =>
        this.sameId(itemGroup.id, parentId)
      );
      if (group) {
        group.services = [...(group.services || []), row];
        group.hasServices = true;
      }
    });
    workspace.services = this.sortRows(workspace.services);
    (workspace.groups || []).forEach((group) => {
      group.services = this.sortRows(group.services);
    });
  }

  parentForPending(parents, singleParent, parentLineId) {
    if (parentLineId) {
      return (
        parents.find((parent) => this.sameId(parent.id, parentLineId)) || null
      );
    }
    return singleParent;
  }

  pendingRow(line, parent) {
    const choice = line.modifierChoice;
    const chosen = choice?.cleared !== true && !!choice?.pricingModifierId;
    const inherited =
      !choice &&
      parent?.hasModifier === true &&
      parent?.modifierLevel === LEVEL_ITEM_AND_SERVICE;
    const hasModifier = chosen || inherited;
    const parentId = parent?.id || line.parentLineId || "work-order";
    return {
      id: `pending-${parentId}-${line.productId}`,
      pending: true,
      productId: line.productId,
      parentLineId: parent?.id || line.parentLineId || null,
      assetId: parent?.assetId || null,
      kind: KIND_SERVICE,
      category: line.category || "",
      itemNumber: line.itemNumber || "",
      description: line.description || "",
      categoryCodeDiscount: "",
      hasModifier,
      canAdd: !hasModifier,
      canEdit: hasModifier,
      canRemove: hasModifier,
      modifierName: chosen
        ? choice.modifierName || ""
        : inherited
          ? parent.modifierName
          : "",
      pricingModifierId: chosen
        ? choice.pricingModifierId
        : inherited
          ? parent.pricingModifierId
          : null,
      modifierReasonCode: chosen
        ? choice.modifierReasonCode
        : inherited
          ? parent.modifierReasonCode
          : null,
      orderReferenceId: chosen
        ? choice.orderReferenceId
        : inherited
          ? parent.orderReferenceId
          : null,
      modifierLevel: inherited ? parent.modifierLevel : null,
      modifierChoice: choice || null
    };
  }

  lineKey(parentId, productId) {
    return `${this.idKey(parentId)}:${this.idKey(productId)}`;
  }

  sameId(left, right) {
    return this.idKey(left) !== "" && this.idKey(left) === this.idKey(right);
  }

  idKey(value) {
    return value ? String(value).substring(0, 15) : "";
  }

  sortRows(rows) {
    return [...(rows || [])].sort((left, right) => {
      const leftKey =
        `${left.category || ""}${left.itemNumber || ""}${left.id || ""}`.toLowerCase();
      const rightKey =
        `${right.category || ""}${right.itemNumber || ""}${right.id || ""}`.toLowerCase();
      if (leftKey < rightKey) {
        return -1;
      }
      if (leftKey > rightKey) {
        return 1;
      }
      return 0;
    });
  }

  toastError(message) {
    this.dispatchEvent(
      new ShowToastEvent({
        title: "Modifier codes",
        message,
        variant: "error"
      })
    );
  }

  messageFrom(error) {
    return (
      error?.body?.message || error?.message || "Unable to update the modifier."
    );
  }
}