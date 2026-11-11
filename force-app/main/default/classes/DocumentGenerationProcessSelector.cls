/**
 * @description GW-5695 - Selector for DocumentGenerationProcess. Queries are built by the calling service
 *              through SoqlQueryBuilder; this class only binds the object name.
 * @group GW-5695
 */
public with sharing class DocumentGenerationProcessSelector extends SoqlQueryBuilder {
	/**
	 * @description GW-5695 - Creates a selector for DocumentGenerationProcess.
	 */
	public DocumentGenerationProcessSelector() {
		this.objectName = 'DocumentGenerationProcess';
	}
}