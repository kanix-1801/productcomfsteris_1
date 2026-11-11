/**
 * @author Vinay Soni
 * @date 2026/10/26
 *
 * @group Contract Modifier
 *
 * @description
 * GW-4777 / GW-5676 - Contract Adjustments (Inclusions / Exclusions and Model Qty) for the RCA product
 * configurator. The modelQtyCoverage LWC writes the adjustments as JSON to QuoteLineItem.ModelQtyCoverage__c
 * through the configurator context. When the quote line is saved, syncAdjustmentsFromQuoteLines makes the
 * line's ContractModifier__c records match it:
 *  - MODEL QTY: one record per row (Product Line, Sub Product Line, Product Type, Manufacture, Model and
 *    ModelQty__c = maximum covered devices).
 *  - INC/EXC: one INC record per inclusion and one EXC record per exclusion, the exclusion pointing to its
 *    inclusion through ParentContractModifier__c.
 * A blank criteria field means "any value". Every record carries the line's term (Start/End Date) and is
 * linked to the Quote and the Quote Line Item.
 * Pricing Programs: reads the active PricingProgram__c records and their CT codes (PricingProgramLines__c) for
 * the LWC search. The programs picked are kept in the JSON ("pricingPrograms"); no records are created yet.
 */
public with sharing class ContractModifierService {

    private static final String CLASS_NAME = 'ContractModifierService';
    private static final String SCENARIO = 'Contract Adjustments';
    private static final String LOGGER_TAG = 'ContractAdjustments';

    /**
     * @description Quote Line Item field that holds the adjustments JSON.
     */
    public static final String COVERAGE_FIELD = 'ModelQtyCoverage__c';

    private static final Integer MODEL_MAX_LENGTH = 100; // ContractModifier__c.Model__c
    private static final Integer MANUFACTURER_MAX_LENGTH = 255; // ContractModifier__c.Manufacture__c
    private static final Integer QTY_MAX = 99999; // ModelQty__c is Number(5, 0)
    private static final Integer MAX_ASSETS = 10000;
    private static final Integer PRICING_PROGRAM_MIN_SEARCH_LENGTH = 3; // same as the LWC
    private static final Integer PRICING_PROGRAM_MAX_RESULTS = 50;
    /**
     * @description Restricted picklists the criteria are written to, by JSON property.
     */
    private static final Map<String, Schema.SObjectField> PICKLIST_FIELD_MAP = new Map<String, Schema.SObjectField>{
        'productLine' => ContractModifier__c.ProductLine__c,
        'subProductLine' => ContractModifier__c.SubProductLine__c,
        'productType' => ContractModifier__c.ProductType__c
    };

    /**
     * @description Active picklist values by JSON property: lower-cased value -> API value (loaded once).
     */
    private static Map<String, Map<String, String>> picklistValueMap;

    /**
     * @description Quote lines already synced in this transaction (recursion guard, per record).
     */
    @TestVisible
    private static final Set<Id> processedLineIdSet = new Set<Id>();

    /**
     * @description Equipment described by up to five fields; a blank field means any value. Shared with the
     *              LWC, so the property names are also the JSON keys stored in ModelQtyCoverage__c.
     */
    public virtual class Criteria {
        public String productLine;
        public String subProductLine;
        public String productType;
        public String manufacturer;
        public String model;
    }

    /**
     * @description One Model Qty row: the equipment and the maximum number of devices covered.
     */
    public class ModelQtyEntry extends Criteria {
        public Decimal qty;
    }

    /**
     * @description One inclusion and the exclusions that narrow it.
     */
    public class InclusionRule extends Criteria {
        public List<Criteria> exclusions = new List<Criteria>();
    }

    /**
     * @description The adjustments entered for one quote line (the ModelQtyCoverage__c JSON).
     */
    public class ContractAdjustments {
        public List<InclusionRule> inclusions = new List<InclusionRule>();
        public List<ModelQtyEntry> models = new List<ModelQtyEntry>();
        public List<PricingProgramEntry> pricingPrograms = new List<PricingProgramEntry>();
        public String pricingProgram; // legacy single value, passed through unchanged
    }

    /**
     * @description Repair assets that share the same five values, with how many there are. Drives the Model
     *              Qty pickers and the Matching Assets count in the LWC.
     */
    public class AssetGroup {
        @AuraEnabled public String productLine;
        @AuraEnabled public String subProductLine;
        @AuraEnabled public String productType;
        @AuraEnabled public String manufacturer;
        @AuraEnabled public String model;
        @AuraEnabled public Integer assetCount = 0;
    }

    /**
     * @description One CT code of a pricing program (a PricingProgramLines__c record), as stored in the JSON.
     */
    public class PricingProgramCtCode {
        @AuraEnabled public String code; // CategoryCode__c
        @AuraEnabled public String name; // CategoryCodeName__c
    }

    /**
     * @description A pricing program picked on the line: the "pricingPrograms" rows of ModelQtyCoverage__c.
     */
    public virtual class PricingProgramEntry {
        @AuraEnabled public String programId; // PricingProgram__c.Id
        @AuraEnabled public String program; // PricingProgram__c.Name, e.g. PP-0009 (the LWC row key)
        @AuraEnabled public String description; // DisplayName__c, or ProgramName__c
        @AuraEnabled public List<PricingProgramCtCode> ctCodes = new List<PricingProgramCtCode>();
    }

    /**
     * @description A pricing program offered in the LWC search: the stored entry plus fields that are only shown
     *              or searched, not saved.
     */
    public class PricingProgramOption extends PricingProgramEntry {
        @AuraEnabled public String category; // ProductLine__c
        @AuraEnabled public String manufacturer;
        @AuraEnabled public String deviceType;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
    }

    /**
     * @description An inclusion record to insert and its exclusions, inserted once the inclusion has an Id.
     */
    private class PendingInclusion {
        ContractModifier__c inclusion;
        List<ContractModifier__c> exclusionList = new List<ContractModifier__c>();
    }

    /**
     * @description Reads ModelQtyCoverage__c JSON. Blank or unreadable JSON returns null. JSON saved before
     *              the Contract Adjustments layout (models with model/qty only) still reads.
     * @param raw JSON stored in QuoteLineItem.ModelQtyCoverage__c
     * @return Parsed adjustments, or null
     */
    public static ContractAdjustments parseCoverage(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        try {
            ContractAdjustments adjustments = (ContractAdjustments) JSON.deserialize(raw, ContractAdjustments.class);
            if (adjustments == null) {
                return null;
            }
            if (adjustments.models == null) {
                adjustments.models = new List<ModelQtyEntry>();
            }
            if (adjustments.inclusions == null) {
                adjustments.inclusions = new List<InclusionRule>();
            }
            for (InclusionRule rule : adjustments.inclusions) {
                if (rule != null && rule.exclusions == null) {
                    rule.exclusions = new List<Criteria>();
                }
            }
            if (adjustments.pricingPrograms == null) {
                adjustments.pricingPrograms = new List<PricingProgramEntry>();
            }
            return adjustments;
        } catch (JSONException e) {
            Logger.warn(CLASS_NAME + '.parseCoverage: unreadable ' + COVERAGE_FIELD + ' JSON', e).addTag(LOGGER_TAG);
            return null;
        }
    }

    /**
     * @description After insert/update of Quote Line Items: for each line whose ModelQtyCoverage__c changed (or,
     *              for a line with adjustments, whose Start/End Date changed), inserts, updates and deletes its
     *              MODEL QTY and INC/EXC Contract Modifiers so they match the JSON, with the line's term. A blank
     *              value removes them. Failures are rolled back and logged, and do not block the save.
     * @param newLineList Trigger.new
     * @param oldLineMap Trigger.oldMap (null on insert)
     */
    public static void syncAdjustmentsFromQuoteLines(List<QuoteLineItem> newLineList, Map<Id, QuoteLineItem> oldLineMap) {
        Map<Id, QuoteLineItem> changedLineMap = new Map<Id, QuoteLineItem>();
        for (QuoteLineItem line : newLineList) {
            if (!needsSync(line, oldLineMap == null ? null : oldLineMap.get(line.Id))) {
                continue; // change detection: nothing new to sync
            }
            if (processedLineIdSet.contains(line.Id)) {
                Logger.debug(CLASS_NAME + '.syncAdjustmentsFromQuoteLines: line already synced', line.Id)
                      .addTag(LOGGER_TAG);
                continue;
            }
            changedLineMap.put(line.Id, line);
        }
        if (changedLineMap.isEmpty()) {
            return;
        }
        processedLineIdSet.addAll(changedLineMap.keySet());

        Logger.setScenario(SCENARIO);
        List<ContractModifier__c> toInsertList = new List<ContractModifier__c>();
        List<ContractModifier__c> toUpdateList = new List<ContractModifier__c>();
        List<ContractModifier__c> toDeleteList = new List<ContractModifier__c>();
        List<PendingInclusion> pendingList = new List<PendingInclusion>();
        Savepoint savepointRecord = Database.setSavepoint();
        try {
            Map<Id, List<ContractModifier__c>> modelQtyByLineIdMap = new Map<Id, List<ContractModifier__c>>();
            Map<Id, List<ContractModifier__c>> incExcByLineIdMap = new Map<Id, List<ContractModifier__c>>();
            for (ContractModifier__c rec : selectAdjustments(changedLineMap.keySet())) {
                Map<Id, List<ContractModifier__c>> targetMap = rec.Type__c == ContractModifierSelector.TYPE_INC_EXC
                    ? incExcByLineIdMap : modelQtyByLineIdMap;
                if (!targetMap.containsKey(rec.QuoteLineItem__c)) {
                    targetMap.put(rec.QuoteLineItem__c, new List<ContractModifier__c>());
                }
                targetMap.get(rec.QuoteLineItem__c).add(rec);
            }

            for (QuoteLineItem line : changedLineMap.values()) {
                String raw = (String) line.get(COVERAGE_FIELD);
                ContractAdjustments adjustments = parseCoverage(raw);
                if (adjustments == null && String.isNotBlank(raw)) {
                    continue; // unreadable JSON (already logged): leave the existing records alone
                }
                planModelQtyChanges(line, adjustments == null ? null : adjustments.models,
                                    listFor(modelQtyByLineIdMap, line.Id), toInsertList, toUpdateList, toDeleteList);
                planIncExcChanges(line, adjustments == null ? null : adjustments.inclusions,
                                  listFor(incExcByLineIdMap, line.Id), pendingList, toUpdateList, toDeleteList);
            }

            if (!toDeleteList.isEmpty()) {
                delete as user toDeleteList;
            }
            if (!toUpdateList.isEmpty()) {
                update as user toUpdateList;
            }
            for (PendingInclusion pending : pendingList) {
                toInsertList.add(pending.inclusion);
            }
            if (!toInsertList.isEmpty()) {
                insert as user toInsertList;
            }
            // Exclusions need their inclusion's Id, so they go in a second insert.
            List<ContractModifier__c> exclusionInsertList = new List<ContractModifier__c>();
            for (PendingInclusion pending : pendingList) {
                for (ContractModifier__c exclusion : pending.exclusionList) {
                    exclusion.ParentContractModifier__c = pending.inclusion.Id;
                    exclusionInsertList.add(exclusion);
                }
            }
            if (!exclusionInsertList.isEmpty()) {
                insert as user exclusionInsertList;
            }
            Logger.info(CLASS_NAME + '.syncAdjustmentsFromQuoteLines: '
                        + (toInsertList.size() + exclusionInsertList.size()) + ' inserted, '
                        + toUpdateList.size() + ' updated, ' + toDeleteList.size() + ' deleted').addTag(LOGGER_TAG);
        } catch (Exception e) {
            // Not rethrown: a failed sync must not block the configurator's quote save. Rolled back so a line
            // is never left with half of its adjustments.
            Database.rollback(savepointRecord);
            Logger.error(CLASS_NAME + '.syncAdjustmentsFromQuoteLines: Contract Modifier sync failed',
                         (List<SObject>) changedLineMap.values(), e).addTag(LOGGER_TAG);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Saved adjustments for a quote line, for the LWC: the line's ModelQtyCoverage__c JSON, or,
     *              when that is blank, the adjustments rebuilt from its Contract Modifiers.
     * @param quoteLineItemId Quote Line Item Id
     * @return Adjustments (never null)
     */
    public static ContractAdjustments getContractAdjustments(Id quoteLineItemId) {
        ContractAdjustments adjustments = new ContractAdjustments();
        if (quoteLineItemId == null) {
            return adjustments;
        }
        QuoteLineItem lineRecord = (QuoteLineItem) new QuoteLineItemSelector()
            .selectField(COVERAGE_FIELD)
            .whereEquals('Id', quoteLineItemId)
            .first();
        ContractAdjustments saved = lineRecord == null ? null : parseCoverage(lineRecord.ModelQtyCoverage__c);
        if (saved != null) {
            return saved;
        }

        Map<Id, InclusionRule> inclusionByIdMap = new Map<Id, InclusionRule>();
        List<ContractModifier__c> exclusionRecordList = new List<ContractModifier__c>();
        for (ContractModifier__c rec : selectAdjustments(new Set<Id>{ quoteLineItemId })) {
            if (rec.Type__c == ContractModifierSelector.TYPE_MODEL_QTY) {
                ModelQtyEntry entry = new ModelQtyEntry();
                readCriteria(rec, entry);
                entry.qty = rec.ModelQty__c;
                adjustments.models.add(entry);
            } else if (rec.InclusionExclusionType__c == ContractModifierSelector.EXCLUSION) {
                exclusionRecordList.add(rec);
            } else {
                InclusionRule rule = new InclusionRule();
                readCriteria(rec, rule);
                inclusionByIdMap.put(rec.Id, rule);
                adjustments.inclusions.add(rule);
            }
        }
        for (ContractModifier__c rec : exclusionRecordList) {
            InclusionRule parent = inclusionByIdMap.get(rec.ParentContractModifier__c);
            if (parent != null) {
                Criteria exclusion = new Criteria();
                readCriteria(rec, exclusion);
                parent.exclusions.add(exclusion);
            }
        }
        return adjustments;
    }

    /**
     * @description Valid Sub Product Lines for a Product Line, from active products (master data).
     * @param productLine Product Line value
     * @return Distinct Sub Product Line values, sorted; empty when no Product Line is given
     */
    public static List<String> getSubProductLines(String productLine) {
        List<String> subProductLineList = new List<String>();
        if (String.isBlank(productLine)) {
            return subProductLineList;
        }

        List<Product2> productList = (List<Product2>) new Product2Selector()
            .selectField('SubProductLine__c')
            .whereEquals('IsActive', true)
            .whereEquals('ProductLine__c', productLine)
            .whereField('SubProductLine__c', '!=', null)
            .orderBy('SubProductLine__c')
            .execute();
        // Distinct values, ignoring case like GROUP BY; the first spelling in sort order is kept.
        Set<String> seenSet = new Set<String>();
        for (Product2 productRecord : productList) {
            if (seenSet.add(productRecord.SubProductLine__c.toLowerCase())) {
                subProductLineList.add(productRecord.SubProductLine__c);
            }
        }
        return subProductLineList;
    }

    /**
     * @description Manufacturers of the repair assets on the quote's account and its parent accounts, narrowed
     *              to a Product Line and Sub Product Line (Inclusion / Exclusion Manufacturer picker).
     * @param quoteId Quote Id
     * @param productLine Product Line to match, ignoring case (optional)
     * @param subProductLine Sub Product Line to match, ignoring case (optional)
     * @return Distinct manufacturer names, sorted
     */
    public static List<String> getManufacturers(Id quoteId, String productLine, String subProductLine) {
        List<String> manufacturerList = new List<String>();
        List<Object> accountIdValues = quoteAccountIds(quoteId);
        if (accountIdValues.isEmpty()) {
            return manufacturerList;
        }

        List<String> fieldList = new List<String>{
            'Id', 'ManufacturerCalculated__c', 'ProductLineCalculated__c', 'SubProductLineCalculated__c'
        };
        Set<String> seenSet = new Set<String>();
        for (Asset assetRecord : selectAccountAssets(fieldList, accountIdValues)) {
            String manufacturer = text(assetRecord, 'ManufacturerCalculated__c')?.trim();
            if (String.isBlank(manufacturer)
                    || !matches(productLine, text(assetRecord, 'ProductLineCalculated__c'))
                    || !matches(subProductLine, text(assetRecord, 'SubProductLineCalculated__c'))
                    || seenSet.contains(manufacturer.toLowerCase())) {
                continue;
            }
            seenSet.add(manufacturer.toLowerCase());
            manufacturerList.add(manufacturer);
        }
        manufacturerList.sort();
        return manufacturerList;
    }

    /**
     * @description The repair assets on the quote's account and its parent accounts, grouped by Product Line,
     *              Sub Product Line, Product Type, Manufacturer and Model. Product Line / Sub Product Line /
     *              Product Type are returned as Contract Modifier picklist values (blank when the asset's value
     *              is not one), so a value picked from them can be saved.
     * @param quoteId Quote Id
     * @return Asset groups with their asset counts, sorted
     */
    public static List<AssetGroup> getAssetCatalog(Id quoteId) {
        Map<String, AssetGroup> groupByKeyMap = new Map<String, AssetGroup>();
        List<Object> accountIdValues = quoteAccountIds(quoteId);
        if (accountIdValues.isEmpty()) {
            return groupByKeyMap.values();
        }

        List<String> fieldList = new List<String>{
            'Id', 'ProductLineCalculated__c', 'SubProductLineCalculated__c', 'ProductTypeCalculated__c',
            'ManufacturerCalculated__c', 'ModelCalculated__c'
        };
        for (Asset assetRecord : selectAccountAssets(fieldList, accountIdValues)) {
            AssetGroup assetGroup = new AssetGroup();
            assetGroup.productLine = toPicklistValue('productLine', text(assetRecord, 'ProductLineCalculated__c'));
            assetGroup.subProductLine = toPicklistValue(
                'subProductLine', text(assetRecord, 'SubProductLineCalculated__c')
            );
            assetGroup.productType = toPicklistValue('productType', text(assetRecord, 'ProductTypeCalculated__c'));
            assetGroup.manufacturer = blankToNull(text(assetRecord, 'ManufacturerCalculated__c')?.trim());
            assetGroup.model = blankToNull(text(assetRecord, 'ModelCalculated__c')?.trim());

            String key = joinKey(new List<String>{
                assetGroup.productLine, assetGroup.subProductLine, assetGroup.productType,
                assetGroup.manufacturer, assetGroup.model
            }).toLowerCase();
            if (!groupByKeyMap.containsKey(key)) {
                groupByKeyMap.put(key, assetGroup);
            }
            groupByKeyMap.get(key).assetCount++;
        }

        List<String> keyList = new List<String>(groupByKeyMap.keySet());
        keyList.sort();
        List<AssetGroup> groupList = new List<AssetGroup>();
        for (String key : keyList) {
            groupList.add(groupByKeyMap.get(key));
        }
        return groupList;
    }

    /**
     * @description Active, in-date pricing programs whose name, program name, display name, or one of whose CT
     *              codes / CT names contains the search text, each with its CT codes (Pricing Programs search).
     * @param searchTerm Text typed in the LWC (3 characters minimum)
     * @return Matching programs sorted by name (at most 50); empty for a blank or too-short term
     */
    public static List<PricingProgramOption> searchPricingPrograms(String searchTerm) {
        String term = searchTerm?.trim();
        if (String.isBlank(term) || term.length() < PRICING_PROGRAM_MIN_SEARCH_LENGTH) {
            return new List<PricingProgramOption>();
        }
        return toPricingProgramOptions(selectPricingPrograms(toLikeTerm(term), null, Date.today()));
    }

    /**
     * @description Pricing programs by name with their current CT codes, to refresh the rows saved on a line.
     *              No status or date filter, so a program that has since expired still shows on an older quote.
     * @param programNames PricingProgram__c names, e.g. PP-0009
     * @return The programs found, sorted by name
     */
    public static List<PricingProgramOption> getPricingProgramsByNames(List<String> programNames) {
        Set<String> nameSet = new Set<String>();
        for (String name : programNames == null ? new List<String>() : programNames) {
            if (String.isNotBlank(name)) {
                nameSet.add(name.trim());
            }
        }
        if (nameSet.isEmpty()) {
            return new List<PricingProgramOption>();
        }
        return toPricingProgramOptions(selectPricingPrograms(null, nameSet, null));
    }

    /* =====================  MODEL QTY  ===================== */

    /**
     * @description Adds one line's Model Qty inserts, updates and deletes to the lists. A row is matched to an
     *              existing record by its five criteria (ignoring case). Invalid or duplicate rows are skipped
     *              and logged.
     */
    private static void planModelQtyChanges(
        QuoteLineItem line,
        List<ModelQtyEntry> entryList,
        List<ContractModifier__c> existingList,
        List<ContractModifier__c> toInsertList,
        List<ContractModifier__c> toUpdateList,
        List<ContractModifier__c> toDeleteList
    ) {
        Map<String, ContractModifier__c> existingByKeyMap = new Map<String, ContractModifier__c>();
        for (ContractModifier__c rec : existingList) {
            Criteria criteria = new Criteria();
            readCriteria(rec, criteria);
            String key = hasAnyValue(criteria) ? criteriaKey(criteria).toLowerCase() : null;
            if (key == null || existingByKeyMap.containsKey(key)) {
                toDeleteList.add(rec); // blank or duplicate row: not a valid coverage row
            } else {
                existingByKeyMap.put(key, rec);
            }
        }

        Set<String> keptKeySet = new Set<String>();
        for (ModelQtyEntry entry : entryList == null ? new List<ModelQtyEntry>() : entryList) {
            Criteria criteria = normalize(entry);
            if (criteria == null || !isValidQty(entry.qty)) {
                Logger.warn(CLASS_NAME + '.planModelQtyChanges: skipped invalid row ' + JSON.serialize(entry),
                            line.Id).addTag(LOGGER_TAG);
                continue;
            }
            String key = criteriaKey(criteria).toLowerCase();
            if (keptKeySet.contains(key)) {
                Logger.warn(CLASS_NAME + '.planModelQtyChanges: skipped duplicate row ' + JSON.serialize(entry),
                            line.Id).addTag(LOGGER_TAG);
                continue;
            }
            keptKeySet.add(key);

            ContractModifier__c existing = existingByKeyMap.get(key);
            if (existing == null) {
                ContractModifier__c rec = newRecord(line, ContractModifierSelector.TYPE_MODEL_QTY,
                                                    ContractModifierSelector.MODEL_QTY_RECORD_TYPE_ID, criteria);
                rec.ModelQty__c = entry.qty;
                toInsertList.add(rec);
            } else if (isCriteriaChanged(existing, criteria) || existing.ModelQty__c != entry.qty
                    || isTermChanged(existing, line)) {
                ContractModifier__c rec = new ContractModifier__c(Id = existing.Id, ModelQty__c = entry.qty);
                applyCriteria(rec, criteria);
                applyTerm(rec, line);
                toUpdateList.add(rec);
            }
        }

        for (String key : existingByKeyMap.keySet()) {
            if (!keptKeySet.contains(key)) {
                toDeleteList.add(existingByKeyMap.get(key));
            }
        }
    }

    /* =====================  INCLUSIONS / EXCLUSIONS  ===================== */

    /**
     * @description Adds one line's Inclusion / Exclusion changes. When the rules are unchanged only the term is
     *              updated; otherwise the line's INC/EXC records are replaced (an exclusion belongs to one
     *              inclusion, so rules are not matched one by one). Invalid or duplicate rules are skipped and
     *              logged; an invalid inclusion skips its exclusions too.
     */
    private static void planIncExcChanges(
        QuoteLineItem line,
        List<InclusionRule> ruleList,
        List<ContractModifier__c> existingList,
        List<PendingInclusion> pendingList,
        List<ContractModifier__c> toUpdateList,
        List<ContractModifier__c> toDeleteList
    ) {
        List<InclusionRule> desiredList = validInclusions(line, ruleList);
        if (incExcSignature(desiredList) == incExcSignature(existingList)) {
            for (ContractModifier__c rec : existingList) {
                if (isTermChanged(rec, line)) {
                    ContractModifier__c updated = new ContractModifier__c(Id = rec.Id);
                    applyTerm(updated, line);
                    toUpdateList.add(updated);
                }
            }
            return;
        }

        toDeleteList.addAll(existingList);
        for (InclusionRule rule : desiredList) {
            PendingInclusion pending = new PendingInclusion();
            pending.inclusion = newRecord(line, ContractModifierSelector.TYPE_INC_EXC,
                                          ContractModifierSelector.INC_EXC_RECORD_TYPE_ID, rule);
            pending.inclusion.InclusionExclusionType__c = ContractModifierSelector.INCLUSION;
            for (Criteria exclusion : rule.exclusions) {
                ContractModifier__c rec = newRecord(line, ContractModifierSelector.TYPE_INC_EXC,
                                                    ContractModifierSelector.INC_EXC_RECORD_TYPE_ID, exclusion);
                rec.InclusionExclusionType__c = ContractModifierSelector.EXCLUSION;
                pending.exclusionList.add(rec);
            }
            pendingList.add(pending);
        }
    }

    // Normalized inclusions to store, each with its normalized exclusions.
    private static List<InclusionRule> validInclusions(QuoteLineItem line, List<InclusionRule> ruleList) {
        List<InclusionRule> resultList = new List<InclusionRule>();
        Set<String> seenSet = new Set<String>();
        for (InclusionRule rule : ruleList == null ? new List<InclusionRule>() : ruleList) {
            Criteria criteria = normalize(rule);
            String key = criteria == null ? null : criteriaKey(criteria).toLowerCase();
            if (key == null || seenSet.contains(key)) {
                Logger.warn(CLASS_NAME + '.validInclusions: skipped invalid or duplicate inclusion '
                            + JSON.serialize(rule), line.Id).addTag(LOGGER_TAG);
                continue;
            }
            seenSet.add(key);

            InclusionRule result = new InclusionRule();
            copyCriteria(criteria, result);
            Set<String> seenExclusionSet = new Set<String>();
            for (Criteria exclusion : rule.exclusions == null ? new List<Criteria>() : rule.exclusions) {
                Criteria normalized = normalize(exclusion);
                String exclusionKey = normalized == null ? null : criteriaKey(normalized).toLowerCase();
                if (exclusionKey == null || seenExclusionSet.contains(exclusionKey)) {
                    Logger.warn(CLASS_NAME + '.validInclusions: skipped invalid or duplicate exclusion '
                                + JSON.serialize(exclusion), line.Id).addTag(LOGGER_TAG);
                    continue;
                }
                seenExclusionSet.add(exclusionKey);
                result.exclusions.add(normalized);
            }
            resultList.add(result);
        }
        return resultList;
    }

    // The rules in order, each inclusion followed by its exclusions (exact values).
    private static String incExcSignature(List<InclusionRule> ruleList) {
        List<String> partList = new List<String>();
        for (InclusionRule rule : ruleList) {
            partList.add(ContractModifierSelector.INCLUSION + ':' + criteriaKey(rule));
            for (Criteria exclusion : rule.exclusions) {
                partList.add(ContractModifierSelector.EXCLUSION + ':' + criteriaKey(exclusion));
            }
        }
        return String.join(partList, '\n');
    }

    // Same signature for the stored records. An exclusion without a stored inclusion makes it differ, so the
    // records are rebuilt.
    private static String incExcSignature(List<ContractModifier__c> recordList) {
        List<InclusionRule> ruleList = new List<InclusionRule>();
        Map<Id, InclusionRule> inclusionByIdMap = new Map<Id, InclusionRule>();
        for (ContractModifier__c rec : recordList) {
            if (rec.InclusionExclusionType__c == ContractModifierSelector.INCLUSION) {
                InclusionRule rule = new InclusionRule();
                readCriteria(rec, rule);
                inclusionByIdMap.put(rec.Id, rule);
                ruleList.add(rule);
            }
        }
        for (ContractModifier__c rec : recordList) {
            if (rec.InclusionExclusionType__c == ContractModifierSelector.INCLUSION) {
                continue;
            }
            InclusionRule parent = inclusionByIdMap.get(rec.ParentContractModifier__c);
            if (parent == null) {
                return 'orphan:' + rec.Id;
            }
            Criteria exclusion = new Criteria();
            readCriteria(rec, exclusion);
            parent.exclusions.add(exclusion);
        }
        return incExcSignature(ruleList);
    }

    /* =====================  Pricing Programs  ===================== */

    // PricingProgram__c records (queried with their lines) -> LWC options. CT codes keep the query order.
    private static List<PricingProgramOption> toPricingProgramOptions(List<PricingProgram__c> programList) {
        List<PricingProgramOption> optionList = new List<PricingProgramOption>();
        for (PricingProgram__c programRecord : programList) {
            PricingProgramOption option = new PricingProgramOption();
            option.programId = programRecord.Id;
            option.program = programRecord.Name;
            option.description = String.isNotBlank(programRecord.DisplayName__c)
                ? programRecord.DisplayName__c : programRecord.ProgramName__c;
            option.category = programRecord.ProductLine__c;
            option.manufacturer = programRecord.Manufacturer__c;
            option.deviceType = programRecord.DeviceType__c;
            option.startDate = programRecord.StartDate__c;
            option.endDate = programRecord.EndDate__c;
            for (PricingProgramLines__c lineRecord : programRecord.PricingProgramLines__r) {
                if (String.isBlank(lineRecord.CategoryCode__c)) {
                    continue; // a line without a CT code product has nothing to show
                }
                PricingProgramCtCode ctCode = new PricingProgramCtCode();
                ctCode.code = lineRecord.CategoryCode__c;
                ctCode.name = lineRecord.CategoryCodeName__c;
                option.ctCodes.add(ctCode);
            }
            optionList.add(option);
        }
        return optionList;
    }

    // "%text%" for a LIKE bind, with the LIKE wildcards typed by the user escaped.
    private static String toLikeTerm(String term) {
        return '%' + term.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_') + '%';
    }

    /* =====================  SHARED HELPERS  ===================== */

    // Coverage JSON changed, or the term changed on a line that has adjustments (never wipes records on a
    // date-only change of a line without JSON).
    private static Boolean needsSync(QuoteLineItem line, QuoteLineItem oldLine) {
        String newValue = (String) line.get(COVERAGE_FIELD);
        if (oldLine == null) {
            return String.isNotBlank(newValue);
        }
        if (newValue != (String) oldLine.get(COVERAGE_FIELD)) {
            return true;
        }
        Boolean termChanged = line.StartDate != oldLine.StartDate || line.EndDate != oldLine.EndDate;
        return termChanged && String.isNotBlank(newValue);
    }

    // Trimmed copy of the criteria, or null when it has no value, a value is too long, or a picklist value
    // is not an active Contract Modifier value.
    private static Criteria normalize(Criteria source) {
        if (source == null) {
            return null;
        }
        Criteria criteria = new Criteria();
        criteria.productLine = blankToNull(source.productLine?.trim());
        criteria.subProductLine = blankToNull(source.subProductLine?.trim());
        criteria.productType = blankToNull(source.productType?.trim());
        criteria.manufacturer = blankToNull(source.manufacturer?.trim());
        criteria.model = blankToNull(source.model?.trim());

        Boolean valid = hasAnyValue(criteria)
            && isValidPicklistValue('productLine', criteria.productLine)
            && isValidPicklistValue('subProductLine', criteria.subProductLine)
            && isValidPicklistValue('productType', criteria.productType)
            && (criteria.manufacturer == null || criteria.manufacturer.length() <= MANUFACTURER_MAX_LENGTH)
            && (criteria.model == null || criteria.model.length() <= MODEL_MAX_LENGTH);
        return valid ? criteria : null;
    }

    private static Boolean hasAnyValue(Criteria criteria) {
        return criteria.productLine != null || criteria.subProductLine != null || criteria.productType != null
            || criteria.manufacturer != null || criteria.model != null;
    }

    private static Boolean isValidQty(Decimal qty) {
        return qty != null && qty == qty.setScale(0) && qty >= 1 && qty <= QTY_MAX;
    }

    private static String criteriaKey(Criteria criteria) {
        return joinKey(new List<String>{
            criteria.productLine, criteria.subProductLine, criteria.productType, criteria.manufacturer, criteria.model
        });
    }

    private static String joinKey(List<String> valueList) {
        List<String> partList = new List<String>();
        for (String value : valueList) {
            partList.add(value == null ? '' : value);
        }
        return String.join(partList, '|');
    }

    private static ContractModifier__c newRecord(QuoteLineItem line, String type, Id recordTypeId, Criteria criteria) {
        ContractModifier__c rec = new ContractModifier__c(
            RecordTypeId = recordTypeId,
            Type__c = type,
            Quote__c = line.QuoteId,
            QuoteLineItem__c = line.Id
        );
        applyCriteria(rec, criteria);
        applyTerm(rec, line);
        return rec;
    }

    private static void applyCriteria(ContractModifier__c rec, Criteria criteria) {
        rec.ProductLine__c = criteria.productLine;
        rec.SubProductLine__c = criteria.subProductLine;
        rec.ProductType__c = criteria.productType;
        rec.Manufacture__c = criteria.manufacturer;
        rec.Model__c = criteria.model;
    }

    private static void readCriteria(ContractModifier__c rec, Criteria criteria) {
        criteria.productLine = rec.ProductLine__c;
        criteria.subProductLine = rec.SubProductLine__c;
        criteria.productType = rec.ProductType__c;
        criteria.manufacturer = rec.Manufacture__c;
        criteria.model = rec.Model__c;
    }

    private static void copyCriteria(Criteria source, Criteria target) {
        target.productLine = source.productLine;
        target.subProductLine = source.subProductLine;
        target.productType = source.productType;
        target.manufacturer = source.manufacturer;
        target.model = source.model;
    }

    // Exact comparison, so a change of case is saved.
    private static Boolean isCriteriaChanged(ContractModifier__c existing, Criteria criteria) {
        Criteria stored = new Criteria();
        readCriteria(existing, stored);
        return !criteriaKey(stored).equals(criteriaKey(criteria));
    }

    private static void applyTerm(ContractModifier__c rec, QuoteLineItem line) {
        rec.StartDate__c = line.StartDate;
        rec.EndDate__c = line.EndDate;
    }

    private static Boolean isTermChanged(ContractModifier__c rec, QuoteLineItem line) {
        return rec.StartDate__c != line.StartDate || rec.EndDate__c != line.EndDate;
    }

    private static Boolean isValidPicklistValue(String property, String value) {
        return value == null || picklistValues(property).values().contains(value);
    }

    // The Contract Modifier picklist value matching an asset value (ignoring case), or null.
    private static String toPicklistValue(String property, String value) {
        return String.isBlank(value) ? null : picklistValues(property).get(value.trim().toLowerCase());
    }

    private static Map<String, String> picklistValues(String property) {
        if (picklistValueMap == null) {
            picklistValueMap = new Map<String, Map<String, String>>();
            for (String key : PICKLIST_FIELD_MAP.keySet()) {
                Map<String, String> valueMap = new Map<String, String>();
                for (Schema.PicklistEntry entry : PICKLIST_FIELD_MAP.get(key).getDescribe().getPicklistValues()) {
                    if (entry.isActive()) {
                        valueMap.put(entry.getValue().toLowerCase(), entry.getValue());
                    }
                }
                picklistValueMap.put(key, valueMap);
            }
        }
        return picklistValueMap.get(property);
    }

    private static List<ContractModifier__c> listFor(Map<Id, List<ContractModifier__c>> recordMap, Id lineId) {
        return recordMap.containsKey(lineId) ? recordMap.get(lineId) : new List<ContractModifier__c>();
    }

    // The quote's account and its parent accounts (empty without a quote or account). Must stay a List<Id> at
    // runtime: binding a List<Object> to an Id column fails in SOQL.
    private static List<Object> quoteAccountIds(Id quoteId) {
        Quote quoteRecord = quoteId == null ? null : (Quote) new QuoteSelector()
            .selectField('AccountId')
            .whereEquals('Id', quoteId)
            .first();
        if (quoteRecord == null || quoteRecord.AccountId == null) {
            return new List<Id>();
        }
        Set<Id> accountIdSet = new Set<Id>{ quoteRecord.AccountId };
        List<AccountAccountRelationship__c> relationshipList =
            (List<AccountAccountRelationship__c>) new AccountAccountRelationshipSelector()
                .selectField('ParentAccount__c')
                .whereEquals('ChildAccount__c', quoteRecord.AccountId)
                .whereField('ParentAccount__c', '!=', null)
                .execute();
        for (AccountAccountRelationship__c rel : relationshipList) {
            accountIdSet.add(rel.ParentAccount__c);
        }
        return new List<Id>(accountIdSet);
    }

    // Model Qty and Inclusion / Exclusion Contract Modifiers of the given quote lines, oldest first.
    private static List<ContractModifier__c> selectAdjustments(Set<Id> quoteLineItemIdSet) {
        if (quoteLineItemIdSet == null || quoteLineItemIdSet.isEmpty()) {
            return new List<ContractModifier__c>();
        }
        // Must stay a List<Id> at runtime: binding a List<Object> to an Id column fails in SOQL.
        List<Object> lineIdValues = new List<Id>(quoteLineItemIdSet);
        List<Object> typeValues = new List<String>{
            ContractModifierSelector.TYPE_MODEL_QTY, ContractModifierSelector.TYPE_INC_EXC
        };
        return (List<ContractModifier__c>) new ContractModifierSelector()
            .selectFields(new List<String>{
                'Id', 'Type__c', 'InclusionExclusionType__c', 'ParentContractModifier__c', 'ProductLine__c',
                'SubProductLine__c', 'ProductType__c', 'Manufacture__c', 'Model__c', 'ModelQty__c',
                'QuoteLineItem__c', 'Quote__c', 'StartDate__c', 'EndDate__c'
            })
            .whereField('QuoteLineItem__c', 'IN', lineIdValues)
            .whereField('Type__c', 'IN', typeValues)
            .orderBy('CreatedDate')
            .execute();
    }

    // Pricing programs with their CT code lines, in USER_MODE. With likeTerm: search mode (Active, in date on
    // asOf, text match). With nameSet: lookup by name, no status or date filter. Inline SOQL because
    // SoqlQueryBuilder has no child subqueries (same approach as WorkOrdersSelector.selectByIdWithLineItems);
    // user input is only ever a bind variable.
    private static List<PricingProgram__c> selectPricingPrograms(String likeTerm, Set<String> nameSet, Date asOf) {
        Map<String, Object> bindMap = new Map<String, Object>{
            'likeTerm' => likeTerm,
            'nameSet' => nameSet,
            'asOf' => asOf,
            'status' => ContractModifierSelector.PRICING_PROGRAM_STATUS_ACTIVE,
            'maxRows' => PRICING_PROGRAM_MAX_RESULTS
        };
        String soql = 'SELECT Id, Name, ProgramName__c, DisplayName__c, ProductLine__c, Manufacturer__c, '
            + 'DeviceType__c, StartDate__c, EndDate__c, '
            + '(SELECT Id, CategoryCode__c, CategoryCodeName__c FROM PricingProgramLines__r '
            + 'ORDER BY CategoryCode__c) '
            // + 'FROM PricingProgram__c';
            + 'FROM PricingProgram__c WHERE '
            + 'Status__c = :status ';
        // if (nameSet != null) {
        //     soql += 'Name IN :nameSet';
        // } else {
        //     soql += 'Status__c = :status '
        //         + 'AND (StartDate__c = null OR StartDate__c <= :asOf) '
        //         + 'AND (EndDate__c = null OR EndDate__c >= :asOf) '
        //         + 'AND (Name LIKE :likeTerm OR ProgramName__c LIKE :likeTerm OR DisplayName__c LIKE :likeTerm '
        //         + 'OR Id IN (SELECT PricingProgram__c FROM PricingProgramLines__c '
        //         + 'WHERE CategoryCode__c LIKE :likeTerm OR CategoryCodeName__c LIKE :likeTerm))';
        // }
        soql += ' ORDER BY Name LIMIT :maxRows';
        return (List<PricingProgram__c>) Database.queryWithBinds(soql, bindMap, AccessLevel.USER_MODE);
    }

    // Assets on the given accounts with the given fields, ordered by serial number (nulls last) and name.
    private static List<Asset> selectAccountAssets(List<String> fieldList, List<Object> accountIdValues) {
        return (List<Asset>) new AssetsSelector()
            .selectFields(fieldList)
            .whereField('AccountId', 'IN', accountIdValues)
            .orderBy('SerialNumber', false, true)
            .orderBy('Name')
            .limitTo(MAX_ASSETS)
            .execute();
    }

    private static Boolean matches(String wanted, String actual) {
        return String.isBlank(wanted) || (actual != null && actual.trim().equalsIgnoreCase(wanted.trim()));
    }

    private static String text(SObject record, String field) {
        Object value = record.get(field);
        return value == null ? null : String.valueOf(value);
    }

    private static String blankToNull(String value) {
        return String.isBlank(value) ? null : value;
    }
}