public with sharing class ModelRepairContractController {

    // Quote Line Item fields for the Include/Exclude and Pricing Program tiles.
    // Rename here if your API names differ.
    private static final String INC_EXC_FIELD = 'IncludeExclude__c';
    private static final String PRICING_FIELD = 'PricingProgram__c';

    /* ---------- response / request shapes ---------- */

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public PicklistOption(String label, String value) { this.label = label; this.value = value; }
    }

    public class ModelRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String model;
        @AuraEnabled public Decimal coveredQuantity;
        @AuraEnabled public Decimal quantityRepaired;
    }

    public class CoverageData {
        @AuraEnabled public List<ModelRow> models = new List<ModelRow>();
        @AuraEnabled public String includeExclude;
        @AuraEnabled public String pricingProgram;
        @AuraEnabled public List<PicklistOption> pricingOptions = new List<PicklistOption>();
    }

    public class ModelEntry {
        @AuraEnabled public String model;
        @AuraEnabled public Decimal coveredQuantity;
    }

    public class SavePayload {
        @AuraEnabled public Boolean updateModels;
        @AuraEnabled public List<ModelEntry> models;
        @AuraEnabled public Boolean updateIncExc;
        @AuraEnabled public String includeExclude;
        @AuraEnabled public Boolean updatePricing;
        @AuraEnabled public String pricingProgram;
    }

    /* ---------- read ---------- */

    @AuraEnabled
    public static CoverageData getData(Id quoteLineItemId) {
        CoverageData data = new CoverageData();
        if (quoteLineItemId == null) {
            return data;
        }
        try {
            for (ContractModifier__c rec : [
                SELECT Id, Model__c, ModelQty__c
                FROM ContractModifier__c
                WHERE QuoteLineItem__c = :quoteLineItemId
                WITH USER_MODE
                ORDER BY CreatedDate
            ]) {
                ModelRow row = new ModelRow();
                row.id = rec.Id;
                row.model = rec.Model__c;
                row.coveredQuantity = rec.ModelQty__c;
                data.models.add(row);
            }

            // Only select the QLI fields that actually exist in this org
            Map<String, Schema.SObjectField> fm = Schema.QuoteLineItem.SObjectType.getDescribe().fields.getMap();
            Boolean hasIncExc = fm.containsKey(INC_EXC_FIELD.toLowerCase());
            Boolean hasPricing = fm.containsKey(PRICING_FIELD.toLowerCase());
            if (hasIncExc || hasPricing) {
                List<String> cols = new List<String>{ 'Id' };
                if (hasIncExc) { cols.add(INC_EXC_FIELD); }
                if (hasPricing) { cols.add(PRICING_FIELD); }
                String soql = 'SELECT ' + String.join(cols, ', ') +
                              ' FROM QuoteLineItem WHERE Id = :quoteLineItemId WITH USER_MODE LIMIT 1';
                List<QuoteLineItem> qlis = Database.query(soql);
                if (!qlis.isEmpty()) {
                    if (hasIncExc) { data.includeExclude = (String) qlis[0].get(INC_EXC_FIELD); }
                    if (hasPricing) { data.pricingProgram = (String) qlis[0].get(PRICING_FIELD); }
                }
            }
            if (hasPricing) {
                for (Schema.PicklistEntry pe : fm.get(PRICING_FIELD.toLowerCase()).getDescribe().getPicklistValues()) {
                    if (pe.isActive()) {
                        data.pricingOptions.add(new PicklistOption(pe.getLabel(), pe.getValue()));
                    }
                }
            }
        } catch (Exception ex) {
            throw buildAuraException('Unable to load coverage details: ' + ex.getMessage());
        }
        return data;
    }

    /* ---------- write (single transaction) ---------- */

    @AuraEnabled
    public static void saveAll(Id quoteLineItemId, SavePayload payload) {
        if (quoteLineItemId == null || payload == null) {
            throw buildAuraException('Quote Line Item is required.');
        }

        // 1) validate everything before touching the database
        Map<String, ModelEntry> entryMap = null;
        if (payload.updateModels == true) {
            entryMap = validateEntries(payload.models);
        }
        Map<String, Schema.SObjectField> fm = Schema.QuoteLineItem.SObjectType.getDescribe().fields.getMap();
        if (payload.updateIncExc == true && !fm.containsKey(INC_EXC_FIELD.toLowerCase())) {
            throw buildAuraException('Field ' + INC_EXC_FIELD + ' was not found on Quote Line Item.');
        }
        if (payload.updatePricing == true && !fm.containsKey(PRICING_FIELD.toLowerCase())) {
            throw buildAuraException('Field ' + PRICING_FIELD + ' was not found on Quote Line Item.');
        }

        // 2) write, all-or-nothing
        Savepoint sp = Database.setSavepoint();
        try {
            QuoteLineItem qli = [
                SELECT Id, QuoteId FROM QuoteLineItem WHERE Id = :quoteLineItemId WITH USER_MODE LIMIT 1
            ];

            if (entryMap != null) {
                applyModels(qli, entryMap);
            }

            if (payload.updateIncExc == true || payload.updatePricing == true) {
                QuoteLineItem upd = new QuoteLineItem(Id = qli.Id);
                if (payload.updateIncExc == true) { upd.put(INC_EXC_FIELD, payload.includeExclude); }
                if (payload.updatePricing == true) { upd.put(PRICING_FIELD, payload.pricingProgram); }
                update as user upd;
            }
        } catch (AuraHandledException ex) {
            Database.rollback(sp);
            throw ex;
        } catch (DmlException ex) {
            Database.rollback(sp);
            throw buildAuraException(ex.getDmlMessage(0));
        } catch (Exception ex) {
            Database.rollback(sp);
            throw buildAuraException(ex.getMessage());
        }
    }

    /* ---------- helpers ---------- */

    private static Map<String, ModelEntry> validateEntries(List<ModelEntry> entries) {
        if (entries == null || entries.isEmpty()) {
            throw buildAuraException('Enter at least one Model and Covered Quantity.');
        }
        Map<String, ModelEntry> byKey = new Map<String, ModelEntry>();
        for (ModelEntry e : entries) {
            String m = String.isBlank(e.model) ? null : e.model.trim();
            if (m == null || e.coveredQuantity == null || e.coveredQuantity < 1
                    || e.coveredQuantity != e.coveredQuantity.setScale(0)) {
                throw buildAuraException('Each row needs a Model and a whole-number Covered Quantity of at least 1.');
            }
            if (m.length() > 100) {
                throw buildAuraException('Model "' + m.left(20) + '..." exceeds 100 characters.');
            }
            String key = m.toLowerCase();
            if (byKey.containsKey(key)) {
                throw buildAuraException('Model "' + m + '" is entered more than once.');
            }
            e.model = m;
            byKey.put(key, e);
        }
        return byKey;
    }

    /**
     * Makes the saved records match the entered list:
     *  - new Model            -> insert (Quantity Repaired = 0)
     *  - existing Model       -> update Covered Quantity only (never reset Quantity Repaired)
     *  - Model no longer listed -> delete, unless it already has repairs
     */
    private static void applyModels(QuoteLineItem qli, Map<String, ModelEntry> entryMap) {
        Map<String, ContractModifier__c> existing = new Map<String, ContractModifier__c>();
        for (ContractModifier__c rec : [
            SELECT Id, Model__c, ModelQty__c
            FROM ContractModifier__c
            WHERE QuoteLineItem__c = :qli.Id
            WITH USER_MODE
        ]) {
            if (String.isNotBlank(rec.Model__c)) {
                existing.put(rec.Model__c.toLowerCase(), rec);
            }
        }

        List<ContractModifier__c> toUpsert = new List<ContractModifier__c>();
        List<ContractModifier__c> toDelete = new List<ContractModifier__c>();

        for (String key : entryMap.keySet()) {
            ModelEntry e = entryMap.get(key);
            ContractModifier__c rec = existing.get(key);
            if (rec != null) {
                Decimal repaired = rec.ModelQty__c == null ? 0 : rec.ModelQty__c;
                if (e.coveredQuantity < repaired) {
                    throw buildAuraException('Model "' + e.model + '": Covered Quantity cannot be less than the '
                        + repaired + ' already repaired.');
                }
                if (rec.ModelQty__c != e.coveredQuantity) {
                    toUpsert.add(new ContractModifier__c(Id = rec.Id, ModelQty__c = e.coveredQuantity));
                }
            } else {
                toUpsert.add(new ContractModifier__c(
                    Model__c = e.model,
                    ModelQty__c = e.coveredQuantity,
                    Quote__c = qli.QuoteId,
                    QuoteLineItem__c = qli.Id
                ));
            }
        }

        for (String key : existing.keySet()) {
            if (!entryMap.containsKey(key)) {
                ContractModifier__c rec = existing.get(key);
                Decimal repaired = rec.ModelQty__c == null ? 0 : rec.ModelQty__c;
                if (repaired > 0) {
                    throw buildAuraException('Model "' + rec.Model__c + '" has ' + repaired
                        + ' repair(s) recorded and cannot be removed.');
                }
                toDelete.add(rec);
            }
        }

        if (!toDelete.isEmpty()) { delete as user toDelete; }
        if (!toUpsert.isEmpty()) { upsert as user toUpsert; }
    }

    // AuraHandledException needs setMessage() or the client only sees "Script-thrown exception"
    private static AuraHandledException buildAuraException(String message) {
        AuraHandledException ahe = new AuraHandledException(message);
        ahe.setMessage(message);
        return ahe;
    }
}