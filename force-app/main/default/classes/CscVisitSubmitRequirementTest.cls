/**
 * @author Abhishek Mishra
 * @date 20-10-2026
 * @description #GC-3518 Tests the submit field messages used when approval skips CSC_002 and CSC_012.
 */
@IsTest(SeeAllData=false)
private class CscVisitSubmitRequirementTest {
    @TestSetup
    static void setupSalesRep() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            User salesRep = new User(
                Alias = 'subrep',
                Email = 'subrep@csc.example.test',
                EmailEncodingKey = 'UTF-8',
                LastName = 'SubmitSalesRep',
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                ProfileId = [SELECT Id FROM Profile WHERE Name = 'Healthcare Sales' LIMIT 1].Id,
                UserRoleId = [SELECT Id FROM UserRole WHERE PortalType = 'None' LIMIT 1].Id,
                TimeZoneSidKey = 'America/New_York',
                Username = 'subrep' + DateTime.now().getTime() + '@csc.example.test'
            );
            insert salesRep;
            PermissionSetGroup permissionSetGroupRecord = [
                SELECT Id, Status
                FROM PermissionSetGroup
                WHERE DeveloperName = 'SalesFieldRepAccountManagerPSG'
                LIMIT 1
            ];
            if (permissionSetGroupRecord.Status != 'Updated') {
                Test.calculatePermissionSetGroup(permissionSetGroupRecord.Id);
            }
            insert new PermissionSetAssignment(
                AssigneeId = salesRep.Id,
                PermissionSetGroupId = permissionSetGroupRecord.Id
            );
        }
    }

    private static User salesRep() {
        return [SELECT Id FROM User WHERE LastName = 'SubmitSalesRep' LIMIT 1];
    }

    @IsTest
    static void blankPurposeBlocksRequestedStatus() {
        System.runAs(salesRep()) {
        Id visitId = fakeId();
        CSC_Visit_Request__c currentVisit = requestedVisit(visitId);
        currentVisit.Visit_Purpose__c = null;

        CscVisitRequestService.requireFieldsOnSubmit(
            new List<CSC_Visit_Request__c>{ currentVisit },
            priorVisits(visitId)
        );

        System.assert(hasMessage(currentVisit, 'Visit Purpose'));
        }
    }

    @IsTest
    static void otherPurposeRequiresExplanation() {
        System.runAs(salesRep()) {
        Id visitId = fakeId();
        CSC_Visit_Request__c currentVisit = requestedVisit(visitId);
        currentVisit.RecordTypeId = Schema.SObjectType.CSC_Visit_Request__c
            .getRecordTypeInfosByDeveloperName()
            .get('CSCVisitRequest')
            .getRecordTypeId();
        currentVisit.Visit_Purpose__c = 'Other';

        CscVisitRequestService.requireFieldsOnSubmit(
            new List<CSC_Visit_Request__c>{ currentVisit },
            priorVisits(visitId)
        );

        System.assert(hasMessage(currentVisit, 'Other is selected'));
        }
    }

    @IsTest
    static void completeRequestHasNoSubmitError() {
        System.runAs(salesRep()) {
        Id visitId = fakeId();
        CSC_Visit_Request__c currentVisit = requestedVisit(visitId);
        currentVisit.Visit_Purpose__c = 'Product Evaluation';

        CscVisitRequestService.requireFieldsOnSubmit(
            new List<CSC_Visit_Request__c>{ currentVisit },
            priorVisits(visitId)
        );

        System.assertEquals(0, currentVisit.getErrors().size());
        }
    }

    private static CSC_Visit_Request__c requestedVisit(Id visitId) {
        return new CSC_Visit_Request__c(
            Id = visitId,
            Status__c = CscVisitRequestSelector.STATUS_REQUESTED,
            Primary_Requested_Date__c = Date.today().addDays(10),
            Backup_Requested_Date__c = Date.today().addDays(12),
            PrimaryObjective__c = 'Review the installed base'
        );
    }

    private static Map<Id, CSC_Visit_Request__c> priorVisits(Id visitId) {
        return new Map<Id, CSC_Visit_Request__c>{
            visitId => new CSC_Visit_Request__c(
                Id = visitId,
                Status__c = CscVisitRequestSelector.STATUS_DRAFT
            )
        };
    }

    private static Boolean hasMessage(CSC_Visit_Request__c visit, String expectedText) {
        for (Database.Error errorRow : visit.getErrors()) {
            if (errorRow.getMessage().contains(expectedText)) {
                return true;
            }
        }
        return false;
    }

    private static Integer sequence = 1;

    private static Id fakeId() {
        String prefix = CSC_Visit_Request__c.SObjectType.getDescribe().getKeyPrefix();
        String suffix = String.valueOf(sequence++);
        return (Id) (prefix + '0'.repeat(12 - suffix.length()) + suffix);
    }
}