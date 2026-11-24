/**
 * @description GW-259: Loads Device Standards for a Product Serviced line and saves PMI measurements.
 *              A failed reading sets the line Inspection Outcome to Performance Standard Not Met (P1).
 * @group Work Order Debrief
 * @see woDebriefPmiInspection
 */
public with sharing class WoDebriefPmiInspectionController {
    /** @description Measurement Type stored for checklist rows. */
    @TestVisible private static final String MEASUREMENT_TYPE_PMI = 'PMI';
    /** @description Passing reading. */
    @TestVisible private static final String STATUS_PASS = 'Pass';
    /** @description Failing reading. */
    @TestVisible private static final String STATUS_FAILED = 'Failed';
    /** @description Work order line outcome when any reading fails. */
    public static final String OUTCOME_P1 = 'Performance Standard Not Met (P1)';
    /** @description Outcome written when a later save clears a P1 that this checklist set. */
    @TestVisible private static final String OUTCOME_PASSED = 'Passed';
    private static final String LINE_TYPE_PRODUCT_SERVICED = 'Product Serviced';
    private static final Integer NAME_MAX = 80;
    private static final Integer REFERENCE_MAX = 20;
    private static final Integer VALUE_MAX = 50;
    private static final Set<String> CLOSED_WORK_ORDER_STATUSES = new Set<String>{
        'Completed', 'Closed', 'Canceled', 'Cannot Complete'
    };

    /** @description Device Standards substituted in tests so ProductAttributeDefinition is not required. */
    @TestVisible
    private static Map<Id, DeviceStandard> testStandardsById;

    /**
     * @description One Device Standard used to seed a checklist row.
     */
    public class DeviceStandard {
        /** @description ProductAttributeDefinition Id. */
        @AuraEnabled public Id standardId;
        /** @description Product the standard belongs to. */
        public Id product2Id;
        /** @description Device Standard name. */
        @AuraEnabled public String name;
        /** @description Default value from the Device Standard. */
        @AuraEnabled public String referenceValue;
        /** @description Minimum from the Device Standard. Not stored on the measurement. */
        @AuraEnabled public String minimumValue;
        /** @description Maximum from the Device Standard. Not stored on the measurement. */
        @AuraEnabled public String maximumValue;
    }

    /**
     * @description Checklist row shown in the inspection popup.
     */
    public class InspectionRow {
        /** @description ProductAttributeDefinition Id for a Device Standard row. */
        @AuraEnabled public Id standardId;
        /** @description Existing Measurement Id when the row was saved before. */
        @AuraEnabled public Id measurementId;
        /** @description Measurement name. Read-only for Device Standards. */
        @AuraEnabled public String measurementName;
        /** @description Reference value. Read-only for Device Standards. */
        @AuraEnabled public String referenceValue;
        /** @description Minimum. Read-only for Device Standards. */
        @AuraEnabled public String minimumValue;
        /** @description Maximum. Read-only for Device Standards. */
        @AuraEnabled public String maximumValue;
        /** @description Value entered by the user. */
        @AuraEnabled public String measurementValue;
        /** @description Comment entered by the user. */
        @AuraEnabled public String comments;
        /** @description Pass or Failed when a value is present. */
        @AuraEnabled public String status;
        /** @description True when the user added the row. */
        @AuraEnabled public Boolean manual;
    }

    /**
     * @description Popup payload for one Product Serviced line.
     */
    public class InspectionContext {
        /** @description True when the work order can no longer be edited. */
        @AuraEnabled public Boolean workOrderClosed;
        /** @description True when the product has at least one active Device Standard. */
        @AuraEnabled public Boolean hasStandards;
        /** @description Message when the product has no Device Standards. */
        @AuraEnabled public String emptyMessage;
        /** @description Device Standard rows, then any manual measurements. */
        @AuraEnabled public List<InspectionRow> rows;
    }

    /**
     * @description One row submitted from the inspection popup.
     */
    public class MeasurementInput {
        /** @description Existing Measurement Id. */
        @AuraEnabled public Id measurementId { get; set; }
        /** @description ProductAttributeDefinition Id. Null for a manual row. */
        @AuraEnabled public Id standardId { get; set; }
        /** @description Measurement name for a manual row. */
        @AuraEnabled public String measurementName { get; set; }
        /** @description Reference value for a manual row. */
        @AuraEnabled public String referenceValue { get; set; }
        /** @description Optional minimum for a manual row. Used only to calculate Pass or Failed. */
        @AuraEnabled public String minimumValue { get; set; }
        /** @description Optional maximum for a manual row. Used only to calculate Pass or Failed. */
        @AuraEnabled public String maximumValue { get; set; }
        /** @description Value entered by the user. */
        @AuraEnabled public String measurementValue { get; set; }
        /** @description Comment entered by the user. */
        @AuraEnabled public String comments { get; set; }
    }

    /**
     * @description Result of saving the checklist.
     */
    public class SaveResult {
        /** @description Inspection Outcome on the line after the save. */
        @AuraEnabled public String inspectionOutcome;
        /** @description True when the outcome was changed by this save. */
        @AuraEnabled public Boolean outcomeUpdated;
        /** @description True when any saved row failed. */
        @AuraEnabled public Boolean hasFailure;
        /** @description True when every Device Standard has a value, or the product has none. */
        @AuraEnabled public Boolean checklistComplete;
    }

    /**
     * @description Product Serviced lines on a work order whose checklist is satisfied.
     *              A line is satisfied when its product has no active Device Standards, or every
     *              standard already has a PMI measurement value.
     * @param workOrderId Work Order Id
     * @return Satisfied Product Serviced line Ids
     */
    @AuraEnabled
    public static List<Id> listSatisfiedLineIds(Id workOrderId) {
        if (workOrderId == null) {
            return new List<Id>();
        }
        List<WorkOrderLineItem> lines = [
            SELECT Id, Asset.Product2Id
            FROM WorkOrderLineItem
            WHERE WorkOrderId = :workOrderId
                AND LineType__c = :LINE_TYPE_PRODUCT_SERVICED
                AND AssetId != null
            WITH USER_MODE
        ];
        if (lines.isEmpty()) {
            return new List<Id>();
        }

        Set<Id> productIds = new Set<Id>();
        Set<Id> lineIds = new Set<Id>();
        for (WorkOrderLineItem line : lines) {
            lineIds.add(line.Id);
            if (line.Asset.Product2Id != null) {
                productIds.add(line.Asset.Product2Id);
            }
        }

        Map<Id, List<DeviceStandard>> standardsByProduct = standardsByProduct(productIds);
        Map<Id, Set<String>> measuredNamesByLine = measuredNamesByLine(lineIds);
        List<Id> satisfied = new List<Id>();
        for (WorkOrderLineItem line : lines) {
            List<DeviceStandard> standards = standardsByProduct.get(line.Asset.Product2Id);
            if (standards == null || standards.isEmpty()) {
                satisfied.add(line.Id);
                continue;
            }
            Set<String> measuredNames = measuredNamesByLine.containsKey(line.Id)
                ? measuredNamesByLine.get(line.Id)
                : new Set<String>();
            if (coversStandards(standards, measuredNames)) {
                satisfied.add(line.Id);
            }
        }
        return satisfied;
    }

    /**
     * @description Loads Device Standards for the line asset's product and any PMI measurements already saved.
     * @param workOrderLineItemId Product Serviced line Id
     * @return Checklist context
     */
    @AuraEnabled
    public static InspectionContext loadInspection(Id workOrderLineItemId) {
        WorkOrderLineItem line = queryLine(workOrderLineItemId);
        InspectionContext context = new InspectionContext();
        context.workOrderClosed = CLOSED_WORK_ORDER_STATUSES.contains(line.WorkOrder.Status);
        context.rows = new List<InspectionRow>();
        context.hasStandards = false;
        context.emptyMessage = null;

        Id productId = line.AssetId == null ? null : line.Asset.Product2Id;
        List<DeviceStandard> standards = standardsForProduct(productId);
        Map<String, Measurement__c> savedByName = measurementsByName(line.Id);
        Set<Id> usedMeasurementIds = new Set<Id>();

        for (DeviceStandard standard : standards) {
            context.hasStandards = true;
            Measurement__c existing = savedByName.get(standard.name);
            InspectionRow row = new InspectionRow();
            row.standardId = standard.standardId;
            row.measurementName = standard.name;
            row.referenceValue = standard.referenceValue;
            row.minimumValue = standard.minimumValue;
            row.maximumValue = standard.maximumValue;
            row.manual = false;
            if (existing != null) {
                row.measurementId = existing.Id;
                row.measurementValue = existing.MeasurementValue__c;
                row.comments = existing.Comments__c;
                row.status = existing.Status__c;
                usedMeasurementIds.add(existing.Id);
            }
            context.rows.add(row);
        }

        for (Measurement__c existing : savedByName.values()) {
            if (usedMeasurementIds.contains(existing.Id)) {
                continue;
            }
            InspectionRow row = new InspectionRow();
            row.measurementId = existing.Id;
            row.measurementName = existing.Name;
            row.referenceValue = existing.ReferenceValue__c;
            row.measurementValue = existing.MeasurementValue__c;
            row.comments = existing.Comments__c;
            row.status = existing.Status__c;
            row.manual = true;
            context.rows.add(row);
        }

        if (!context.hasStandards) {
            context.emptyMessage = 'There is nothing to fill for this asset.';
        }
        return context;
    }

    /**
     * @description Saves PMI measurements and sets P1 when any reading fails.
     *              When a previous P1 is cleared by an all-pass save, the outcome becomes Passed.
     * @param workOrderLineItemId Product Serviced line Id
     * @param rows Checklist rows from the popup
     * @return Save result
     */
    @AuraEnabled
    public static SaveResult saveInspection(Id workOrderLineItemId, List<MeasurementInput> rows) {
        WorkOrderLineItem line = queryLine(workOrderLineItemId);
        if (CLOSED_WORK_ORDER_STATUSES.contains(line.WorkOrder.Status)) {
            throw PlatformUtilities.buildAuraException('This work order is closed. Measurements cannot be changed.');
        }
        if (line.AssetId == null) {
            throw PlatformUtilities.buildAuraException('Add an asset before recording the inspection.');
        }

        List<MeasurementInput> inputs = rows == null ? new List<MeasurementInput>() : rows;
        List<DeviceStandard> standards = standardsForProduct(line.Asset.Product2Id);
        Map<Id, DeviceStandard> standardsById = new Map<Id, DeviceStandard>();
        for (DeviceStandard standard : standards) {
            standardsById.put(standard.standardId, standard);
        }

        Set<Id> submittedStandardIds = new Set<Id>();
        List<PreparedRow> prepared = new List<PreparedRow>();
        for (MeasurementInput input : inputs) {
            if (input == null) {
                continue;
            }
            prepared.add(prepareRow(input, standardsById, line.Asset.Product2Id, submittedStandardIds));
        }
        for (DeviceStandard standard : standards) {
            if (!submittedStandardIds.contains(standard.standardId)) {
                throw PlatformUtilities.buildAuraException('Enter a measurement value for ' + standard.name + '.');
            }
        }

        Map<Id, Measurement__c> existingById = new Map<Id, Measurement__c>();
        Map<String, Measurement__c> existingByName = new Map<String, Measurement__c>();
        for (Measurement__c existing : [
            SELECT Id, Name
            FROM Measurement__c
            WHERE WorkOrderLineItem__c = :line.Id
                AND MeasurementType__c = :MEASUREMENT_TYPE_PMI
            WITH USER_MODE
        ]) {
            existingById.put(existing.Id, existing);
            existingByName.put(existing.Name, existing);
        }

        List<Measurement__c> upserts = new List<Measurement__c>();
        Boolean hasFailure = false;
        for (PreparedRow row : prepared) {
            Measurement__c measurement = new Measurement__c(
                Name = row.name,
                Asset__c = line.AssetId,
                WorkOrder__c = line.WorkOrderId,
                WorkOrderLineItem__c = line.Id,
                MeasurementType__c = MEASUREMENT_TYPE_PMI,
                ReferenceValue__c = row.referenceValue,
                MeasurementValue__c = row.measurementValue,
                MeasurementDate__c = Date.today(),
                Comments__c = row.comments,
                Status__c = row.status
            );
            Id existingId = row.measurementId;
            if (existingId != null && !existingById.containsKey(existingId)) {
                existingId = null;
            }
            if (existingId == null && existingByName.containsKey(row.name)) {
                existingId = existingByName.get(row.name).Id;
            }
            if (existingId != null) {
                measurement.Id = existingId;
            }
            if (row.status == STATUS_FAILED) {
                hasFailure = true;
            }
            upserts.add(measurement);
        }

        if (!upserts.isEmpty()) {
            try {
                Database.upsert(upserts, AccessLevel.USER_MODE);
            } catch (DmlException ex) {
                throw PlatformUtilities.buildAuraException(ex.getDmlMessage(0));
            }
        }

        SaveResult result = new SaveResult();
        result.hasFailure = hasFailure;
        result.inspectionOutcome = line.InspectionOutcome__c;
        result.outcomeUpdated = false;
        result.checklistComplete = coversStandards(standards, namesWithValues(prepared));

        String nextOutcome = result.inspectionOutcome;
        if (hasFailure && nextOutcome != OUTCOME_P1) {
            nextOutcome = OUTCOME_P1;
        } else if (!hasFailure && !prepared.isEmpty() && nextOutcome == OUTCOME_P1) {
            nextOutcome = OUTCOME_PASSED;
        }
        if (nextOutcome != result.inspectionOutcome) {
            try {
                Database.update(
                    new WorkOrderLineItem(Id = line.Id, InspectionOutcome__c = nextOutcome),
                    AccessLevel.USER_MODE
                );
            } catch (DmlException ex) {
                throw PlatformUtilities.buildAuraException(ex.getDmlMessage(0));
            }
            result.inspectionOutcome = nextOutcome;
            result.outcomeUpdated = true;
        }
        return result;
    }

    /**
     * @description Pass when the value is inside minimum and maximum.
     *              When both bounds are blank, Pass only when the value equals the reference.
     * @param measurementValue Value entered by the user
     * @param referenceValue Reference or default value
     * @param minimumValue Minimum bound. Blank means no minimum.
     * @param maximumValue Maximum bound. Blank means no maximum.
     * @return Pass, Failed, or null when the value is blank
     */
    @TestVisible
    private static String evaluateStatus(
        String measurementValue,
        String referenceValue,
        String minimumValue,
        String maximumValue
    ) {
        String value = measurementValue == null ? '' : measurementValue.trim();
        if (String.isBlank(value)) {
            return null;
        }
        Boolean hasMin = String.isNotBlank(minimumValue);
        Boolean hasMax = String.isNotBlank(maximumValue);
        if (!hasMin && !hasMax) {
            return sameReading(value, referenceValue) ? STATUS_PASS : STATUS_FAILED;
        }
        Decimal entered = parseDecimal(value);
        if (entered == null) {
            return STATUS_FAILED;
        }
        if (hasMin) {
            Decimal minBound = parseDecimal(minimumValue);
            if (minBound == null || entered < minBound) {
                return STATUS_FAILED;
            }
        }
        if (hasMax) {
            Decimal maxBound = parseDecimal(maximumValue);
            if (maxBound == null || entered > maxBound) {
                return STATUS_FAILED;
            }
        }
        return STATUS_PASS;
    }

    private class PreparedRow {
        public Id measurementId;
        public String name;
        public String referenceValue;
        public String measurementValue;
        public String comments;
        public String status;
    }

    /**
     * @description Builds a validated row. Device Standard bounds come from the product, not the client.
     * @param input Submitted row
     * @param standardsById Device Standards for the asset product
     * @param productId Asset product
     * @param submittedStandardIds Standards included in this save
     * @return Row ready to store
     */
    private static PreparedRow prepareRow(
        MeasurementInput input,
        Map<Id, DeviceStandard> standardsById,
        Id productId,
        Set<Id> submittedStandardIds
    ) {
        String name;
        String referenceValue;
        String minimumValue;
        String maximumValue;
        if (input.standardId != null) {
            DeviceStandard standard = standardsById.get(input.standardId);
            if (standard == null || standard.product2Id != productId) {
                throw PlatformUtilities.buildAuraException('A Device Standard on this checklist is not for the asset product.');
            }
            if (!submittedStandardIds.add(input.standardId)) {
                throw PlatformUtilities.buildAuraException('Device Standard ' + standard.name + ' was submitted more than once.');
            }
            name = standard.name;
            referenceValue = standard.referenceValue;
            minimumValue = standard.minimumValue;
            maximumValue = standard.maximumValue;
        } else {
            name = input.measurementName == null ? '' : input.measurementName.trim();
            referenceValue = input.referenceValue == null ? '' : input.referenceValue.trim();
            minimumValue = input.minimumValue;
            maximumValue = input.maximumValue;
            if (String.isBlank(name) || String.isBlank(referenceValue)) {
                throw PlatformUtilities.buildAuraException(
                    'Measurement name, reference value, and measurement value are required for a manual measurement.'
                );
            }
        }

        String measurementValue = input.measurementValue == null ? '' : input.measurementValue.trim();
        if (String.isBlank(measurementValue)) {
            throw PlatformUtilities.buildAuraException('Enter a measurement value for ' + name + '.');
        }
        if (name.length() > NAME_MAX) {
            throw PlatformUtilities.buildAuraException(name + ' is longer than ' + NAME_MAX + ' characters.');
        }
        if (referenceValue != null && referenceValue.length() > REFERENCE_MAX) {
            throw PlatformUtilities.buildAuraException(
                'Reference value for ' + name + ' is longer than ' + REFERENCE_MAX + ' characters.'
            );
        }
        if (measurementValue.length() > VALUE_MAX) {
            throw PlatformUtilities.buildAuraException(
                'Measurement value for ' + name + ' is longer than ' + VALUE_MAX + ' characters.'
            );
        }

        String status = evaluateStatus(measurementValue, referenceValue, minimumValue, maximumValue);
        PreparedRow row = new PreparedRow();
        row.measurementId = input.measurementId;
        row.name = name;
        row.referenceValue = referenceValue;
        row.measurementValue = measurementValue;
        row.comments = input.comments;
        row.status = status;
        return row;
    }

    /**
     * @description Product Serviced line the running user can read.
     * @param workOrderLineItemId Line Id
     * @return Line with asset product and work order status
     */
    private static WorkOrderLineItem queryLine(Id workOrderLineItemId) {
        if (workOrderLineItemId == null) {
            throw PlatformUtilities.buildAuraException('Save the Product Serviced line before opening Inspection.');
        }
        List<WorkOrderLineItem> lines = [
            SELECT Id, AssetId, Asset.Product2Id, WorkOrderId, WorkOrder.Status, InspectionOutcome__c
            FROM WorkOrderLineItem
            WHERE Id = :workOrderLineItemId
                AND LineType__c = :LINE_TYPE_PRODUCT_SERVICED
            WITH USER_MODE
            LIMIT 1
        ];
        if (lines.isEmpty()) {
            throw PlatformUtilities.buildAuraException('The Product Serviced line could not be opened.');
        }
        return lines[0];
    }

    /**
     * @description Active visible Device Standards for one product.
     * @param productId Asset product
     * @return Standards in related-list order
     */
    private static List<DeviceStandard> standardsForProduct(Id productId) {
        if (productId == null) {
            return new List<DeviceStandard>();
        }
        List<DeviceStandard> standards = standardsByProduct(new Set<Id>{ productId }).get(productId);
        return standards == null ? new List<DeviceStandard>() : standards;
    }

    /**
     * @description Active visible Device Standards grouped by product.
     * @param productIds Asset products
     * @return Standards keyed by product Id
     */
    private static Map<Id, List<DeviceStandard>> standardsByProduct(Set<Id> productIds) {
        Map<Id, List<DeviceStandard>> byProduct = new Map<Id, List<DeviceStandard>>();
        if (productIds == null || productIds.isEmpty()) {
            return byProduct;
        }
        if (Test.isRunningTest() && testStandardsById != null) {
            for (DeviceStandard standard : testStandardsById.values()) {
                if (!productIds.contains(standard.product2Id)) {
                    continue;
                }
                if (!byProduct.containsKey(standard.product2Id)) {
                    byProduct.put(standard.product2Id, new List<DeviceStandard>());
                }
                byProduct.get(standard.product2Id).add(standard);
            }
            return byProduct;
        }
        for (ProductAttributeDefinition definition : new StandardReader().selectForProducts(productIds)) {
            DeviceStandard standard = toStandard(definition);
            if (!byProduct.containsKey(definition.Product2Id)) {
                byProduct.put(definition.Product2Id, new List<DeviceStandard>());
            }
            byProduct.get(definition.Product2Id).add(standard);
        }
        return byProduct;
    }

    /**
     * @description Maps a Device Standard record into the checklist shape.
     * @param definition ProductAttributeDefinition row
     * @return Device standard
     */
    private static DeviceStandard toStandard(ProductAttributeDefinition definition) {
        DeviceStandard standard = new DeviceStandard();
        standard.standardId = definition.Id;
        standard.product2Id = definition.Product2Id;
        standard.name = definition.Name;
        standard.referenceValue = definition.DefaultValue;
        standard.minimumValue = definition.MinimumValue;
        standard.maximumValue = definition.MaximumValue;
        return standard;
    }

    /**
     * @description PMI measurement names that already have a value, keyed by line.
     * @param lineIds Product Serviced line Ids
     * @return Names keyed by line Id
     */
    private static Map<Id, Set<String>> measuredNamesByLine(Set<Id> lineIds) {
        Map<Id, Set<String>> namesByLine = new Map<Id, Set<String>>();
        for (Measurement__c measurement : [
            SELECT WorkOrderLineItem__c, Name, MeasurementValue__c
            FROM Measurement__c
            WHERE WorkOrderLineItem__c IN :lineIds
                AND MeasurementType__c = :MEASUREMENT_TYPE_PMI
            WITH USER_MODE
        ]) {
            if (String.isBlank(measurement.MeasurementValue__c)) {
                continue;
            }
            if (!namesByLine.containsKey(measurement.WorkOrderLineItem__c)) {
                namesByLine.put(measurement.WorkOrderLineItem__c, new Set<String>());
            }
            namesByLine.get(measurement.WorkOrderLineItem__c).add(measurement.Name);
        }
        return namesByLine;
    }

    /**
     * @description Latest PMI measurement for each name on the line.
     * @param workOrderLineItemId Product Serviced line Id
     * @return Measurements keyed by name
     */
    private static Map<String, Measurement__c> measurementsByName(Id workOrderLineItemId) {
        Map<String, Measurement__c> byName = new Map<String, Measurement__c>();
        for (Measurement__c measurement : [
            SELECT Id, Name, ReferenceValue__c, MeasurementValue__c, Comments__c, Status__c, CreatedDate
            FROM Measurement__c
            WHERE WorkOrderLineItem__c = :workOrderLineItemId
                AND MeasurementType__c = :MEASUREMENT_TYPE_PMI
            WITH USER_MODE
            ORDER BY CreatedDate ASC
        ]) {
            byName.put(measurement.Name, measurement);
        }
        return byName;
    }

    /**
     * @description True when every Device Standard name has a measurement value.
     * @param standards Device Standards for the product
     * @param measuredNames Names that have a value
     * @return True when the checklist is satisfied
     */
    private static Boolean coversStandards(List<DeviceStandard> standards, Set<String> measuredNames) {
        if (standards == null || standards.isEmpty()) {
            return true;
        }
        for (DeviceStandard standard : standards) {
            if (measuredNames == null || !measuredNames.contains(standard.name)) {
                return false;
            }
        }
        return true;
    }

    /**
     * @description Names of prepared rows. Every prepared row has a value.
     * @param rows Rows about to be saved
     * @return Measurement names
     */
    private static Set<String> namesWithValues(List<PreparedRow> rows) {
        Set<String> names = new Set<String>();
        for (PreparedRow row : rows) {
            names.add(row.name);
        }
        return names;
    }

    /**
     * @description True when both readings are the same number, or the same text when either is not numeric.
     * @param entered Value entered by the user
     * @param reference Reference or default value
     * @return True when the readings match
     */
    private static Boolean sameReading(String entered, String reference) {
        String expected = reference == null ? '' : reference.trim();
        Decimal enteredNumber = parseDecimal(entered);
        Decimal expectedNumber = parseDecimal(expected);
        if (enteredNumber != null && expectedNumber != null) {
            return enteredNumber == expectedNumber;
        }
        return entered == expected;
    }

    /**
     * @description Parses a reading. Blank and non-numeric text return null.
     * @param value Reading text
     * @return Decimal value, or null
     */
    private static Decimal parseDecimal(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Decimal.valueOf(value.trim());
        } catch (Exception ex) {
            return null;
        }
    }

    /**
     * @description Reads Device Standards in system mode after the caller has already read the line.
     *              Field technicians can open the asset, but do not always have access to ProductAttributeDefinition.
     */
    private without sharing class StandardReader {
        /**
         * @description Active Device Standards shown on the product related list.
         * @param productIds Asset products
         * @return Device Standard records
         */
        public List<ProductAttributeDefinition> selectForProducts(Set<Id> productIds) {
            return [
                SELECT Id, Name, Product2Id, DefaultValue, MinimumValue, MaximumValue, Sequence
                FROM ProductAttributeDefinition
                WHERE Product2Id IN :productIds
                    AND Status = 'Active'
                    AND IsHidden = false
                ORDER BY Sequence NULLS LAST, Name
            ];
        }
    }
}