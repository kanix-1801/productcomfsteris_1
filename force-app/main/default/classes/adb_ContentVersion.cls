/**
 * @description Domain Builder for the ContentVersion SObject.
 *              Provides a fluent API for creating test ContentVersion records.
 *              Inserting a ContentVersion automatically creates the parent ContentDocument.
 *              After persist(), re-query the record for ContentDocumentId if needed.
 */
@IsTest
public class adb_ContentVersion extends adb_DomainBuilder {

    /**
     * @description Constructs a ContentVersion builder with reasonable defaults.
     */
    public adb_ContentVersion() {
        super(ContentVersion.SObjectType);
        set(ContentVersion.Title, 'Test Document ' + String.valueOf(Math.random()).substring(0, 8));
        set(ContentVersion.PathOnClient, 'TestDocument.txt');
        set(ContentVersion.VersionData, Blob.valueOf('Test file content'));
        set(ContentVersion.IsMajorVersion, true);
    }

    /**
     * @description Sets the Title.
     * @param value The title value.
     * @return This builder instance.
     */
    public adb_ContentVersion title(String value) {
        return (adb_ContentVersion) set(ContentVersion.Title, value);
    }

    /**
     * @description Sets the PathOnClient (file name with extension).
     * @param value The path on client value.
     * @return This builder instance.
     */
    public adb_ContentVersion pathOnClient(String value) {
        return (adb_ContentVersion) set(ContentVersion.PathOnClient, value);
    }

    /**
     * @description Sets the VersionData (file body).
     * @param value The version data blob.
     * @return This builder instance.
     */
    public adb_ContentVersion versionData(Blob value) {
        return (adb_ContentVersion) set(ContentVersion.VersionData, value);
    }

    /**
     * @description Sets the Description.
     * @param value The description value.
     * @return This builder instance.
     */
    public adb_ContentVersion description(String value) {
        return (adb_ContentVersion) set(ContentVersion.Description, value);
    }

    /**
     * @description Sets the IsMajorVersion flag.
     * @param value The major version flag.
     * @return This builder instance.
     */
    public adb_ContentVersion isMajorVersion(Boolean value) {
        return (adb_ContentVersion) set(ContentVersion.IsMajorVersion, value);
    }
}