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

    /**
     * @description Type__c value for Pricing Program records (the org value is mixed case). Not in the
     *              selectAdjustments type filter yet: Pricing Programs are only kept in the line's JSON for now.
     */
    public static final String TYPE_PRICING_PROGRAM = 'Pricing Program';

    /**
     * @description Record type for Pricing Program records.
     */
    public static final Id PRICING_PROGRAM_RECORD_TYPE_ID = Schema.SObjectType.ContractModifier__c
                                                                  .getRecordTypeInfosByDeveloperName()
                                                                  .get('Pricing_Program')
                                                                  ?.getRecordTypeId();

    /**
     * @description PricingProgram__c.Status__c value offered in the Pricing Programs search.
     */
    public static final String PRICING_PROGRAM_STATUS_ACTIVE = 'Active';

    public ContractModifierSelector() {
        this.objectName = 'ContractModifier__c';
    }
}