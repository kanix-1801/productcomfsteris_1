/**
 * @description GC-3431 Service layer for EPP capital-equipment and consumable Opportunity Products.
 *
 *              Responsibilities:
 *              1. Confirm the Opportunity is an Equipment Placement Program record with a Price Book.
 *              2. Search and return products separately for Capital Equipment and Consumables.
 *              3. Validate submitted quantities, dates, frequency, and elevated pricing.
 *              4. Insert eligible Opportunity Products and roll back when validation or DML fails.
 * @author      Vinay
 * @date        2026-09-29
 */
public with sharing class EPPProductService {

    private static final String CLASS_NAME = 'EPPProductService';
    private static final String SCENARIO = 'Equipment Placement Program';
    private static final String EPP_RECORD_TYPE = 'HCSalesEquipmentPlacementProgram';
    private static final Set<String> CONSUMPTION_FREQUENCIES =
        new Set<String>{ 'Weekly', 'Monthly', 'Annual', 'One Time' };

    /**
     * @description Searches the Standard Price Book for products eligible for one EPP section.
     * @param opportunityId Equipment Placement Program Opportunity Id.
     * @param isConsumable True for Consumables; false for Capital Equipment.
     * @param searchKey Product name or product code text.
     * @return Product wrappers for the add-product modal.
     */
    public static List<EPPProductController.ProductWrapper> searchProducts(
        Id opportunityId,
        Boolean isConsumable,
        String searchKey
    ) {
        Logger.setScenario(SCENARIO);
        try {
            Logger.info(CLASS_NAME + '.searchProducts: started')
                .addTag('Opportunity')
                .addTag('Price Book Entry');
            Opportunity opportunityRecord = validateOpportunity(opportunityId);
            Boolean consumableFlag = isConsumable == true;
            List<EPPProductController.ProductWrapper> results =
                new List<EPPProductController.ProductWrapper>();

            for (PricebookEntry entry : EPPPricebookEntrySelector.searchEligibleEntries(
                consumableFlag,
                searchKey,
                opportunityRecord.CurrencyIsoCode
            )) {
                EPPProductController.ProductWrapper wrapper =
                    new EPPProductController.ProductWrapper();
                wrapper.pricebookEntryId = entry.Id;
                wrapper.productId = entry.Product2Id;
                wrapper.productName = entry.Product2.Name;
                wrapper.productCode = entry.Product2.ProductCode;
                wrapper.productFamily = String.isNotBlank(entry.Product2.ItemFamily__c)
                    ? entry.Product2.ItemFamily__c
                    : entry.Product2.Family;
                wrapper.businessUnit = entry.Product2.BusinessUnit__c;
                wrapper.productDescription = entry.Product2.Description;
                wrapper.listPrice = entry.UnitPrice;
                results.add(wrapper);
            }

            Logger.info(CLASS_NAME + '.searchProducts: resultCount=' + results.size())
                .addTag('Price Book Entry')
                .setRecord(opportunityRecord);
            return results;
        } catch (EPPProductException validationException) {
            Logger.warn(
                CLASS_NAME + '.searchProducts: ' + validationException.getMessage()
                + ', opportunityId=' + opportunityId
            ).addTag('Opportunity');
            throw validationException;
        } catch (Exception exceptionValue) {
            Logger.error(CLASS_NAME + '.searchProducts', exceptionValue).addTag('Opportunity');
            throw exceptionValue;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Returns saved Opportunity Products for one EPP section.
     * @param opportunityId Equipment Placement Program Opportunity Id.
     * @param isConsumable True for consumable lines; false for capital equipment lines.
     * @return Wrappers used by the EPP product tables.
     */
    public static List<EPPProductController.OpportunityProductWrapper> getOpportunityProducts(
        Id opportunityId,
        Boolean isConsumable
    ) {
        Logger.setScenario(SCENARIO);
        try {
            Logger.info(CLASS_NAME + '.getOpportunityProducts: started')
                .addTag('Opportunity')
                .addTag('Opportunity Product');
            validateOpportunity(opportunityId);
            List<EPPProductController.OpportunityProductWrapper> results =
                new List<EPPProductController.OpportunityProductWrapper>();

            for (OpportunityLineItem line : EPPPricebookEntrySelector.selectLines(
                opportunityId,
                isConsumable == true
            )) {
                EPPProductController.OpportunityProductWrapper wrapper =
                    new EPPProductController.OpportunityProductWrapper();
                wrapper.opportunityLineItemId = line.Id;
                wrapper.productId = line.Product2Id;
                wrapper.productName = line.Product2.Name;
                wrapper.productCode = line.Product2.ProductCode;
                wrapper.productFamily = line.ProductFamily__c;
                wrapper.businessUnit = line.BusinessUnit__c;
                wrapper.quantity = line.Quantity;
                wrapper.unitPrice = line.UnitPrice;
                wrapper.totalPrice = line.TotalPrice;
                wrapper.placementStartDate = line.PlacementStartDate__c;
                wrapper.placementEndDate = line.PlacementEndDate__c;
                wrapper.consumptionFrequency = line.ConsumptionFrequency__c;
                wrapper.elevatedEPPPricingApplicable = line.ElevatedEPPPricingApplicable__c;
                wrapper.eppPrice = line.EPPPrice__c;
                wrapper.commitmentStartDate = line.CommitmentStartDate__c;
                wrapper.commitmentEndDate = line.CommitmentEndDate__c;
                wrapper.annualCommittedRevenue = line.AnnualCommittedRevenue__c;
                wrapper.contractTermRevenue = line.ContractTermRevenue__c;
                results.add(wrapper);
            }

            Logger.info(CLASS_NAME + '.getOpportunityProducts: resultCount=' + results.size())
                .addTag('Opportunity Product');
            return results;
        } catch (EPPProductException validationException) {
            Logger.warn(
                CLASS_NAME + '.getOpportunityProducts: ' + validationException.getMessage()
                + ', opportunityId=' + opportunityId
            ).addTag('Opportunity');
            throw validationException;
        } catch (Exception exceptionValue) {
            Logger.error(CLASS_NAME + '.getOpportunityProducts', exceptionValue)
                .addTag('Opportunity');
            throw exceptionValue;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Validates and inserts the products selected in one EPP section.
     * @param opportunityId Equipment Placement Program Opportunity Id.
     * @param isConsumable True when the submitted products belong to the Consumables section.
     * @param productInputsJson Serialized list of ProductInput values.
     * @return Number of Opportunity Products inserted.
     */
    public static Integer createOpportunityProducts(
        Id opportunityId,
        Boolean isConsumable,
        String productInputsJson
    ) {
        Logger.setScenario(SCENARIO);
        Savepoint savePointValue = Database.setSavepoint();

        try {
            Logger.info(CLASS_NAME + '.createOpportunityProducts: started')
                .addTag('Opportunity')
                .addTag('Opportunity Product');
            Opportunity opportunityRecord = validateOpportunity(opportunityId);
            Boolean consumableFlag = isConsumable == true;
            List<EPPProductController.ProductInput> inputs = parseInputs(productInputsJson);
            validateInputValues(inputs, consumableFlag);

            Set<Id> requestedEntryIds = new Set<Id>();
            for (EPPProductController.ProductInput input : inputs) {
                try {
                    requestedEntryIds.add(Id.valueOf(input.pricebookEntryId));
                } catch (Exception invalidIdException) {
                    throw new EPPProductException('A selected product has an invalid Price Book Entry.');
                }
            }

            if (requestedEntryIds.size() != inputs.size()) {
                throw new EPPProductException('The same product cannot be selected more than once.');
            }

            Map<Id, PricebookEntry> standardEntriesById = new Map<Id, PricebookEntry>(
                EPPPricebookEntrySelector.selectEligibleEntriesByIds(
                    requestedEntryIds,
                    consumableFlag,
                    opportunityRecord.CurrencyIsoCode
                )
            );

            if (standardEntriesById.size() != requestedEntryIds.size()) {
                throw new EPPProductException(
                    'One or more selected products are not eligible for this EPP product section.'
                );
            }

            Map<Id, Id> opportunityEntryIdByStandardId = resolveOpportunityEntries(
                opportunityRecord,
                standardEntriesById
            );

            List<OpportunityLineItem> linesToInsert = new List<OpportunityLineItem>();
            for (EPPProductController.ProductInput input : inputs) {
                Id standardEntryId = Id.valueOf(input.pricebookEntryId);
                PricebookEntry entry = standardEntriesById.get(standardEntryId);
                OpportunityLineItem line = new OpportunityLineItem(
                    OpportunityId = opportunityId,
                    PricebookEntryId = opportunityEntryIdByStandardId.get(standardEntryId),
                    Quantity = input.quantity,
                    UnitPrice = input.unitPrice == null ? entry.UnitPrice : input.unitPrice
                );
                if (consumableFlag) {
                    Boolean elevatedApplies = input.elevatedEPPPricingApplicable == true;
                    line.ConsumptionFrequency__c = input.consumptionFrequency;
                    line.ElevatedEPPPricingApplicable__c = elevatedApplies;
                    line.EPPPrice__c = elevatedApplies ? input.eppPrice : null;
                    line.CommitmentStartDate__c = input.commitmentStartDate;
                    line.CommitmentEndDate__c = input.commitmentEndDate;
                } else {
                    line.PlacementStartDate__c = input.placementStartDate;
                    line.PlacementEndDate__c = input.placementEndDate;
                }
                linesToInsert.add(line);
            }

            insert linesToInsert;
            Logger.info(
                CLASS_NAME + '.createOpportunityProducts: createdCount=' + linesToInsert.size()
            ).addTag('Opportunity Product').setRecord(linesToInsert);
            return linesToInsert.size();
        } catch (EPPProductException validationException) {
            Database.rollback(savePointValue);
            Logger.warn(
                CLASS_NAME + '.createOpportunityProducts: ' + validationException.getMessage()
                + ', opportunityId=' + opportunityId
            ).addTag('Opportunity');
            throw validationException;
        } catch (DmlException dmlExceptionValue) {
            Database.rollback(savePointValue);
            Logger.error(CLASS_NAME + '.createOpportunityProducts', dmlExceptionValue)
                .addTag('Opportunity Product');
            throw new EPPProductException(
                'Unable to add the selected EPP products: ' + dmlExceptionValue.getDmlMessage(0)
            );
        } catch (Exception exceptionValue) {
            Database.rollback(savePointValue);
            Logger.error(CLASS_NAME + '.createOpportunityProducts', exceptionValue)
                .addTag('Opportunity Product');
            throw new EPPProductException(
                'Unable to add the selected EPP products: ' + exceptionValue.getMessage()
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Returns the Opportunity Price Book Entry to use for each selected Standard Price Book Entry.
     *              Creates or reactivates the Opportunity entry when the product is not already on that book.
     * @param opportunityRecord EPP Opportunity that owns the Price Book used for Opportunity Products.
     * @param standardEntriesById Eligible Standard Price Book entries selected in the modal.
     * @return Opportunity Price Book Entry Id keyed by Standard Price Book Entry Id.
     */
    private static Map<Id, Id> resolveOpportunityEntries(
        Opportunity opportunityRecord,
        Map<Id, PricebookEntry> standardEntriesById
    ) {
        Set<Id> productIds = new Set<Id>();
        for (PricebookEntry standardEntry : standardEntriesById.values()) {
            productIds.add(standardEntry.Product2Id);
        }

        Map<Id, PricebookEntry> opportunityEntriesByProductId = new Map<Id, PricebookEntry>();
        List<PricebookEntry> entriesToActivate = new List<PricebookEntry>();
        for (PricebookEntry opportunityEntry : EPPPricebookEntrySelector.selectOpportunityEntries(
            opportunityRecord.Pricebook2Id,
            productIds,
            opportunityRecord.CurrencyIsoCode
        )) {
            opportunityEntriesByProductId.put(opportunityEntry.Product2Id, opportunityEntry);
            if (opportunityEntry.IsActive != true) {
                opportunityEntry.IsActive = true;
                entriesToActivate.add(opportunityEntry);
            }
        }
        if (!entriesToActivate.isEmpty()) {
            update entriesToActivate;
        }

        List<PricebookEntry> entriesToInsert = new List<PricebookEntry>();
        for (PricebookEntry standardEntry : standardEntriesById.values()) {
            if (opportunityEntriesByProductId.containsKey(standardEntry.Product2Id)) {
                continue;
            }
            if (standardEntry.Pricebook2Id == opportunityRecord.Pricebook2Id) {
                opportunityEntriesByProductId.put(standardEntry.Product2Id, standardEntry);
                continue;
            }
            entriesToInsert.add(new PricebookEntry(
                Pricebook2Id = opportunityRecord.Pricebook2Id,
                Product2Id = standardEntry.Product2Id,
                UnitPrice = standardEntry.UnitPrice,
                IsActive = true,
                CurrencyIsoCode = opportunityRecord.CurrencyIsoCode
            ));
        }
        if (!entriesToInsert.isEmpty()) {
            insert entriesToInsert;
            for (PricebookEntry insertedEntry : entriesToInsert) {
                opportunityEntriesByProductId.put(insertedEntry.Product2Id, insertedEntry);
            }
        }

        Map<Id, Id> opportunityEntryIdByStandardId = new Map<Id, Id>();
        for (PricebookEntry standardEntry : standardEntriesById.values()) {
            PricebookEntry opportunityEntry = opportunityEntriesByProductId.get(standardEntry.Product2Id);
            if (opportunityEntry == null) {
                throw new EPPProductException(
                    'The selected product could not be priced for this Opportunity.'
                );
            }
            opportunityEntryIdByStandardId.put(standardEntry.Id, opportunityEntry.Id);
        }
        return opportunityEntryIdByStandardId;
    }

    /**
     * @description Confirms the Opportunity exists, uses the EPP record type, and has a Price Book.
     * @param opportunityId Equipment Placement Program Opportunity Id.
     * @return The validated Opportunity.
     */
    private static Opportunity validateOpportunity(Id opportunityId) {
        if (opportunityId == null) {
            throw new EPPProductException('An Opportunity is required.');
        }

        Opportunity opportunityRecord =
            EPPPricebookEntrySelector.selectOpportunity(opportunityId);
        if (opportunityRecord == null) {
            throw new EPPProductException('The Opportunity could not be found.');
        }
        if (opportunityRecord.RecordType.DeveloperName != EPP_RECORD_TYPE) {
            throw new EPPProductException(
                'Products can only be added from an Equipment Placement Program Opportunity.'
            );
        }
        if (opportunityRecord.Pricebook2Id == null) {
            throw new EPPProductException('The EPP Opportunity does not have a Price Book.');
        }

        return opportunityRecord;
    }

    /**
     * @description Deserializes the product payload submitted by the LWC.
     * @param productInputsJson Serialized list of ProductInput values.
     * @return At least one ProductInput. Throws EPPProductException when the payload is blank or unreadable.
     */
    private static List<EPPProductController.ProductInput> parseInputs(String productInputsJson) {
        if (String.isBlank(productInputsJson)) {
            throw new EPPProductException('Select at least one product before saving.');
        }

        try {
            List<EPPProductController.ProductInput> inputs =
                (List<EPPProductController.ProductInput>) JSON.deserialize(
                    productInputsJson,
                    List<EPPProductController.ProductInput>.class
                );
            if (inputs == null || inputs.isEmpty()) {
                throw new EPPProductException('Select at least one product before saving.');
            }
            return inputs;
        } catch (EPPProductException validationException) {
            throw validationException;
        } catch (Exception parseException) {
            throw new EPPProductException('The selected products could not be read.');
        }
    }

    /**
     * @description Checks quantity, price, and the date or frequency fields required by the selected section.
     *              EPP Price is required whenever elevated pricing is selected.
     * @param inputs Products submitted from the add-product modal.
     * @param isConsumable True for Consumables validation; false for Capital Equipment validation.
     * @return None.
     */
    private static void validateInputValues(
        List<EPPProductController.ProductInput> inputs,
        Boolean isConsumable
    ) {
        for (EPPProductController.ProductInput input : inputs) {
            if (input == null || String.isBlank(input.pricebookEntryId)) {
                throw new EPPProductException('A selected product is missing its Price Book Entry.');
            }
            if (input.quantity == null || input.quantity <= 0) {
                throw new EPPProductException('Quantity must be greater than zero for every product.');
            }
            if (input.unitPrice != null && input.unitPrice < 0) {
                throw new EPPProductException('Sales Price cannot be negative.');
            }

            if (isConsumable) {
                if (String.isBlank(input.consumptionFrequency)
                    || !CONSUMPTION_FREQUENCIES.contains(input.consumptionFrequency)
                ) {
                    throw new EPPProductException(
                        'Select a consumption frequency for every consumable product.'
                    );
                }
                if (input.commitmentStartDate == null || input.commitmentEndDate == null) {
                    throw new EPPProductException(
                        'Enter Commitment Start Date and Commitment End Date for every consumable product.'
                    );
                }
                if (input.commitmentEndDate < input.commitmentStartDate) {
                    throw new EPPProductException(
                        'Commitment End Date cannot be earlier than Commitment Start Date.'
                    );
                }
                if (
                    input.elevatedEPPPricingApplicable == true
                    && input.eppPrice == null
                ) {
                    throw new EPPProductException(
                        'Enter the EPP Price when Elevated / EPP Pricing Applicable is selected.'
                    );
                }
            } else {
                if (input.placementStartDate == null || input.placementEndDate == null) {
                    throw new EPPProductException(
                        'Enter Placement Start Date and Placement End Date for every equipment product.'
                    );
                }
                if (input.placementEndDate < input.placementStartDate) {
                    throw new EPPProductException(
                        'Placement End Date cannot be earlier than Placement Start Date.'
                    );
                }
            }
        }
    }
}