/**
 * @description Domain Builder for the PermissionSetAssignment SObject.
 *              Provides a fluent API for creating test PermissionSetAssignment records.
 */
@IsTest
public class adb_PermissionSetAssignment extends adb_DomainBuilder {

    /**
     * @description Constructs a PermissionSetAssignment builder.
     */
    public adb_PermissionSetAssignment() {
        super(PermissionSetAssignment.SObjectType);
    }

    /**
     * @description Sets AssigneeId.
     * @param value User Id to assign the permission set to.
     * @return This builder instance.
     */
    public adb_PermissionSetAssignment assigneeId(Id value) {
        return (adb_PermissionSetAssignment) set(PermissionSetAssignment.AssigneeId, value);
    }

    /**
     * @description Sets PermissionSetId.
     * @param value Permission Set Id.
     * @return This builder instance.
     */
    public adb_PermissionSetAssignment permissionSetId(Id value) {
        return (adb_PermissionSetAssignment) set(PermissionSetAssignment.PermissionSetId, value);
    }
}