/**
 * @author PWC Developer
 * @date 2026/10/16
 *
 * @group CSC Visit
 *
 * @description
 * GC-3564 - Covers physician search, Sunshine expense save, and the Visit PDF model.
 */
@IsTest
private class SunshineServiceTest {

    @IsTest
    static void search_matchesFirstNameLastNameAndCity() {
        SunshineService.SearchResult result = SunshineService.search('jordan', 'HALE', ' Mentor ', null);

        System.assertEquals(1, result.matchCount);
        System.assertEquals('1234567893', result.npi);
        System.assertEquals('207R00000X', result.taxonomyCode);
        System.assert(result.resultMessage.contains('Jordan Hale'));
    }

    @IsTest
    static void search_matchesNpiFromTheDirectory() {
        SunshineService.SearchResult result = SunshineService.search(null, null, null, '1679576722');

        System.assertEquals(1, result.matchCount);
        System.assertEquals('Avery', result.firstName);
        System.assertEquals('Cleveland', result.city);
        System.assertEquals('207Q00000X', result.taxonomyCode);
    }

    @IsTest
    static void search_returnsNoMatchWhenThePhysicianIsNotInTheDirectory() {
        SunshineService.SearchResult result = SunshineService.search('Jordan', 'Hale', 'Columbus', null);

        System.assertEquals(0, result.matchCount);
        System.assertEquals(null, result.npi);
        System.assert(result.resultMessage.contains('No physician matched'));
    }

    @IsTest
    static void search_requiresNameAndCityWhenNpiIsBlank() {
        SunshineService.SearchResult result = SunshineService.search('Jordan', null, 'Mentor', null);

        System.assertEquals(0, result.matchCount);
        System.assert(result.resultMessage.contains('first name'));
    }

    @IsTest
    static void save_storesTaxonomyAndExpensesFromTheDirectory() {
        CSC_Visit_Request__c visit = insertVisit();
        SunshineService.SaveRequest request = expenseRequest(visit.Id, '1234567893');
        request.airfare = 100;
        request.hotel = 200;
        request.visitNights = 2;
        request.meals = 50;
        request.transportation = 25;
        request.sunshineType = 'Physician';
        request.productAssociated = 'Cleansuite';

        Test.startTest();
        Id sunshineId = SunshineService.save(request);
        Test.stopTest();

        Sunshine__c saved = [
            SELECT NPI__c, First_Name__c, Taxonomy_Code__c, Taxonomy_Description__c, Airfare__c,
                   Visit_Nights__c, Total_Reportable_Expense__c, NPI_Key__c, Last_NPI_Search__c,
                   Type__c, Product_Associated__c
            FROM Sunshine__c
            WHERE Id = :sunshineId
        ];
        System.assertEquals('1234567893', saved.NPI__c);
        System.assertEquals('Jordan', saved.First_Name__c);
        System.assertEquals('207R00000X', saved.Taxonomy_Code__c);
        System.assertEquals('Internal Medicine Physician', saved.Taxonomy_Description__c);
        System.assertEquals(2, saved.Visit_Nights__c);
        System.assertEquals(375, saved.Total_Reportable_Expense__c);
        System.assertEquals('Physician', saved.Type__c);
        System.assertEquals('Cleansuite', saved.Product_Associated__c);
        System.assertEquals(String.valueOf(visit.Id) + '-1234567893', saved.NPI_Key__c);
        System.assertNotEquals(null, saved.Last_NPI_Search__c);
    }

    @IsTest
    static void save_updatesExpensesAfterThePhysicianIsRecorded() {
        CSC_Visit_Request__c visit = insertVisit();
        Id sunshineId = SunshineService.save(expenseRequest(visit.Id, '1063493807'));

        SunshineService.SaveRequest updateRequest = new SunshineService.SaveRequest();
        updateRequest.visitId = visit.Id;
        updateRequest.sunshineId = sunshineId;
        updateRequest.meals = 80;

        Id updatedId = SunshineService.save(updateRequest);
        Sunshine__c saved = [SELECT Meals__c, NPI__c FROM Sunshine__c WHERE Id = :updatedId];

        System.assertEquals(sunshineId, updatedId);
        System.assertEquals(80, saved.Meals__c);
        System.assertEquals('1063493807', saved.NPI__c);
    }

