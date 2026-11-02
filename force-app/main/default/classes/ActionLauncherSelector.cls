/**
 * @author PWC Developer
 * @date 2026/08/28
 *
 * @group Action Launcher
 *
 * @description
 * GC-3346 - SOQL-only selector for Action Launcher custom buttons and merge-field records.
 */
public with sharing class ActionLauncherSelector {

    private static final String LINK_TYPE_URL = 'url';

    /**
     * @description
     * GC-3346 - Selects URL custom buttons for the provided object and API names.
     *
     * @param objectApiName Current record object API name.
     * @param webLinkNameSet Custom button API names without the object prefix.
     * @return Matching URL custom button records.
     */
    public static List<WebLink> selectUrlWebLinks(
        String objectApiName,
        Set<String> webLinkNameSet
    ) {
        if (
            String.isBlank(objectApiName) ||
            webLinkNameSet == null ||
            webLinkNameSet.isEmpty()
        ) {
            return new List<WebLink>();
        }

        return [
            SELECT
                Id,
                Name,
                MasterLabel,
                Url,
                LinkType,
                OpenType
            FROM WebLink
            WHERE PageOrSobjectType = :objectApiName
            AND Name IN :webLinkNameSet
            AND LinkType = :LINK_TYPE_URL
        ];
    }

    /**
     * @description
     * GC-3346 - Selects one source record using object and field names validated by the service.
     *
     * @param recordId Current record id.
     * @param objectApiName Validated object API name.
     * @param fieldNameSet Validated and accessible field API names.
     * @return Source record used to resolve custom button merge fields.
     */
    public static SObject selectRecordById(
        String recordId,
        String objectApiName,
        Set<String> fieldNameSet
    ) {
        if (
            String.isBlank(recordId) ||
            String.isBlank(objectApiName) ||
            fieldNameSet == null ||
            fieldNameSet.isEmpty()
        ) {
            return null;
        }

        String queryString =
            'SELECT ' + String.join(new List<String>(fieldNameSet), ', ') +
            ' FROM ' + objectApiName +
            ' WHERE Id = :recordId' +
            ' WITH USER_MODE' +
            ' LIMIT 1';
        List<SObject> recordList = Database.query(queryString);

        return recordList.isEmpty() ? null : recordList[0];
    }
}