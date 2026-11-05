/**
 * @author PWC Developer
 * @date 2026/11/04
 *
 * @group Mock Room / ORI Approval
 *
 * @description
 * GC-3483. One person selected on Submit for Approval.
 * The screen sends this row to the flow. A Salesforce user and an external email are never both stored.
 */
public with sharing class MockRoomORIRecipient {
    @AuraEnabled
    @InvocableVariable(label='User Id' description='GC-3483. Salesforce user on this row. Blank when the person is not in Salesforce.')
    public String userId;

    @AuraEnabled
    @InvocableVariable(label='Email' description='GC-3483. External awareness email. Blank when the person is a Salesforce user.')
    public String email;

    @AuraEnabled
    @InvocableVariable(label='Role' description='GC-3483. Approver or Awareness.')
    public String role;

    @AuraEnabled
    @InvocableVariable(label='Exists In Salesforce' description='GC-3483. True when this person is selected from Salesforce users.')
    public Boolean existsInSalesforce;
}