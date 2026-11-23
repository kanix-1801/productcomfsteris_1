/**
 * @author Vinay Soni
 * @date 2026/11/12
 * @description GW-4777/5676 - SOQL - only selector for Contract Adjustment Object
 */

public with sharing class ContractAdjustmentSelector extends SoqlQueryBuilder {

	/**
	 * @description Type__c value for Model Qty coverage records.
	 */
	public static final String TYPE_MODEL_QTY = 'Model Qty';

	/**
	 * @description Type__c value for Inclusion / Exclusion rule records.
	 */
	public static final String TYPE_INC_EXC = 'Inc/Exc';

	/**
	 * @description Type__c value for Pricing Program records (one per program picked on the line).
	 */
	public static final String TYPE_PRICING_PROGRAM = 'Pricing Program';

	/**
	 * @description Type__c value for On Location - Mobile Van records (one per instrument service category).
	 */
	public static final String TYPE_MOBILE_VAN = 'On Location - Mobile Van';

	/**
	 * @description InclusionExclusionType__c values.
	 */
	public static final String INCLUSION = 'INC';
	public static final String EXCLUSION = 'EXC';

	/**
	 * @description Record type for Model Qty records.
	 */
	public static final Id MODEL_QTY_RECORD_TYPE_ID = Schema.SObjectType.ContractAdjustment__c
															.getRecordTypeInfosByDeveloperName()
															.get('Model_Qty')
															?.getRecordTypeId();

	/**
	 * @description Record type for Inclusion / Exclusion records.
	 */
	public static final Id INC_EXC_RECORD_TYPE_ID = Schema.SObjectType.ContractAdjustment__c
														  .getRecordTypeInfosByDeveloperName()
														  .get('Inclusion_Exclusion')
														  ?.getRecordTypeId();

	/**
	 * @description Record type for Pricing Program records.
	 */
	public static final Id PRICING_PROGRAM_RECORD_TYPE_ID = Schema.SObjectType.ContractAdjustment__c
																  .getRecordTypeInfosByDeveloperName()
																  .get('Pricing_Program')
																  ?.getRecordTypeId();

	/**
	 * @description Record type for On Location - Mobile Van records.
	 */
	public static final Id MOBILE_VAN_RECORD_TYPE_ID = Schema.SObjectType.ContractAdjustment__c
															 .getRecordTypeInfosByDeveloperName()
															 .get('ONL_Mobile')
															 ?.getRecordTypeId();

	/**
	 * @description PricingProgram__c.Status__c value offered in the Pricing Programs search.
	 */
	public static final String PRICING_PROGRAM_STATUS_ACTIVE = 'Active';

	/**
	 * @description PricingProgram__c.Type__c value offered in the ONL Pricing Program search (On Location - Mobile Van).
	 */
	public static final String PRICING_PROGRAM_TYPE_MOBILE_VAN = 'On Location - Mobile Van';

	public ContractAdjustmentSelector() {
		this.objectName = 'ContractAdjustment__c';
	}
}