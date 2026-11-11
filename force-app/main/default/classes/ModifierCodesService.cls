/**
 * @description GW-3458 - Applies, removes, and inherits pricing modifiers on evaluation work order lines.
 *              A line holds one modifier. An Item and Service modifier on a Product Serviced line
 *              is copied onto Service Code children that do not already have a different modifier.
 */
public with sharing class ModifierCodesService {
    public static final String LEVEL_ITEM = 'Item';
    public static final String LEVEL_SERVICE = 'Service';
    public static final String LEVEL_ITEM_AND_SERVICE = 'Item and Service';
    public static final String LINE_PRODUCT_SERVICED = 'Product Serviced';
    public static final String LINE_SERVICE_CODE = 'Service Code';
    public static final String LINE_CATEGORY_CODE = 'Category Code';
    public static final String LINE_SPECIAL_PRICING = 'Special Pricing';
    public static final String VARIANT_INSTRUMENT = 'instrument';
    public static final String KIND_ITEM = 'item';
    public static final String KIND_SERVICE = 'service';

    private static final Set<String> SERVICE_LINE_TYPES = new Set<String>{
        LINE_SERVICE_CODE,
        LINE_CATEGORY_CODE,
        LINE_SPECIAL_PRICING
    };
    private static final Set<String> ITEM_LEVELS = new Set<String>{ LEVEL_ITEM, LEVEL_ITEM_AND_SERVICE };
    private static final Set<String> SERVICE_LEVELS = new Set<String>{ LEVEL_SERVICE, LEVEL_ITEM_AND_SERVICE };

    public class ModifierCodesException extends Exception {
    }

    /**
     * @description Tables for the Modifier Codes tab.
     */
    public class Workspace {
        @AuraEnabled public Boolean showOrderReference;
        @AuraEnabled public List<LineRow> items = new List<LineRow>();
        @AuraEnabled public List<LineRow> services = new List<LineRow>();
        @AuraEnabled public List<ItemGroup> groups = new List<ItemGroup>();
    }

    /**
     * @description One Product Serviced item and the service lines beneath it.
     */
    public class ItemGroup implements Comparable {
        @AuraEnabled public String id;
        @AuraEnabled public String title;
        @AuraEnabled public String assetId;
        @AuraEnabled public String modifierName;
        @AuraEnabled public Boolean hasModifier;
        @AuraEnabled public Boolean canAdd;
        @AuraEnabled public String pricingModifierId;
        @AuraEnabled public String modifierReasonCode;
        @AuraEnabled public String orderReferenceId;
        @AuraEnabled public Boolean hasServices;
        @AuraEnabled public List<LineRow> services = new List<LineRow>();
        public String sortKey;

        public Integer compareTo(Object other) {
            ItemGroup that = (ItemGroup) other;
            return compareText(sortKey, that == null ? null : that.sortKey);
        }
    }

    /**
     * @description One row in the Item or Services table.
     */
    public class LineRow implements Comparable {
        @AuraEnabled public String id;
        @AuraEnabled public String assetId;
        @AuraEnabled public String kind;
        @AuraEnabled public String serialNumber;
        @AuraEnabled public String productName;
        @AuraEnabled public String model;
        @AuraEnabled public String manufacturer;
        @AuraEnabled public String category;
        @AuraEnabled public String itemNumber;
        @AuraEnabled public String description;
        @AuraEnabled public String categoryCodeDiscount;
        @AuraEnabled public String modifierName;
        @AuraEnabled public Boolean hasModifier;
        @AuraEnabled public Boolean canAdd;
        @AuraEnabled public Boolean canEdit;
        @AuraEnabled public String pricingModifierId;
        @AuraEnabled public String modifierReasonCode;
        @AuraEnabled public String orderReferenceId;
        public String sortKey;

        public Integer compareTo(Object other) {
            LineRow that = (LineRow) other;
            return compareText(sortKey, that == null ? null : that.sortKey);
        }
    }

    /**
     * @description Dropdown option. Value is a record Id.
     */
    public class PickOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    /**
     * @description Save payload from the Modifier Codes popup.
     */
    public class SaveRequest {
        @AuraEnabled public Id workOrderLineItemId;
        @AuraEnabled public Id pricingModifierId;
        @AuraEnabled public String modifierReasonCode;
        @AuraEnabled public Id orderReferenceId;
        @AuraEnabled public Boolean applyOrderReference;
    }

    /**
     * @description Builds the device tables or the instrument groups for one work order.
     * @param workOrderId Work Order being evaluated
     * @param variant device or instrument
     * @return Workspace for the Modifier Codes tab
     */
    public static Workspace getWorkspace(Id workOrderId, String variant) {
        if (workOrderId == null) {
            throw new ModifierCodesException('Work Order is required.');
        }
        Boolean instrument = VARIANT_INSTRUMENT.equalsIgnoreCase(variant);
        Workspace workspace = new Workspace();
        workspace.showOrderReference = !instrument;

        List<WorkOrderLineItem> lines = WorkOrderLineItemsSelector.selectForModifierCodes(workOrderId);
        Map<Id, ItemGroup> groupsById = new Map<Id, ItemGroup>();
        for (WorkOrderLineItem line : lines) {
            if (line.LineType__c == LINE_PRODUCT_SERVICED && line.IsAccessory__c != true) {
                LineRow itemRow = toItemRow(line);
                workspace.items.add(itemRow);
                groupsById.put(line.Id, toGroup(line, itemRow));
            }
        }
        for (WorkOrderLineItem line : lines) {
            if (!SERVICE_LINE_TYPES.contains(line.LineType__c)) {
                continue;
            }
            LineRow serviceRow = toServiceRow(line);
            workspace.services.add(serviceRow);
            ItemGroup parentGroup = groupsById.get(line.ParentWorkOrderLineItemId);
            if (parentGroup != null) {
                parentGroup.services.add(serviceRow);
            }
        }
        workspace.items.sort();
        workspace.services.sort();
        workspace.groups.addAll(groupsById.values());
        workspace.groups.sort();
        for (ItemGroup itemGroup : workspace.groups) {
            itemGroup.services.sort();
            itemGroup.hasServices = !itemGroup.services.isEmpty();
        }
        return workspace;
    }

    /**
     * @description Active modifiers for the item or service dropdown.
     * @param appliesTo item or service
     * @return Options filtered by Modifier Level
     */
    public static List<PickOption> getPricingModifierOptions(String appliesTo) {
        List<String> levels = KIND_SERVICE.equalsIgnoreCase(appliesTo)
            ? new List<String>{ LEVEL_SERVICE, LEVEL_ITEM_AND_SERVICE }
            : new List<String>{ LEVEL_ITEM, LEVEL_ITEM_AND_SERVICE };
        List<PickOption> options = new List<PickOption>();
        for (PricingModifier__c modifier : PricingModifiersSelector.selectActiveByLevels(levels)) {
            PickOption option = new PickOption();
            option.label = modifier.Name;
            option.value = modifier.Id;
            options.add(option);
        }
        return options;
    }

    /**
     * @description Shipped work orders for the asset, completion date descending.
     * @param assetId Asset on the line
     * @return Options for Modifier Reason Code and Order Reference
     */
    public static List<PickOption> getPriorWorkOrders(Id assetId) {
        List<PickOption> options = new List<PickOption>();
        if (assetId == null) {
            return options;
        }
        for (WorkOrder shipped : WorkOrdersSelector.selectShippedByAsset(assetId)) {
            PickOption option = new PickOption();
            option.label = shippedWorkOrderLabel(shipped);
            option.value = shipped.Id;
            options.add(option);
        }
        return options;
    }

    /**
     * @description GW-1162 reason codes. The org field is a restricted picklist, shown as a dropdown.
     * @return Active Modifier Reason Code values
     */
    public static List<PickOption> getReasonCodeOptions() {
        List<PickOption> options = new List<PickOption>();
        for (Schema.PicklistEntry entry : WorkOrderLineItem.ModifierReasonCode__c.getDescribe().getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }
            PickOption option = new PickOption();
            option.label = entry.getLabel();
            option.value = entry.getValue();
            options.add(option);
        }
        return options;
    }

    /**
     * @description Saves the modifier on one line. Item and Service modifiers also stamp
     *              Service Code children that do not already have a different modifier.
     * @param request Popup values
     */
    public static void saveModifier(SaveRequest request) {
        if (request == null || request.workOrderLineItemId == null) {
            throw new ModifierCodesException('Work Order Line is required.');
        }
        if (request.pricingModifierId == null) {
            throw new ModifierCodesException('Select a pricing modifier.');
        }
        WorkOrderLineItem line = loadLine(request.workOrderLineItemId);
        Boolean itemLine = isItemLine(line);
        if (!itemLine && !SERVICE_LINE_TYPES.contains(line.LineType__c)) {
            throw new ModifierCodesException('A modifier can only be applied to an item or a service line.');
        }
        if (!itemLine && !hasModifier(line) && discountBlocksAdd(line)) {
            throw new ModifierCodesException(
                'A modifier cannot be added when a category code discount is already applied.'
            );
        }

        PricingModifier__c modifier = loadModifier(request.pricingModifierId);
        Set<String> allowedLevels = itemLine ? ITEM_LEVELS : SERVICE_LEVELS;
        if (modifier.Active__c != true || !allowedLevels.contains(modifier.ModifierLevel__c)) {
            throw new ModifierCodesException('That pricing modifier is not available for this line.');
        }

        Id assetId = resolveAssetId(line);
        validateReasonCode(request.modifierReasonCode);
        Boolean applyOrderReference = request.applyOrderReference == true;
        if (applyOrderReference) {
            validateReference(request.orderReferenceId, assetId, 'Order Reference');
        }

        Id previousModifierId = line.PricingModifier__c;
        List<WorkOrderLineItem> updates = new List<WorkOrderLineItem>();
        updates.add(
            stampedLine(
                line.Id,
                modifier,
                request.modifierReasonCode,
                applyOrderReference ? request.orderReferenceId : null,
                applyOrderReference
            )
        );
        if (itemLine && modifier.ModifierLevel__c == LEVEL_ITEM_AND_SERVICE) {
            for (WorkOrderLineItem child : WorkOrderLineItemsSelector.selectServiceCodeChildren(line.Id)) {
                if (isDifferentModifier(child.PricingModifier__c, previousModifierId, modifier.Id)) {
                    continue;
                }
                updates.add(
                    stampedLine(
                        child.Id,
                        modifier,
                        request.modifierReasonCode,
                        applyOrderReference ? request.orderReferenceId : null,
                        applyOrderReference
                    )
                );
            }
        }
        update updates;
    }

    /**
     * @description Clears the modifier package. Removing an Item and Service modifier also
     *              clears Service Code children that still have that same modifier.
     * @param workOrderLineItemId Line to clear
     */
    public static void removeModifier(Id workOrderLineItemId) {
        WorkOrderLineItem line = loadLine(workOrderLineItemId);
        Id removedModifierId = line.PricingModifier__c;
        String removedLevel = line.PricingModifier__r == null
            ? null
            : line.PricingModifier__r.ModifierLevel__c;
        List<WorkOrderLineItem> updates = new List<WorkOrderLineItem>{ clearedLine(line.Id) };
        if (
            isItemLine(line) &&
            removedModifierId != null &&
            removedLevel == LEVEL_ITEM_AND_SERVICE
        ) {
            for (WorkOrderLineItem child : WorkOrderLineItemsSelector.selectServiceCodeChildren(line.Id)) {
                if (child.PricingModifier__c == removedModifierId) {
                    updates.add(clearedLine(child.Id));
                }
            }
        }
        update updates;
    }

    /**
     * @description Copies an Item and Service modifier onto newly inserted Service Code lines.
     *              Query failures are logged and skipped so unrelated line creation is unchanged.
     *              A failed update still rolls the insert back.
     * @param inserted Lines just inserted by WorkOrderLineItemsService
     */
    public static void inheritItemAndServiceModifier(List<WorkOrderLineItem> inserted) {
        if (inserted == null || inserted.isEmpty()) {
            return;
        }
        List<WorkOrderLineItem> candidates = new List<WorkOrderLineItem>();
        Set<Id> parentIds = new Set<Id>();
        for (WorkOrderLineItem line : inserted) {
            if (
                line.Id == null ||
                line.LineType__c != LINE_SERVICE_CODE ||
                line.ParentWorkOrderLineItemId == null ||
                line.PricingModifier__c != null
            ) {
                continue;
            }
            candidates.add(line);
            parentIds.add(line.ParentWorkOrderLineItemId);
        }
        if (candidates.isEmpty()) {
            return;
        }

        Map<Id, WorkOrderLineItem> parentsById;
        try {
            parentsById = new Map<Id, WorkOrderLineItem>(
                WorkOrderLineItemsSelector.selectModifierParents(parentIds)
            );
        } catch (Exception e) {
            Logger.warn(
                'GW-3458 modifier inheritance skipped because the parent modifier could not be read. ' +
                e.getMessage()
            );
            return;
        }

        List<WorkOrderLineItem> updates = new List<WorkOrderLineItem>();
        for (WorkOrderLineItem child : candidates) {
            WorkOrderLineItem parent = parentsById.get(child.ParentWorkOrderLineItemId);
            if (
                parent == null ||
                parent.PricingModifier__c == null ||
                parent.PricingModifier__r == null ||
                parent.PricingModifier__r.ModifierLevel__c != LEVEL_ITEM_AND_SERVICE
            ) {
                continue;
            }
            PricingModifier__c inherited = new PricingModifier__c(
                Id = parent.PricingModifier__c,
                Name = String.isNotBlank(parent.PricingModifierName__c)
                    ? parent.PricingModifierName__c
                    : parent.PricingModifier__r.Name,
                ModifierValue__c = parent.PricingModifierValue__c == null
                    ? parent.PricingModifier__r.ModifierValue__c
                    : parent.PricingModifierValue__c
            );
            WorkOrderLineItem stamped = stampedLine(
                child.Id,
                inherited,
                parent.ModifierReasonCode__c,
                parent.OrderReference__c,
                true
            );
            updates.add(stamped);
        }
        if (!updates.isEmpty()) {
            update updates;
        }
    }

    private static WorkOrderLineItem loadLine(Id lineItemId) {
        List<WorkOrderLineItem> lines = WorkOrderLineItemsSelector.selectForModifierUpdate(lineItemId);
        if (lines.isEmpty()) {
            throw new ModifierCodesException('The work order line was not found.');
        }
        return lines[0];
    }

    private static PricingModifier__c loadModifier(Id pricingModifierId) {
        List<PricingModifier__c> modifiers = PricingModifiersSelector.selectById(pricingModifierId);
        if (modifiers.isEmpty()) {
            throw new ModifierCodesException('That pricing modifier is not available for this line.');
        }
        return modifiers[0];
    }

    private static void validateReasonCode(String reasonCode) {
        if (String.isBlank(reasonCode)) {
            return;
        }
        for (Schema.PicklistEntry entry : WorkOrderLineItem.ModifierReasonCode__c.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue() == reasonCode) {
                return;
            }
        }
        throw new ModifierCodesException('Select a modifier reason code.');
    }

    private static void validateReference(Id referenceWorkOrderId, Id assetId, String fieldLabel) {
        if (referenceWorkOrderId == null) {
            return;
        }
        if (assetId == null) {
            throw new ModifierCodesException(fieldLabel + ' requires an asset on this line.');
        }
        List<WorkOrder> references = WorkOrdersSelector.selectForModifierReference(referenceWorkOrderId);
        if (
            references.isEmpty() ||
            references[0].AssetId != assetId ||
            references[0].ActualShipDate__c == null
        ) {
            throw new ModifierCodesException(
                'Select a shipped work order for this asset as the ' + fieldLabel + '.'
            );
        }
    }

    private static Boolean isItemLine(WorkOrderLineItem line) {
        return line.LineType__c == LINE_PRODUCT_SERVICED && line.IsAccessory__c != true;
    }

    private static Boolean hasModifier(WorkOrderLineItem line) {
        return line.PricingModifier__c != null || String.isNotBlank(line.PricingModifierName__c);
    }

    private static Boolean discountBlocksAdd(WorkOrderLineItem line) {
        return line.CategoryCodeDiscount__c != null && line.CategoryCodeDiscount__c != 0;
    }

    /**
     * @description True when the child already has a modifier that is neither blank,
     *              the item's previous modifier, nor the modifier being saved.
     */
    private static Boolean isDifferentModifier(Id childModifierId, Id previousModifierId, Id newModifierId) {
        if (childModifierId == null) {
            return false;
        }
        return childModifierId != previousModifierId && childModifierId != newModifierId;
    }

    private static Id resolveAssetId(WorkOrderLineItem line) {
        if (line.AssetId != null) {
            return line.AssetId;
        }
        return line.WorkOrder == null ? null : line.WorkOrder.AssetId;
    }

    private static WorkOrderLineItem stampedLine(
        Id lineId,
        PricingModifier__c modifier,
        String reasonCode,
        Id orderReferenceId,
        Boolean applyOrderReference
    ) {
        WorkOrderLineItem updateLine = new WorkOrderLineItem(Id = lineId);
        updateLine.PricingModifier__c = modifier.Id;
        updateLine.PricingModifierName__c = modifier.Name;
        updateLine.PricingModifierValue__c = modifier.ModifierValue__c;
        updateLine.ModifierReasonCode__c = reasonCode;
        if (applyOrderReference == true) {
            updateLine.OrderReference__c = orderReferenceId;
        }
        return updateLine;
    }

    private static WorkOrderLineItem clearedLine(Id lineId) {
        WorkOrderLineItem updateLine = new WorkOrderLineItem(Id = lineId);
        updateLine.PricingModifier__c = null;
        updateLine.PricingModifierName__c = null;
        updateLine.PricingModifierValue__c = null;
        updateLine.ModifierReasonCode__c = null;
        updateLine.OrderReference__c = null;
        return updateLine;
    }

    private static LineRow toItemRow(WorkOrderLineItem line) {
        LineRow row = baseRow(line, KIND_ITEM);
        row.serialNumber = firstNonBlank(
            line.SerialNumber__c,
            line.Asset == null ? null : line.Asset.SerialNumber,
            line.WorkOrder == null || line.WorkOrder.Asset == null ? null : line.WorkOrder.Asset.SerialNumber
        );
        row.productName = firstNonBlank(
            line.Product2 == null ? null : line.Product2.Name,
            line.Product__r == null ? null : line.Product__r.Name,
            line.ProductDescription__c
        );
        row.model = firstNonBlank(
            line.Model__c,
            line.Product2 == null ? null : line.Product2.Model__c,
            line.Product__r == null ? null : line.Product__r.Model__c
        );
        row.manufacturer = firstNonBlank(
            line.Asset == null ? null : line.Asset.ManufacturerCalculated__c,
            line.WorkOrder == null || line.WorkOrder.Asset == null
                ? null
                : line.WorkOrder.Asset.ManufacturerCalculated__c,
            firstNonBlank(
                line.Product2 == null ? null : line.Product2.Manufacturer__c,
                line.Product__r == null ? null : line.Product__r.Manufacturer__c,
                null
            )
        );
        row.itemNumber = firstNonBlank(
            line.ProductCodeWoli__c,
            line.Product2 == null ? null : line.Product2.ProductCode,
            line.Product__r == null ? null : line.Product__r.ProductCode
        );
        row.description = firstNonBlank(
            line.Product2 == null ? null : line.Product2.Name,
            line.ProductDescription__c,
            line.Product__r == null ? null : line.Product__r.Name
        );
        row.canEdit = false;
        row.sortKey = (row.itemNumber == null ? '' : row.itemNumber) + row.id;
        return row;
    }

    private static LineRow toServiceRow(WorkOrderLineItem line) {
        LineRow row = baseRow(line, KIND_SERVICE);
        row.category = firstNonBlank(
            line.RepairCode__r == null ? null : line.RepairCode__r.EvalCategory__c,
            line.Product2 == null ? null : line.Product2.EvalCategory__c,
            line.Product__r == null ? null : line.Product__r.EvalCategory__c
        );
        row.itemNumber = firstNonBlank(
            line.ProductCodeWoli__c,
            line.Product2 == null ? null : line.Product2.ProductCode,
            line.RepairCode__r == null ? null : line.RepairCode__r.ProductCode
        );
        row.description = firstNonBlank(
            line.ProductDescription__c,
            line.RepairCode__r == null ? null : line.RepairCode__r.Description,
            line.RepairCode__r == null ? null : line.RepairCode__r.Name
        );
        row.categoryCodeDiscount = formatDiscount(line.CategoryCodeDiscount__c);
        row.canAdd = row.hasModifier != true && !discountBlocksAdd(line);
        row.canEdit = row.hasModifier == true;
        row.sortKey = (row.category == null ? '' : row.category) + (row.itemNumber == null ? '' : row.itemNumber) + row.id;
        return row;
    }

    private static LineRow baseRow(WorkOrderLineItem line, String kind) {
        LineRow row = new LineRow();
        row.id = line.Id;
        row.assetId = resolveAssetId(line);
        row.kind = kind;
        row.pricingModifierId = line.PricingModifier__c;
        row.modifierReasonCode = line.ModifierReasonCode__c;
        row.orderReferenceId = line.OrderReference__c;
        row.modifierName = line.PricingModifier__r != null && String.isNotBlank(line.PricingModifier__r.Name)
            ? line.PricingModifier__r.Name
            : line.PricingModifierName__c;
        row.hasModifier = hasModifier(line);
        row.canAdd = row.hasModifier != true;
        row.canEdit = false;
        return row;
    }

    private static ItemGroup toGroup(WorkOrderLineItem line, LineRow itemRow) {
        ItemGroup itemGroup = new ItemGroup();
        itemGroup.id = itemRow.id;
        itemGroup.assetId = itemRow.assetId;
        itemGroup.modifierName = itemRow.modifierName;
        itemGroup.hasModifier = itemRow.hasModifier;
        itemGroup.canAdd = itemRow.canAdd;
        itemGroup.pricingModifierId = itemRow.pricingModifierId;
        itemGroup.modifierReasonCode = itemRow.modifierReasonCode;
        itemGroup.orderReferenceId = itemRow.orderReferenceId;
        String quantityLabel = line.Quantity == null ? '' : line.Quantity.stripTrailingZeros().toPlainString();
        String titleName = firstNonBlank(itemRow.description, itemRow.productName, '');
        String titleCode = itemRow.itemNumber == null ? '' : itemRow.itemNumber;
        itemGroup.title = (titleCode + ' ' + titleName).trim() + ' (' + quantityLabel + ')';
        itemGroup.sortKey = itemGroup.title;
        return itemGroup;
    }

    private static String formatDiscount(Decimal discount) {
        if (discount == null || discount == 0) {
            return '';
        }
        return discount.stripTrailingZeros().toPlainString() + '%';
    }

    private static String shippedWorkOrderLabel(WorkOrder shipped) {
        String label = String.isNotBlank(shipped.WorkOrderNumber) ? shipped.WorkOrderNumber : String.valueOf(shipped.Id);
        if (shipped.ActualShipDate__c != null) {
            label += ' · ' + shipped.ActualShipDate__c.format();
        }
        return label;
    }

    private static String firstNonBlank(String first, String second, String third) {
        if (String.isNotBlank(first)) {
            return first;
        }
        if (String.isNotBlank(second)) {
            return second;
        }
        return third;
    }

    private static Integer compareText(String left, String right) {
        String safeLeft = left == null ? '' : left.toLowerCase();
        String safeRight = right == null ? '' : right.toLowerCase();
        return safeLeft.compareTo(safeRight);
    }
}