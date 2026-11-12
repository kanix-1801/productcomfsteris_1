/**
* @author Sahithi PWC
* @date 01-07-2026
* @description #GC-3162,GC-3294 Service class for Oracle Pricing integration.
*              #GC-3317 Added Prospect Account Record Type routing to Boomi pricing.
*              #GC-3621 Lost Business uses the same Weekly x52 and Monthly x12 unit price adjustment.
*/
public with sharing class OraclePricingIntegrationService {

    private static final String CLASS_NAME = 'OraclePricingIntegrationService';
    private static final String SCENARIO = 'Oracle Unit Pricing Integration';
    private static final Integer MAX_SKUS_PER_REQUEST =
        Integer.valueOf(System.Label.MAX_SKUS_PER_REQUEST);
    private static final String SOURCE_SYSTEM = System.Label.Source_System;

    private static final String RECORD_TYPE_PROSPECT = 'Prospect';

    private static String pricingFrequencyType(Opportunity opp) {
        if (opp.RecordType != null && opp.RecordType.DeveloperName == 'HCSalesLostBusinessConsumables') {
            return 'Recurring Consumption';
        }
        return opp.Type;
    }

    public class UpdateResult {
        public Boolean allProductsPriced = true;
        public List<String> deletedProductNames = new List<String>();
        public List<Id> deletedOliIds = new List<Id>();
        public List<Id> updatedOliIds = new List<Id>();
    }

    public class FlowRequest {
        @InvocableVariable(required = true)
        public Id opportunityId;
    }

    /**
     * Flow / button entry point. Enqueues async pricing so callouts do not block save.
     */
    @InvocableMethod(
        label = 'Get Oracle Pricing'
        description = 'Calls Oracle Pricing API, updates prices, and deletes unpriced products.'
    )
    public static void invokeFromFlow(List<FlowRequest> requests) {
        if (requests == null || requests.isEmpty() || requests[0].opportunityId == null) {
            return;
        }

        enqueuePricing(requests[0].opportunityId);
    }

    /**
     * Trigger entry point. Enqueues the same async pricing job as Flow.
     */
    public static void enqueuePricing(Id opportunityId) {
        if (opportunityId == null) {
            return;
        }

        System.enqueueJob(new OraclePricingFlowQueueable(opportunityId));
    }

    /**
     * Processes all Opportunity Products, updates pricing, and deletes unpriced OLIs.
     */
    public static void processOpportunity(Id opportunityId) {
        List<Id> allDeletedOliIds = new List<Id>();

        try {
            List<String> allDeletedProducts = new List<String>();
            Set<Id> allUpdatedOliIds = new Set<Id>();

            Logger.setScenario(SCENARIO);
            Logger.info(CLASS_NAME + '.processOpportunity: started');

            if (opportunityId == null) {
                Logger.debug(CLASS_NAME + '.processOpportunity: Opportunity Id is null');
                return;
            }

            Opportunity opp = [
                SELECT Id,
                Type,
                    RecordType.DeveloperName,
                    AccountId,
                    Account.RecordType.DeveloperName,
                    Account.OrgIDs__c,
                    Account.AccountNumber,
                    Account.OracleAddressId__c,
                    Account.Price_List__c,
                    Account.Price_List__r.Price_List_ID__c
                FROM Opportunity
                WHERE Id = :opportunityId
                LIMIT 1
            ];

            List<OpportunityLineItem> lineItems = [
                SELECT Id,
                    UnitPrice,
                    Contract__c,
                    Quantity,
                    PricebookEntry.Product2.Name,
                    ProductCode,
                    ConsumptionFrequency__c
                FROM OpportunityLineItem
                WHERE OpportunityId = :opportunityId
                ORDER BY CreatedDate
            ];

            if (lineItems.isEmpty()) {
                Logger.debug(CLASS_NAME + '.processOpportunity: No Opportunity Products found.');
                return;
            }

            List<List<OpportunityLineItem>> batches = splitLineItems(lineItems);

            for (List<OpportunityLineItem> batch : batches) {
                OraclePricingRequest request = buildRequest(opp, batch);
                UpdateResult updateResult = processBatch(opp, request, batch);

                allDeletedProducts.addAll(updateResult.deletedProductNames);

                allDeletedOliIds.addAll(updateResult.deletedOliIds);
                allUpdatedOliIds.addAll(updateResult.updatedOliIds);
            }

            Boolean allOlisUpdated = lineItems.size() == allUpdatedOliIds.size();

            if (allOlisUpdated) {
                for (OpportunityLineItem oli : lineItems) {
                    if (!allUpdatedOliIds.contains(oli.Id)) {
                        allOlisUpdated = false;
                        break;
                    }
                }
            }

            Opportunity oppUpdate = new Opportunity(Id = opp.Id);
            // Banner true only when every OLI was priced; false if any OLI was deleted or failed.
            oppUpdate.IsOliBannerToBeShown__c =
                allDeletedOliIds.isEmpty() && allOlisUpdated;
            oppUpdate.Last_Refreshed_Date_Time_From_Oracle__c = System.now();
            oppUpdate.Deleted_Opportunity_Product__c = allDeletedProducts.isEmpty()
                ? null : '{' + String.join(allDeletedProducts, '} {') + '}';
               

            if (oppUpdate.getPopulatedFieldsAsMap().size() > 1) {
                update oppUpdate;
            }

            if (!allDeletedOliIds.isEmpty()) {
                deleteFailedOlis(allDeletedOliIds);
            }

            Logger.info(
                CLASS_NAME + '.processOpportunity: Completed, deletedOliIds=' +
                allDeletedOliIds.size()
            );
        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.processOpportunity', e);
        } finally {
            Logger.saveLog();
        }
    }

    @TestVisible
    public static OraclePricingRequest buildRequest(
        Opportunity opp,
        List<OpportunityLineItem> batch
    ) {
        if (isProspectAccount(opp)) {
            return buildProspectRequest(opp, batch);
        }
        return buildCustomerRequest(opp, batch);
    }

    @TestVisible
    public static OraclePricingRequest buildCustomerRequest(
        Opportunity opp,
        List<OpportunityLineItem> batch
    ) {
        OraclePricingRequest request = new OraclePricingRequest();
        request.sfOpportunityId = opp.Id;
        request.sourceSystem = SOURCE_SYSTEM;
        request.productPartNumbers = new List<OraclePricingRequest.ProductPartNumber>();

        for (OpportunityLineItem oli : batch) {
            if (String.isBlank(oli.ProductCode)) {
                continue;
            }

            request.productPartNumbers.add(
                new OraclePricingRequest.ProductPartNumber(
                    oli.ProductCode,
                    oli.Quantity
                )
            );
        }

        request.accountType = 'Account';
        request.operatingUnit = opp.Account.OrgIDs__c;
        request.shipToCustomerNumber = opp.Account.AccountNumber;
        request.shipToAddressSiteId = opp.Account.OracleAddressId__c;

        return request;
    }

    @TestVisible
    public static OraclePricingRequest buildProspectRequest(
        Opportunity opp,
        List<OpportunityLineItem> batch
    ) {
        OraclePricingRequest request = new OraclePricingRequest();
        request.sfOpportunityId = opp.Id;
        request.prospectId = opp.AccountId;
        request.priceList = opp.Account.Price_List__r != null
            ? String.valueOf(opp.Account.Price_List__r.Price_List_ID__c): null;
            
        request.sourceSystem = SOURCE_SYSTEM;
        request.productPartNumbers = new List<OraclePricingRequest.ProductPartNumber>();

        for (OpportunityLineItem oli : batch) {
            if (String.isBlank(oli.ProductCode)) {
                continue;
            }

            request.productPartNumbers.add(
                new OraclePricingRequest.ProductPartNumber(
                    oli.ProductCode,
                    oli.Quantity
                )
            );
        }

        return request;
    }

    @TestVisible
    private static Boolean isProspectAccount(Opportunity opp) {
        return opp != null
            && opp.Account != null
            && opp.Account.RecordType.DeveloperName == RECORD_TYPE_PROSPECT;
    }

    @TestVisible
    private static List<List<OpportunityLineItem>> splitLineItems(
        List<OpportunityLineItem> lineItems
    ) {
        List<List<OpportunityLineItem>> batches = new List<List<OpportunityLineItem>>();

        if (lineItems == null || lineItems.isEmpty()) {
            return batches;
        }

        Integer index = 0;

        while (index < lineItems.size()) {
            List<OpportunityLineItem> batch = new List<OpportunityLineItem>();
            Integer endIndex = Math.min(index + MAX_SKUS_PER_REQUEST, lineItems.size());

            for (Integer i = index; i < endIndex; i++) {
                batch.add(lineItems[i]);
            }

            batches.add(batch);
            index = endIndex;
        }

        return batches;
    }

    @TestVisible
    private static UpdateResult processBatch(
        Opportunity opp,
        OraclePricingRequest request,
        List<OpportunityLineItem> batch
    ) {
        if (isProspectAccount(opp)) {
            return processProspectBatch(opp, request, batch);
        }
        return processCustomerBatch(opp, request, batch);
    }

    @TestVisible
    private static UpdateResult processCustomerBatch(
        Opportunity opp,
        OraclePricingRequest request,
        List<OpportunityLineItem> batch
    ) {
        try {
            Logger.info(CLASS_NAME + '.processCustomerBatch: started');

            OracleUnitPricingGateway.CalloutResult result =
                OracleUnitPricingGateway.sendUnitPriceRequest(request);

            Boolean calloutFailed =
                !result.calloutSuccess || String.isNotBlank(result.errorDetail);

            if (calloutFailed) {
                Logger.error(
                    CLASS_NAME + '.processCustomerBatch: Oracle Pricing callout failed, detail=' +
                    result.errorDetail
                ).addTag('Opportunity').setRecord(opp);
                    
                    

                UpdateResult failedResult = new UpdateResult();
                failedResult.allProductsPriced = false;
                return failedResult;
            }

            return updateOpportunityProducts(batch, request, result.parsedResponse, pricingFrequencyType(opp));
        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.processCustomerBatch', e).addTag('Opportunity').setRecord(opp);
               return new UpdateResult();  


           
        }
    }

    @TestVisible
    private static UpdateResult processProspectBatch(
        Opportunity opp,
        OraclePricingRequest request,
        List<OpportunityLineItem> batch
    ) {
        try {
            Logger.info(CLASS_NAME + '.processProspectBatch: started');

            OracleUnitPricingGateway.CalloutResult result =
                OracleUnitPricingGateway.sendProspectPriceRequest(request);

            Boolean calloutFailed =
                !result.calloutSuccess || String.isNotBlank(result.errorDetail);

            if (calloutFailed) {
                Logger.error(
                    CLASS_NAME + '.processProspectBatch: Prospect Pricing callout failed, detail=' + result.errorDetail                   
                ).addTag('Opportunity').setRecord(opp);
                    
                    

                UpdateResult failedResult = new UpdateResult();
                failedResult.allProductsPriced = false;
                return failedResult;
            }

            return updateProspectOpportunityProducts(batch, request, result.parsedResponse, pricingFrequencyType(opp));
        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.processProspectBatch', e).addTag('Opportunity').setRecord(opp);
            return new UpdateResult();
        }
    }

    @TestVisible
    private static UpdateResult updateOpportunityProducts(
        List<OpportunityLineItem> batch,
        OraclePricingRequest request,
        OraclePricingResponse response,
        String opportunityType
    ) {
        return applyPricingToBatch(batch, request, response, true,opportunityType);
    }

    @TestVisible
    private static UpdateResult updateProspectOpportunityProducts(
        List<OpportunityLineItem> batch,
        OraclePricingRequest request,
        OraclePricingResponse response,
        String opportunityType
    ) {
        return applyPricingToBatch(batch, request, response, false, opportunityType);
    }

    @TestVisible
    private static UpdateResult applyPricingToBatch(
        List<OpportunityLineItem> batch,
        OraclePricingRequest request,
        OraclePricingResponse response,
        Boolean setContract,
        String opportunityType
    ) {
        try {
            UpdateResult result = new UpdateResult();

            if (response == null
                || response.priceInfo == null
                || response.priceInfo.isEmpty()) {
                Logger.debug(CLASS_NAME + '.applyPricingToBatch: No pricing returned.');
                result.allProductsPriced = false;
                flagAllForDeletion(batch, result);
                return result;
            }

            Map<String, OraclePricingResponse.PriceInfo> pricingMap =
                OraclePricingResponse.buildPricingMap(response, request);

            List<OpportunityLineItem> updates = new List<OpportunityLineItem>();
            Set<Id> updatedOliIds = new Set<Id>();

            for (Integer i = 0; i < batch.size(); i++) {
                OpportunityLineItem oli = batch[i];
                OraclePricingResponse.PriceInfo pricing = resolvePricingForOli(
                    oli,
                    i,
                    response,
                    pricingMap
                );

                Decimal unitPrice = OraclePricingResponse.resolveUnitPrice(pricing);

if (pricing == null
    || !OraclePricingResponse.isPricingSuccess(
        pricing.messageKey,
        pricing.errorCode
    )
    || unitPrice == null) {
    result.allProductsPriced = false;
    result.deletedOliIds.add(oli.Id);
    continue;
}

// Apply Consumption Frequency
Decimal calculatedUnitPrice = unitPrice;

if (opportunityType == 'Recurring Consumption') {
    if (oli.ConsumptionFrequency__c == 'Weekly') {
        calculatedUnitPrice = unitPrice * 52;
    } else if (oli.ConsumptionFrequency__c == 'Monthly') {
        calculatedUnitPrice = unitPrice * 12;
    }
}

OpportunityLineItem upd = new OpportunityLineItem();
upd.Id = oli.Id;
upd.UnitPrice = calculatedUnitPrice;

if (setContract) {
    upd.Contract__c = pricing.contractNumber;
}

updates.add(upd);
updatedOliIds.add(oli.Id);
            }
             

            if (!updates.isEmpty()) {
                Database.SaveResult[] saveResults = Database.update(updates, false);
                logSaveResults('OpportunityLineItem', saveResults);

                for (Integer i = 0; i < saveResults.size(); i++) {
                    if (saveResults[i].isSuccess()) {
                        result.updatedOliIds.add(updates[i].Id);
                    } else {
                        result.allProductsPriced = false;
                    }
                }
            }

            // Never delete an OLI that was successfully updated.
            if (!updatedOliIds.isEmpty() && !result.deletedOliIds.isEmpty()) {
                List<Id> filteredDeleteIds = new List<Id>();

                for (Id oliId : result.deletedOliIds) {
                    if (!updatedOliIds.contains(oliId)) {
                        filteredDeleteIds.add(oliId);
                    }
                }

                result.deletedOliIds = filteredDeleteIds;
            }

            result.deletedProductNames = buildDeletedProductNames(batch, result.deletedOliIds);
            return result;
        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.applyPricingToBatch', e);
            return new UpdateResult();
        }
    }

    @TestVisible
    private static OraclePricingResponse.PriceInfo resolvePricingForOli(
        OpportunityLineItem oli,
        Integer index,
        OraclePricingResponse response,
        Map<String, OraclePricingResponse.PriceInfo> pricingMap
    ) {
        if (response != null
            && response.priceInfo != null
            && index < response.priceInfo.size()) {
            OraclePricingResponse.PriceInfo byIndex = response.priceInfo[index];

            if (byIndex != null
                && (String.isBlank(byIndex.productPartNumber)
                    || byIndex.productPartNumber == oli.ProductCode)) {
                return byIndex;
            }
        }

        return pricingMap.get(oli.ProductCode);
    }

    @TestVisible
    private static void flagAllForDeletion(
        List<OpportunityLineItem> batch,
        UpdateResult result
    ) {
        for (OpportunityLineItem oli : batch) {
            result.deletedOliIds.add(oli.Id);
        }

        result.deletedProductNames = buildDeletedProductNames(batch, result.deletedOliIds);
    }

    @TestVisible
    private static List<String> buildDeletedProductNames(
        List<OpportunityLineItem> batch,
        List<Id> deletedOliIds
    ) {
        List<String> deletedProductNames = new List<String>();
        Set<Id> deletedOliIdSet = new Set<Id>(deletedOliIds);

        for (OpportunityLineItem oli : batch) {
            if (deletedOliIdSet.contains(oli.Id)) {
                deletedProductNames.add(oli.PricebookEntry.Product2.Name);
            }
        }

        return deletedProductNames;
    }

    @TestVisible
    private static void deleteFailedOlis(List<Id> oliIds) {
        if (oliIds == null || oliIds.isEmpty()) {
            return;
        }

        List<OpportunityLineItem> toDelete = [
            SELECT Id
            FROM OpportunityLineItem
            WHERE Id IN :oliIds
        ];

        if (toDelete.isEmpty()) {
            return;
        }

        Database.DeleteResult[] deleteResults = Database.delete(toDelete, false);
        logDeleteResults('OpportunityLineItem', deleteResults);
    }

    @TestVisible
    private static void logSaveResults(
        String objectName,
        Database.SaveResult[] saveResults
    ) {
        try {
            if (saveResults == null || saveResults.isEmpty()) {
                return;
            }

            Integer successCount = 0;
            Integer failureCount = 0;

            for (Integer i = 0; i < saveResults.size(); i++) {
                if (saveResults[i].isSuccess()) {
                    successCount++;
                } else {
                    failureCount++;
                    for (Database.Error err : saveResults[i].getErrors()) {
                        Logger.error(
                            CLASS_NAME + '.logSaveResults: ' + objectName + ' failed. index=' + i +', statusCode=' + err.getStatusCode() +', message=' + err.getMessage()                           
                        );
                    }
                }
            }

            Logger.debug(
                CLASS_NAME + '.logSaveResults: ' + objectName +', successCount=' + successCount +', failureCount=' + failureCount                               
            );
        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.logSaveResults', e);
        }
    }

    @TestVisible
    private static void logDeleteResults(
        String objectName,
        Database.DeleteResult[] deleteResults
    ) {
        try {
            if (deleteResults == null || deleteResults.isEmpty()) {
                return;
            }

            Integer successCount = 0;
            Integer failureCount = 0;

            for (Integer i = 0; i < deleteResults.size(); i++) {
                if (deleteResults[i].isSuccess()) {
                    successCount++;
                } else {
                    failureCount++;
                    for (Database.Error err : deleteResults[i].getErrors()) {
                        Logger.error(
                            CLASS_NAME + '.logDeleteResults: ' + objectName +' failed. index=' + i +', statusCode=' + err.getStatusCode() +', message=' + err.getMessage()     
                        );
                    }
                }
            }

            Logger.debug(
                CLASS_NAME + '.logDeleteResults: ' + objectName + ', successCount=' + successCount +', failureCount=' + failureCount);          
        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.logDeleteResults', e);
        }
    }
    
}