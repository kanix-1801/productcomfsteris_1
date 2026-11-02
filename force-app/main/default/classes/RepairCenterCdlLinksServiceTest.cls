/**
 * @description GW-5830 - Tests for RepairCenterContentDocumentLinksService.
 */
@IsTest
private class RepairCenterCdlLinksServiceTest {
    private static final String PO_NUMBER = 'PO-GW5830-001';

    @TestSetup
    static void setupData() {
        adb_Account accountBuilder = new adb_Account().name('GW-5830 PO Required Account');

        adb_WorkOrder parentBuilder = new adb_WorkOrder()
            .account(accountBuilder)
            .status('Quote')
            .subject('GW-5830 Parent WO')
            .setRecordType('RepairCenterDevices');
        ((WorkOrder) parentBuilder.record).CustomerPO__c = PO_NUMBER;

        adb_WorkOrder childPoRequired = new adb_WorkOrder()
            .account(accountBuilder)
            .status('Quote')
            .subject('GW-5830 Child PO Required')
            .setRecordType('RepairCenterDevices')
            .parentWorkOrder(parentBuilder);
        ((WorkOrder) childPoRequired.record).CustomerPO__c = null;
        ((WorkOrder) childPoRequired.record).SubStatus__c = 'PO Required';

        adb_WorkOrder childWaiting = new adb_WorkOrder()
            .account(accountBuilder)
            .status('Quote')
            .subject('GW-5830 Child Waiting')
            .setRecordType('RepairCenterDevices')
            .parentWorkOrder(parentBuilder);
        ((WorkOrder) childWaiting.record).SubStatus__c = 'Waiting for Approval';

        accountBuilder.persist();
    }

    @IsTest
    static void handleNewContentDocumentLinks_advancesPoRequiredChildren() {
        WorkOrder parent = [
            SELECT Id, CustomerPO__c
            FROM WorkOrder
            WHERE Subject = 'GW-5830 Parent WO'
            LIMIT 1
        ];
        WorkOrder childPoRequired = [
            SELECT Id, Status, SubStatus__c
            FROM WorkOrder
            WHERE Subject = 'GW-5830 Child PO Required'
            LIMIT 1
        ];
        WorkOrder childWaiting = [
            SELECT Id, Status, SubStatus__c
            FROM WorkOrder
            WHERE Subject = 'GW-5830 Child Waiting'
            LIMIT 1
        ];

        Assert.areEqual(PO_NUMBER, parent.CustomerPO__c);
        Assert.areEqual('PO Required', childPoRequired.SubStatus__c);

        ContentVersion version = new ContentVersion(
            Title = 'GW-5830 Parent PO File',
            PathOnClient = 'po.pdf',
            VersionData = Blob.valueOf('po-content'),
            IsMajorVersion = true
        );
        insert version;
        Id contentDocumentId = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
        ]
        .ContentDocumentId;

        Test.startTest();
        insert new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId = parent.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        Test.stopTest();

        WorkOrder updatedPoRequired = [
            SELECT Status, SubStatus__c
            FROM WorkOrder
            WHERE Id = :childPoRequired.Id
        ];
        WorkOrder updatedWaiting = [
            SELECT Status, SubStatus__c
            FROM WorkOrder
            WHERE Id = :childWaiting.Id
        ];

