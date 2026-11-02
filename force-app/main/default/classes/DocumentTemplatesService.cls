/**
 * @description GW-3600 - Resolves active Document Template rows for Repair Center document generation.
 */
public with sharing class DocumentTemplatesService {
    /**
     * @description GW-3600 - Returns the newest active Document Template Id for a name.
     * @param templateName Document template name configured in Document Template Designer.
     * @return Active template Id, or null when the name is blank or no active template exists.
     */
    public static Id selectActiveIdByName(String templateName) {
        if (String.isBlank(templateName)) {
            return null;
        }
        return selectActiveIdsByNames(new Set<String>{ templateName }).get(templateName);
    }

    /**
     * @description GW-3600 - Returns the newest active Document Template Id for each name.
     *              When several active versions share a name, the highest VersionNumber is kept.
     * @param templateNames Template names to resolve.
     * @return Template name to active template Id. Empty when no name is provided or none match.
     */
    public static Map<String, Id> selectActiveIdsByNames(Set<String> templateNames) {
        Map<String, Id> templateIdByName = new Map<String, Id>();
        List<String> names = new List<String>();
        if (templateNames != null) {
            for (String templateName : templateNames) {
                if (String.isNotBlank(templateName)) {
                    names.add(templateName);
                }
            }
        }
        if (names.isEmpty()) {
            return templateIdByName;
        }

        SoqlQueryBuilder query = new DocumentTemplateSelector()
            .selectFields(new List<String>{ 'Id', 'Name' })
            .whereEquals('IsActive', true);
        List<String> nameFilterNumbers = new List<String>();
        Integer filterNumber = 2;
        for (String templateName : names) {
            query.whereEquals('Name', templateName);
            nameFilterNumbers.add(String.valueOf(filterNumber));
            filterNumber++;
        }
        if (names.size() > 1) {
            query.withFilterLogic('1 AND (' + String.join(nameFilterNumbers, ' OR ') + ')');
        }

        List<DocumentTemplate> templates = (List<DocumentTemplate>) query.orderByDesc('VersionNumber').execute();

        for (DocumentTemplate template : templates) {
            if (!templateIdByName.containsKey(template.Name)) {
                templateIdByName.put(template.Name, template.Id);
            }
        }
        return templateIdByName;
    }
}