    @IsTest
    static void save_rejectsADuplicatePhysicianAndANegativeAmount() {
        CSC_Visit_Request__c visit = insertVisit();
        SunshineService.save(expenseRequest(visit.Id, '1234567893'));

        try {
            SunshineService.save(expenseRequest(visit.Id, '1234567893'));
            System.assert(false, 'A duplicate physician should be rejected.');
        } catch (SunshineService.SunshineException expectedError) {
            System.assert(expectedError.getMessage().contains('already recorded'));
        }

        SunshineService.SaveRequest negativeRequest = expenseRequest(visit.Id, '1679576722');
        negativeRequest.airfare = -1;
        try {
            SunshineService.save(negativeRequest);
            System.assert(false, 'A negative amount should be rejected.');
        } catch (SunshineService.SunshineException expectedError) {
            System.assert(expectedError.getMessage().contains('Airfare'));
        }
    }

    @IsTest
    static void buildPdf_includesThePhysicianAndSterisAttendee() {
        CSC_Visit_Request__c visit = insertVisit();
        SunshineService.save(expenseRequest(visit.Id, '1679576722'));
        Boolean attendeeInserted = insertAttendee(visit.Id);

        SunshineService.PdfModel pdf = SunshineService.buildPdf(visit.Id);

        System.assertEquals(visit.Name, pdf.visitNumber);
        System.assertEquals(1, pdf.physicians.size());
        System.assertEquals('LANG, AVERY', pdf.physicians[0].physicianName);
        if (attendeeInserted) {
            User runningUser = [SELECT FirstName, LastName, Name FROM User WHERE Id = :UserInfo.getUserId()];
            String expectedName = String.isNotBlank(runningUser.LastName) && String.isNotBlank(runningUser.FirstName)
                ? runningUser.LastName + ', ' + runningUser.FirstName
                : runningUser.Name;
            System.assertEquals(1, pdf.sterisAttendees.size());
            System.assertEquals(expectedName, pdf.sterisAttendees[0].personName);
        }
    }

    private static SunshineService.SaveRequest expenseRequest(Id visitId, String npi) {
        SunshineService.SaveRequest request = new SunshineService.SaveRequest();
        request.visitId = visitId;
        request.npi = npi;
        return request;
    }

    private static CSC_Visit_Request__c insertVisit() {
        CSC_Visit_Request__c visit = (CSC_Visit_Request__c) populateRequiredFields(new CSC_Visit_Request__c());
        insert visit;
        return [SELECT Id, Name FROM CSC_Visit_Request__c WHERE Id = :visit.Id];
    }

    private static Boolean insertAttendee(Id visitId) {
        String lookupField = SunshineSelector.findVisitLookupField();
        if (String.isBlank(lookupField)) {
            return false;
        }
        CSCVisitAttendee__c attendee = (CSCVisitAttendee__c) populateRequiredFields(new CSCVisitAttendee__c());
        attendee.put(lookupField, visitId);
        Schema.DescribeFieldResult attendeeField = CSCVisitAttendee__c.STERISAttendee__c.getDescribe();
        if (attendeeField.getType() == Schema.DisplayType.REFERENCE
            && !attendeeField.getReferenceTo().isEmpty()
            && attendeeField.getReferenceTo()[0] == User.SObjectType) {
            attendee.STERISAttendee__c = UserInfo.getUserId();
        }
        try {
            insert attendee;
            return true;
        } catch (DmlException exceptionValue) {
            return false;
        }
    }

    private static SObject populateRequiredFields(SObject record) {
        for (Schema.SObjectField fieldToken : record.getSObjectType().getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult describe = fieldToken.getDescribe();
            if (!describe.isCreateable() || describe.isNillable() || describe.isDefaultedOnCreate() || record.get(describe.getName()) != null) {
                continue;
            }
            if (describe.getType() == Schema.DisplayType.STRING || describe.getType() == Schema.DisplayType.TEXTAREA) {
                record.put(describe.getName(), 'GC-3564');
            } else if (describe.getType() == Schema.DisplayType.PICKLIST) {
                for (Schema.PicklistEntry entry : describe.getPicklistValues()) {
                    if (entry.isActive()) {
                        record.put(describe.getName(), entry.getValue());
                        break;
                    }
                }
            } else if (describe.getType() == Schema.DisplayType.BOOLEAN) {
                record.put(describe.getName(), false);
            } else if (describe.getType() == Schema.DisplayType.DATE) {
                record.put(describe.getName(), Date.today());
            } else if (describe.getType() == Schema.DisplayType.DATETIME) {
                record.put(describe.getName(), System.now());
            } else if (describe.getType() == Schema.DisplayType.CURRENCY
                || describe.getType() == Schema.DisplayType.DOUBLE
                || describe.getType() == Schema.DisplayType.INTEGER
                || describe.getType() == Schema.DisplayType.PERCENT) {
                record.put(describe.getName(), 0);
            }
        }
        return record;
    }
}