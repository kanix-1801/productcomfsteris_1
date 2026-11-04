/**
 * @author Vinay Soni
 * @date 2026/11/03
 *
 * @group ES Service Product Configurator
 *
 * @description
 * Shared test setup for the ES Service Product Configurator tests (EsServiceAssetSelectionControllerTest,
 * EsServiceProductConfigControllerTest). The controllers query in USER_MODE, so the running user needs
 * access to the ES Service quote line fields; in orgs where the fields were deployed, no profile has it.
 */
@IsTest
public class EsServiceTestDataFactory {

    private static final List<String> FIELD_LIST = new List<String>{
        'QuoteLineItem.Asset__c', 'QuoteLineItem.AssetName__c', 'QuoteLineItem.PFCL__c',
        'QuoteLineItem.PFCLName__c', 'QuoteLineItem.RequestedNumberofPMVisits__c',
        'QuoteLineItem.AssetVisits__c', 'QuoteLineItem.SelectedAssets__c'
    };

    /**
     * @description Grants the running user read access to PFCL__c and read/edit on the ES Service quote line
     *              fields, through a test-only permission set (setup DML isolated with runAs).
     */
    public static void grantAccess() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            PermissionSet permissionSetRecord = new PermissionSet(
                Name = 'EsServiceTestAccess',
                Label = 'ES Service Test Access'
            );
            insert permissionSetRecord;
            insert new ObjectPermissions(
                ParentId = permissionSetRecord.Id,
                SobjectType = 'PFCL__c',
                PermissionsRead = true
            );
            List<FieldPermissions> fieldPermissionList = new List<FieldPermissions>();
            for (String field : FIELD_LIST) {
                fieldPermissionList.add(new FieldPermissions(
                    ParentId = permissionSetRecord.Id,
                    SobjectType = field.substringBefore('.'),
                    Field = field,
                    PermissionsRead = true,
                    PermissionsEdit = true
                ));
            }
            insert fieldPermissionList;
            insert new PermissionSetAssignment(
                AssigneeId = UserInfo.getUserId(),
                PermissionSetId = permissionSetRecord.Id
            );
        }
    }
}