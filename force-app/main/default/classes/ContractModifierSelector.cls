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
}