        Assert.areEqual('Ready for Repair', updatedPoRequired.Status);
        Assert.isNull(updatedPoRequired.SubStatus__c);
        Assert.areEqual('Waiting for Approval', updatedWaiting.SubStatus__c);
        Assert.areNotEqual('Ready for Repair', updatedWaiting.Status);
    }

    @IsTest
    static void handleNewContentDocumentLinks_skipsWhenParentPoBlank() {
        WorkOrder parent = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'GW-5830 Parent WO'
            LIMIT 1
        ];
        parent.CustomerPO__c = null;
        update parent;

        WorkOrder childPoRequired = [
            SELECT Id, Status, SubStatus__c
            FROM WorkOrder
            WHERE Subject = 'GW-5830 Child PO Required'
            LIMIT 1
        ];

        ContentVersion version = new ContentVersion(
            Title = 'GW-5830 No PO File',
            PathOnClient = 'file.pdf',
            VersionData = Blob.valueOf('content'),
            IsMajorVersion = true
        );
        insert version;
        Id contentDocumentId = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
        ]
        .ContentDocumentId;

        Test.startTest();
        insert new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId = parent.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        Test.stopTest();

        WorkOrder unchanged = [
            SELECT Status, SubStatus__c
            FROM WorkOrder
            WHERE Id = :childPoRequired.Id
        ];
        Assert.areEqual('PO Required', unchanged.SubStatus__c);
        Assert.areNotEqual('Ready for Repair', unchanged.Status);
    }

    @IsTest
    static void advancePoRequiredWhenCustomerPoFilled_advancesWhenParentHasAttachment() {
        WorkOrder parent = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'GW-5830 Parent WO'
            LIMIT 1
        ];
        WorkOrder childPoRequired = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'GW-5830 Child PO Required'
            LIMIT 1
        ];

        ContentVersion version = new ContentVersion(
            Title = 'GW-5830 Existing Parent File',
            PathOnClient = 'existing.pdf',
            VersionData = Blob.valueOf('existing'),
            IsMajorVersion = true
        );
        insert version;
        Id contentDocumentId = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
        ]
        .ContentDocumentId;
        insert new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId = parent.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );

        // Re-assert PO Required after the link insert (attachment path may have advanced it).
        childPoRequired = [
            SELECT Id, Status, SubStatus__c, CustomerPO__c
            FROM WorkOrder
            WHERE Id = :childPoRequired.Id
        ];
        if (childPoRequired.Status == 'Ready for Repair') {
            childPoRequired.Status = 'Quote';
            childPoRequired.SubStatus__c = 'PO Required';
            childPoRequired.CustomerPO__c = null;
            update childPoRequired;
        }

        RepairCenterContentDocumentLinksService.CustomerPoAdvanceRequest request =
            new RepairCenterContentDocumentLinksService.CustomerPoAdvanceRequest();
        request.workOrderId = childPoRequired.Id;

        childPoRequired.CustomerPO__c = PO_NUMBER;
        childPoRequired.SubStatus__c = 'PO Required';
        childPoRequired.Status = 'Quote';
        update childPoRequired;

        Test.startTest();
        RepairCenterContentDocumentLinksService.advancePoRequiredWhenCustomerPoFilled(
            new List<RepairCenterContentDocumentLinksService.CustomerPoAdvanceRequest>{ request }
        );
        Test.stopTest();

        WorkOrder updated = [
            SELECT Status, SubStatus__c
            FROM WorkOrder
            WHERE Id = :childPoRequired.Id
        ];
        Assert.areEqual('Ready for Repair', updated.Status);
        Assert.isNull(updated.SubStatus__c);
    }

    @IsTest
    static void advancePoRequiredWhenCustomerPoFilled_noOpWhenEmptyOrNull() {
        Test.startTest();
        RepairCenterContentDocumentLinksService.advancePoRequiredWhenCustomerPoFilled(null);
        RepairCenterContentDocumentLinksService.advancePoRequiredWhenCustomerPoFilled(
            new List<RepairCenterContentDocumentLinksService.CustomerPoAdvanceRequest>()
        );
        RepairCenterContentDocumentLinksService.handleNewContentDocumentLinks(null);
        RepairCenterContentDocumentLinksService.handleNewContentDocumentLinks(
            new List<ContentDocumentLink>()
        );
        Test.stopTest();

        Integer poRequiredCount = [
            SELECT COUNT()
            FROM WorkOrder
            WHERE Subject = 'GW-5830 Child PO Required' AND SubStatus__c = 'PO Required'
        ];
        Assert.areEqual(1, poRequiredCount);
    }

    @IsTest
    static void triggerHandler_constructs() {
        Assert.isNotNull(new RepairCenterCdlTriggerHandler());
    }
}