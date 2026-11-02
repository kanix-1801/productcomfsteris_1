/**
 * @author Vinay Soni
 * @date 2026/10/22
 * @description GW-4777/5676 - SOQL - only selector for Contract Modifier Object
 */

public with sharing class ContractModifierSelector extends SoqlQueryBuilder {

    /**
     * @description Type__c value for Model Qty coverage records.
     */
    public static final String TYPE_MODEL_QTY = 'MODEL QTY';

    /**
     * @description Type__c value for Inclusion / Exclusion rule records.
     */
    public static final String TYPE_INC_EXC = 'INC/EXC';

    /**
     * @description InclusionExclusionType__c values.
     */
    public static final String INCLUSION = 'INC';
    public static final String EXCLUSION = 'EXC';

    /**
     * @description Record type for Model Qty records (the default record type does not allow MODEL QTY).
     */
    public static final Id MODEL_QTY_RECORD_TYPE_ID = Schema.SObjectType.ContractModifier__c
                                                            .getRecordTypeInfosByDeveloperName()
                                                            .get('Model_Qty')
                                                            ?.getRecordTypeId();

    /**
     * @description Record type for Inclusion / Exclusion records.
     */
    public static final Id INC_EXC_RECORD_TYPE_ID = Schema.SObjectType.ContractModifier__c
                                                          .getRecordTypeInfosByDeveloperName()
                                                          .get('Inclusion_Exclusion')
                                                          ?.getRecordTypeId();

    public ContractModifierSelector() {
        this.objectName = 'ContractModifier__c';
    }

    /**
     * @description GW-4777/5676 Selects the Model Qty and Inclusion / Exclusion Contract Modifiers of the given
     *              quote line items, oldest first.
     * @param quoteLineItemIds Quote Line Item Ids.
     * @return List of Contract Modifier records with Type__c = MODEL QTY or INC/EXC.
     */
    public static List<ContractModifier__c> selectAdjustmentsByQuoteLineItemIds(Set<Id> quoteLineItemIds) {
        if (quoteLineItemIds == null || quoteLineItemIds.isEmpty()) {
            return new List<ContractModifier__c>();
        }

        // Must stay a List<Id> at runtime: binding a List<Object> to an Id column fails in SOQL.
        List<Object> lineIdValues = new List<Id>(quoteLineItemIds);
        List<Object> typeValues = new List<String>{ TYPE_MODEL_QTY, TYPE_INC_EXC };
        return (List<ContractModifier__c>) SoqlQueryBuilder.fromObject('ContractModifier__c')
                                                           .selectFields(new List<String>{
                                                               'Id', 'Type__c', 'InclusionExclusionType__c',
                                                               'ParentContractModifier__c', 'ProductLine__c',
                                                               'SubProductLine__c', 'ProductType__c', 'Manufacture__c',
                                                               'Model__c', 'ModelQty__c', 'QuoteLineItem__c',
                                                               'Quote__c', 'StartDate__c', 'EndDate__c'
                                                           })
                                                           .whereField('QuoteLineItem__c', 'IN', lineIdValues)
                                                           .whereField('Type__c', 'IN', typeValues)
                                                           .orderBy('CreatedDate')
                                                           .execute();
    }
}