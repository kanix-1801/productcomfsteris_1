/**
 * @author PWC Developer
 * @date 2026/10/16
 *
 * @group CSC Visit
 *
 * @description
 * GC-3564 - Covers the Sunshine flow actions and the Visit PDF controller.
 */
@IsTest
private class SunshineControllerTest {

    @IsTest
    static void search_returnsTheDirectoryPhysician() {
        SunshineSearchController.SearchRequest request = new SunshineSearchController.SearchRequest();
        request.firstName = 'Riley';
        request.lastName = 'Chen';
        request.city = 'Columbus';

        List<SunshineSearchController.SearchResponse> responses =
            SunshineSearchController.search(new List<SunshineSearchController.SearchRequest>{ request });

        System.assertEquals(1, responses.size());
        System.assertEquals(1, responses[0].matchCount);
        System.assertEquals('208600000X', responses[0].taxonomyCode);
    }

    @IsTest
    static void save_createsTheSunshineRow() {
        CSC_Visit_Request__c visit = insertVisit();
        SunshineSaveController.SaveRequest request = new SunshineSaveController.SaveRequest();
        request.visitId = visit.Id;
        request.npi = '1234567893';
        request.airfare = 40;

        Test.startTest();
        List<SunshineSaveController.SaveResponse> responses =
            SunshineSaveController.save(new List<SunshineSaveController.SaveRequest>{ request });
        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertNotEquals(null, responses[0].sunshineId);
        System.assertEquals(40, [SELECT Airfare__c FROM Sunshine__c WHERE Id = :responses[0].sunshineId].Airfare__c);
    }

    @IsTest
    static void generate_savesThePdfOnTheVisit() {
        CSC_Visit_Request__c visit = insertVisit();
        SunshinePdfController.GenerateRequest request = new SunshinePdfController.GenerateRequest();
        request.visitId = visit.Id;

        Test.startTest();
        List<SunshinePdfController.GenerateResponse> responses =
            SunshinePdfController.generate(new List<SunshinePdfController.GenerateRequest>{ request });
        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertNotEquals(null, responses[0].contentDocumentId);
        System.assert(responses[0].fileTitle.contains(visit.Name));
        System.assertEquals(
            1,
            [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :visit.Id]
        );
    }

    @IsTest
    static void pdfController_loadsTheVisit() {
        CSC_Visit_Request__c visit = insertVisit();
        ApexPages.StandardController standardController = new ApexPages.StandardController(visit);

        CSCVisitPdfController controller = new CSCVisitPdfController(standardController);

        System.assertEquals(visit.Name, controller.pdf.visitNumber);
        System.assertEquals(0, controller.pdf.physicians.size());
    }

    private static CSC_Visit_Request__c insertVisit() {
        CSC_Visit_Request__c visit = new CSC_Visit_Request__c();
        for (Schema.SObjectField fieldToken : CSC_Visit_Request__c.SObjectType.getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult describe = fieldToken.getDescribe();
            if (!describe.isCreateable() || describe.isNillable() || describe.isDefaultedOnCreate() || visit.get(describe.getName()) != null) {
                continue;
            }
            if (describe.getType() == Schema.DisplayType.STRING || describe.getType() == Schema.DisplayType.TEXTAREA) {
                visit.put(describe.getName(), 'GC-3564');
            } else if (describe.getType() == Schema.DisplayType.PICKLIST) {
                for (Schema.PicklistEntry entry : describe.getPicklistValues()) {
                    if (entry.isActive()) {
                        visit.put(describe.getName(), entry.getValue());
                        break;
                    }
                }
            } else if (describe.getType() == Schema.DisplayType.BOOLEAN) {
                visit.put(describe.getName(), false);
            } else if (describe.getType() == Schema.DisplayType.DATE) {
                visit.put(describe.getName(), Date.today());
            } else if (describe.getType() == Schema.DisplayType.CURRENCY || describe.getType() == Schema.DisplayType.DOUBLE) {
                visit.put(describe.getName(), 0);
            }
        }
        insert visit;
        return [SELECT Id, Name FROM CSC_Visit_Request__c WHERE Id = :visit.Id];
    }
}