/**
 * @author PWC Developer
 * @date 2026/07/16
 *
 * @group Record Type Permission Set Assignment
 *
 * @description
 * GC-3175 - SOQL selector for Record_Type_Permission_Set_Mapping__mdt queries.
 */
public with sharing class RecordTypePermissionSetMappingSelector {

    /**
     * @description
     * Returns all active record type permission set mappings.
     *
     * @return Active mapping records.
     */
    public static List<Record_Type_Permission_Set_Mapping__mdt> selectActiveMappings() {
        return [
            SELECT
                Id,
                MasterLabel,
                DeveloperName,
                Object_API_Name__c,
                Record_Type_Developer_Name__c,
                Permission_Set_API_Name__c,
                Active__c
            FROM Record_Type_Permission_Set_Mapping__mdt
            WHERE Active__c = TRUE
            ORDER BY Object_API_Name__c, MasterLabel
        ];
    }

    /**
     * @description
     * Returns active mappings for the provided object API name.
     *
     * @param objectApiName Object API name.
     * @return Active mapping records for the object.
     */
    public static List<Record_Type_Permission_Set_Mapping__mdt> selectActiveMappingsByObject(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return new List<Record_Type_Permission_Set_Mapping__mdt>();
        }

        return [
            SELECT
                Id,
                MasterLabel,
                DeveloperName,
                Object_API_Name__c,
                Record_Type_Developer_Name__c,
                Permission_Set_API_Name__c,
                Active__c
            FROM Record_Type_Permission_Set_Mapping__mdt
            WHERE Active__c = TRUE
            AND Object_API_Name__c = :objectApiName
            ORDER BY MasterLabel
        ];
    }
}