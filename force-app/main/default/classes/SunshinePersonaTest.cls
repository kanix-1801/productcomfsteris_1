/**
 * @description Temporary GC-3564 persona check. Removed after the CSC admin test run.
 */
@IsTest(SeeAllData=true)
private class SunshinePersonaTest {

    @IsTest
    static void cscAdminRunsTheStory() {
        User persona = [
            SELECT Id, UserPermissionsInteractionUser
            FROM User
            WHERE Username = 'morgan.ellison@steris.com.cbmdev1'
            LIMIT 1
        ];
        Boolean canRunFlows = persona.UserPermissionsInteractionUser;
        for (PermissionSetAssignment assignment : [
            SELECT PermissionSet.PermissionsRunFlow
            FROM PermissionSetAssignment
            WHERE AssigneeId = :persona.Id
        ]) {
            canRunFlows = canRunFlows || assignment.PermissionSet.PermissionsRunFlow;
        }
        CSC_Visit_Request__c draftVisit = [
            SELECT Id, Name
            FROM CSC_Visit_Request__c
            WHERE OwnerId = :persona.Id AND Status__c = 'Draft'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        CSC_Visit_Request__c confirmedVisit = [
            SELECT Id, Name, AccountFacility__c
            FROM CSC_Visit_Request__c
            WHERE OwnerId = :persona.Id AND Status__c = 'Confirmed'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        delete [
            SELECT Id
            FROM Sunshine__c
            WHERE CSC_Visit_Request__c IN :new Set<Id>{ draftVisit.Id, confirmedVisit.Id }
        ];

        List<String> gaps = new List<String>();
        System.runAs(persona) {
            System.assertEquals(true, Schema.sObjectType.Sunshine__c.isCreateable(), 'Sunshine create');
            System.assertEquals(true, Schema.sObjectType.Sunshine__c.isUpdateable(), 'Sunshine edit');
            requireEdit(gaps, Sunshine__c.State__c);
            requireEdit(gaps, Sunshine__c.Credential__c);
            requireEdit(gaps, Sunshine__c.Taxonomy_Description__c);
            requireEdit(gaps, Sunshine__c.Last_NPI_Search__c);
            requireEdit(gaps, Sunshine__c.NPI_Key__c);
            requireEdit(gaps, Sunshine__c.Airfare__c);
            requireEdit(gaps, Sunshine__c.Hotel__c);
            requireEdit(gaps, Sunshine__c.Visit_Nights__c);
            requireEdit(gaps, Sunshine__c.Meals__c);
            requireEdit(gaps, Sunshine__c.Transportation__c);
            requireEdit(gaps, Sunshine__c.Type__c);
            requireEdit(gaps, Sunshine__c.Product_Associated__c);
            System.assertEquals(0, gaps.size(), String.join(gaps, '; '));

            SunshineService.SearchResult byName = SunshineService.search('Jordan', 'Hale', 'Mentor', null);
            System.assertEquals(1, byName.matchCount, byName.resultMessage);
            System.assertEquals('1234567893', byName.npi);
            System.assertEquals('207R00000X', byName.taxonomyCode);

            SunshineService.SearchResult byNpi = SunshineService.search(null, null, null, '1679576722');
            System.assertEquals(1, byNpi.matchCount);
            System.assertEquals('Lang', byNpi.lastName);

            SunshineService.SearchResult missing = SunshineService.search('Jordan', 'Hale', null, null);
            System.assertEquals(0, missing.matchCount);

            SunshineService.SaveRequest draftSave = new SunshineService.SaveRequest();
            draftSave.visitId = draftVisit.Id;
            draftSave.npi = '1234567893';
            draftSave.airfare = 450;
            draftSave.hotel = 620;
            draftSave.visitNights = 2;
            draftSave.meals = 90;
            draftSave.transportation = 75;
            draftSave.sunshineType = 'Physician';
            draftSave.productAssociated = 'Cleansuite';
            Id draftRow = SunshineService.save(draftSave);
            Sunshine__c stored = [
                SELECT Taxonomy_Code__c, Total_Reportable_Expense__c
                FROM Sunshine__c
                WHERE Id = :draftRow
            ];
            System.assertEquals('207R00000X', stored.Taxonomy_Code__c);
            System.assertEquals(1235, stored.Total_Reportable_Expense__c);

            SunshineService.SaveRequest confirmedSave = new SunshineService.SaveRequest();
            confirmedSave.visitId = confirmedVisit.Id;
            confirmedSave.npi = '1679576722';
            confirmedSave.airfare = 0;
            confirmedSave.hotel = 210;
            confirmedSave.visitNights = 1;
            confirmedSave.meals = 30;
            confirmedSave.transportation = 64;
            confirmedSave.sunshineType = 'Physician';
            confirmedSave.productAssociated = 'Cleansuite';
            Id confirmedRow = SunshineService.save(confirmedSave);
            Sunshine__c updated = [
                SELECT Transportation__c, Total_Reportable_Expense__c
                FROM Sunshine__c
                WHERE Id = :confirmedRow
            ];
            System.assertEquals(64, updated.Transportation__c);
            System.assertEquals(304, updated.Total_Reportable_Expense__c);

            Boolean duplicateRejected = false;
            try {
                SunshineService.SaveRequest duplicateRequest = new SunshineService.SaveRequest();
                duplicateRequest.visitId = draftVisit.Id;
                duplicateRequest.npi = '1234567893';
                SunshineService.save(duplicateRequest);
            } catch (SunshineService.SunshineException ex) {
                duplicateRejected = ex.getMessage().contains('already recorded');
            }
            System.assertEquals(true, duplicateRejected, 'Duplicate physician should be rejected');

            Boolean negativeRejected = false;
            try {
                SunshineService.SaveRequest negativeRequest = new SunshineService.SaveRequest();
                negativeRequest.visitId = confirmedVisit.Id;
                negativeRequest.npi = '1063493807';
                negativeRequest.airfare = -5;
                SunshineService.save(negativeRequest);
            } catch (SunshineService.SunshineException ex) {
                negativeRejected = ex.getMessage().contains('cannot be negative');
            }
            System.assertEquals(true, negativeRejected, 'Negative airfare should be rejected');

            SunshineService.PdfModel pdf = SunshineService.buildPdf(confirmedVisit.Id);
            System.assert(pdf.visitNumber.startsWith('CSC-'), pdf.visitNumber);
            System.assert(pdf.accountLine.contains('Lakeside Surgical Hospital'), pdf.accountLine);
            System.assert(pdf.visitWhen.contains('All Day'), pdf.visitWhen);
            System.assertEquals(1, pdf.physicians.size());
            System.assertEquals('LANG, AVERY', pdf.physicians[0].physicianName);
            System.assertEquals(1, pdf.sterisAttendees.size());
            System.assert(pdf.lastVendor.contains('replacement'), pdf.lastVendor);

            requireRead(gaps, Account.Name);
            requireRead(gaps, Account.ParentId);
            requireRead(gaps, Account.BillingCity);
            requireRead(gaps, Account.BillingState);
            requireRead(gaps, Account.Type);
            requireRead(gaps, Contact.Name);
            requireRead(gaps, Contact.Title);
            requireRead(gaps, Contact.Email);
            requireRead(gaps, Contact.Phone);
            requireRead(gaps, CSCVisitAttendee__c.CSCVisit__c);
            requireRead(gaps, CSCVisitAttendee__c.STERISAttendee__c);
            requireRead(gaps, AccountTeamMember.SalesCategoryDescription__c);
            requireRead(gaps, AccountTeamMember.ExpiryDate__c);
            requireRead(gaps, AccountTeamMember.AssignmentType__c);
            requireRead(gaps, AccountTeamMember.TerritoryCode__c);
            requireRead(gaps, AccountTeamMember.SalesCategoryCode__c);
            requireRead(gaps, AccountAccountRelationship__c.ChildAccount__c);
            requireRead(gaps, AccountAccountRelationship__c.ParentAccount__c);
            requireRead(gaps, AccountAccountRelationship__c.RelationshipType__c);
            requireRead(gaps, AccountAccountRelationship__c.InverseRelationshipType__c);
            try {
                AccountAccountRelationshipSelector.selectGpoIdnAffiliationsByAccountIds(
                    new Set<Id>{ confirmedVisit.AccountFacility__c }
                );
            } catch (Exception ex) {
                gaps.add('Affiliation query: ' + ex.getMessage());
            }
            try {
                AccountTeamMemberSelector.selectByAccountId(confirmedVisit.AccountFacility__c, false);
            } catch (Exception ex) {
                gaps.add('Account team query: ' + ex.getMessage());
            }

            if (!canRunFlows) {
                gaps.add('Flow User or Run Flows');
            }
            SunshineService.PdfFile file = SunshineService.generatePdfFile(confirmedVisit.Id);
            System.assertNotEquals(null, file.contentDocumentId);
            System.assertEquals(0, gaps.size(), String.join(gaps, '; '));
        }
    }

    @IsTest
    static void addPhysicianAfterVisitIsCompleted() {
        User persona = [SELECT Id FROM User WHERE Username = 'morgan.ellison@steris.com.cbmdev1' LIMIT 1];
        CSC_Visit_Request__c visit = [SELECT Id, Status__c FROM CSC_Visit_Request__c WHERE Name = 'CSC-00097' LIMIT 1];
        visit.Status__c = 'Completed';
        update visit;
        System.runAs(persona) {
            SunshineService.SaveRequest request = new SunshineService.SaveRequest();
            request.visitId = visit.Id;
            request.npi = '1063493807';
            request.airfare = 100;
            request.hotel = 0;
            request.visitNights = 1;
            request.meals = 20;
            request.transportation = 15;
            request.sunshineType = 'Physician';
            request.productAssociated = 'Cleansuite';
            Id savedId = SunshineService.save(request);
            System.assertNotEquals(null, savedId);
        }
    }

    private static void requireRead(List<String> gaps, Schema.SObjectField field) {
        Schema.DescribeFieldResult describe = field.getDescribe();
        if (describe.isPermissionable() && !describe.isAccessible()) {
            gaps.add(describe.getName() + ' read');
        }
    }

    private static void requireEdit(List<String> gaps, Schema.SObjectField field) {
        Schema.DescribeFieldResult describe = field.getDescribe();
        if (describe.isPermissionable() && !describe.isUpdateable()) {
            gaps.add(describe.getName() + ' edit');
        }
    }
}