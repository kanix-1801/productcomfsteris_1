/**
 * @description Selector for DocumentTemplate (GW-3600). Queries are built by
 *              DocumentTemplatesService through SoqlQueryBuilder; this class only binds the object name.
 * @group GW-3600
 */
public with sharing class DocumentTemplateSelector extends SoqlQueryBuilder {
    /**
     * @description GW-3600 - Creates a selector for DocumentTemplate.
     */
    public DocumentTemplateSelector() {
        this.objectName = 'DocumentTemplate';
    }
}