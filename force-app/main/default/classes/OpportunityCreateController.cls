/**
 * @author Abhishek Mishra
 * @date 06-17-2026
 * @description Controller used by the custom Opportunity creation LWC to retrieve
 *              duplicate Opportunities and record type field configuration.
 */
public with sharing class OpportunityCreateController {

    /**
     * @description Checks for open duplicate Opportunities using Address, Primary Contact,
     *              Opportunity Type, and Territory Id derived from TAS address data.
     *
     * @param addressId Selected Opportunity Address record Id.
     * @param primaryContactId Selected Primary Contact record Id.
     * @param opportunityType Selected Opportunity Type value.
     * @return List of matching open Opportunities.
     */
    @AuraEnabled(cacheable=false)
    public static List<Opportunity> checkDuplicateOpportunity(
        Id addressId,
        Id primaryContactId,
        String opportunityType
    ) {
        try {
            Logger.debug('OpportunityCreateController.checkDuplicateOpportunity: started');

            if (
                addressId == null ||
                primaryContactId == null ||
                String.isBlank(opportunityType)
            ) {
                Logger.debug(
                    'OpportunityCreateController.checkDuplicateOpportunity: required input is missing'
                );
                return new List<Opportunity>();
            }

            Schema.Address addressRecord = [
                SELECT Id, AddressID__c
                FROM Address
                WHERE Id = :addressId
                LIMIT 1
            ];

            if (String.isBlank(addressRecord.AddressID__c)) {
                Logger.debug(
                    'OpportunityCreateController.checkDuplicateOpportunity: AddressID__c is blank'
                );
                return new List<Opportunity>();
            }

            List<OrderLineContact__c> orderLineContacts = [
                SELECT TerritoryID__c
                FROM OrderLineContact__c
                WHERE TASAddressId__c = :addressRecord.AddressID__c
                AND TerritoryID__c != null
                LIMIT 1
            ];

            if (orderLineContacts.isEmpty()) {
                Logger.debug(
                    'OpportunityCreateController.checkDuplicateOpportunity: no territory found for TAS address'
                );
                return new List<Opportunity>();
            }

            String duplicateKey = (
                String.valueOf(addressId) +
                String.valueOf(primaryContactId) +
                opportunityType +
                orderLineContacts[0].TerritoryID__c
            ).trim().toLowerCase();

            List<Opportunity> duplicateOpportunities = [
                SELECT Id,
                       Name,
                       Account.Name,
                       Address__r.Street,
                       PrimaryContact__r.Name,
                       Type,
                       Owner.Name,
                       StageName,
                       CloseDate
                FROM Opportunity
                WHERE Duplicate_Match_Key__c = :duplicateKey
                AND IsClosed = false
                ORDER BY CreatedDate DESC
            ];

            Logger.debug(
                'OpportunityCreateController.checkDuplicateOpportunity: completed, duplicateCount=' +
                duplicateOpportunities.size()
            );

            return duplicateOpportunities;

        } catch (Exception e) {
            Logger.error(
                'OpportunityCreateController.checkDuplicateOpportunity',
                e
            );
            throw e;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Wrapper returned to LWC containing field configuration for a record type.
     */
    public class FieldConfigResponse {
        @AuraEnabled public String recordTypeName;
        @AuraEnabled public List<FieldConfigField> leftFields;
        @AuraEnabled public List<FieldConfigField> rightFields;
    }

    /**
     * @description Wrapper returned to LWC for each configured field.
     */
    public class FieldConfigField {
        @AuraEnabled public String apiName;
        @AuraEnabled public Boolean required;
    }

    /**
     * @description Retrieves active Opportunity field configuration from Custom Metadata.
     *
     * @return List of field configuration records grouped by record type.
     */
    @AuraEnabled(cacheable=true)
    public static List<FieldConfigResponse> getFieldConfigs() {
        List<FieldConfigResponse> responses = new List<FieldConfigResponse>();

        for (Opportunity_Field_Config__mdt config : [
            SELECT Record_Type_Name__c,
                   Left_Fields__c,
                   Right_Fields__c,
                   Active__c
            FROM Opportunity_Field_Config__mdt
            WHERE Active__c = true
        ]) {
            FieldConfigResponse response = new FieldConfigResponse();
            response.recordTypeName = config.Record_Type_Name__c;
            response.leftFields = parseFields(config.Left_Fields__c);
            response.rightFields = parseFields(config.Right_Fields__c);

            responses.add(response);
        }

        return responses;
    }

    /**
     * @description Parses comma-separated field API names and identifies required fields
     *              using the configured asterisk suffix.
     *
     * @param fieldText Comma-separated field list from Custom Metadata.
     * @return Parsed field configuration list.
     */
    private static List<FieldConfigField> parseFields(String fieldText) {
        List<FieldConfigField> fields = new List<FieldConfigField>();

        if (String.isBlank(fieldText)) {
            return fields;
        }

        for (String rawField : fieldText.split(',')) {
            if (String.isBlank(rawField)) {
                continue;
            }

            String cleanedField = rawField.trim();
            Boolean isRequired = cleanedField.endsWith('*');

            if (isRequired) {
                cleanedField = cleanedField.replace('*', '').trim();
            }

            FieldConfigField fieldConfig = new FieldConfigField();
            fieldConfig.apiName = cleanedField;
            fieldConfig.required = isRequired;

            fields.add(fieldConfig);
        }

        return fields;
    }
}