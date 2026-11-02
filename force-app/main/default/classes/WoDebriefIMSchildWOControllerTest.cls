/**
 * @description Tests for WoDebriefIMSchildWOController repair-code Product2 lookup.
 * @see WoDebriefIMSchildWOController
 */
@IsTest
private class WoDebriefIMSchildWOControllerTest {
    /**
     * @description Inserts a Product2 used by repair-code lookup tests.
     * @param productCode Product Code
     * @param productType ProductType__c value
     * @param baseServiceCode BaseServiceCode__c value
     * @return Inserted Product2
     */
    private static Product2 createProduct(String productCode, String productType, String baseServiceCode) {
        Product2 product = new Product2(
            Name = 'Test ' + productCode,
            ProductCode = productCode,
            IsActive = true,
            ProductType__c = productType,
            BaseServiceCode__c = baseServiceCode
        );
        insert product;
        return product;
    }

    /**
     * @description Verifies null product Id returns an empty result.
     */
    @IsTest
    static void getChildDebriefAccess_siteVisit_returnsNotAllowed() {
        Account account = new Account(
            Name = 'GW Child Debrief Access Account',
            SourceSystemID__c = 'ORACLE-CHILD-ACC-' + String.valueOf(Crypto.getRandomInteger())
        );
        insert account;
        WorkOrder siteVisit = new WorkOrder(
            AccountId = account.Id,
            Subject = 'Site Visit WO Access'
        );
        insert siteVisit;

        Test.startTest();
        WoDebriefIMSchildWOController.ChildDebriefAccessResult result =
            WoDebriefIMSchildWOController.getChildDebriefAccess(siteVisit.Id);
        Test.stopTest();

        System.assertEquals(false, result.allowed);
        System.assertEquals(siteVisit.Id, result.workOrderId);
    }

    /**
     * @description Null Work Order Id cannot open child debrief.
     */
    @IsTest
    static void allowsChildWorkOrderDebrief_nullWorkOrder_returnsFalse() {
        Test.startTest();
        Boolean allowed = WoDebriefIMSchildWOController.allowsChildWorkOrderDebrief(null);
        Test.stopTest();
        System.assertEquals(false, allowed);
    }

    /**
     * @description Site visit work orders without a parent cannot open child debrief.
     */
    @IsTest
    static void allowsChildWorkOrderDebrief_siteVisit_returnsFalse() {
        Account account = new Account(
            Name = 'GW Child Debrief Account',
            SourceSystemID__c = 'ORACLE-CHILD-DEB-' + String.valueOf(Crypto.getRandomInteger())
        );
        insert account;
        WorkOrder siteVisit = new WorkOrder(
            AccountId = account.Id,
            Subject = 'Site Visit WO'
        );
        insert siteVisit;

        Test.startTest();
        Boolean allowed = WoDebriefIMSchildWOController.allowsChildWorkOrderDebrief(siteVisit.Id);
        Test.stopTest();

        System.assertEquals(false, allowed);
    }

    /**
     * @description Child work orders with a parent may open child debrief.
     */
    @IsTest
    static void allowsChildWorkOrderDebrief_childWorkOrder_returnsTrue() {
        Account account = new Account(
            Name = 'GW Child Debrief Parent Account',
            SourceSystemID__c = 'ORACLE-CHILD-DEB2-' + String.valueOf(Crypto.getRandomInteger())
        );
        insert account;
        WorkOrder siteVisit = new WorkOrder(
            AccountId = account.Id,
            Subject = 'Parent Site Visit'
        );
        insert siteVisit;
        Product2 device = createProduct('DT.CHILD' + String.valueOf(Crypto.getRandomInteger()), 'Service Asset', null);
        Asset asset = new Asset(
            Name = 'Child WO Asset',
            AccountId = account.Id,
            Product2Id = device.Id,
            SerialNumber = 'SN-CHILD'
        );
        insert asset;
        WorkOrder childWorkOrder = new WorkOrder(
            AccountId = account.Id,
            ParentWorkOrderId = siteVisit.Id,
            AssetId = asset.Id,
            Subject = 'Child WO'
        );
        insert childWorkOrder;

        Test.startTest();
        Boolean allowed = WoDebriefIMSchildWOController.allowsChildWorkOrderDebrief(childWorkOrder.Id);
        Test.stopTest();

        System.assertEquals(true, allowed);
    }

    /**
     * @description Child work orders without an Asset cannot open child debrief.
     */
    @IsTest
    static void getChildDebriefAccess_childWithoutAsset_returnsNotAllowed() {
        Account account = new Account(
            Name = 'GW Child No Asset Account',
            SourceSystemID__c = 'ORACLE-CHILD-NA-' + String.valueOf(Crypto.getRandomInteger())
        );
        insert account;
        WorkOrder siteVisit = new WorkOrder(
            AccountId = account.Id,
            Subject = 'Parent Site Visit No Asset Child'
        );
        insert siteVisit;
        WorkOrder childWorkOrder = new WorkOrder(
            AccountId = account.Id,
            ParentWorkOrderId = siteVisit.Id,
            Subject = 'Child WO No Asset'
        );
        insert childWorkOrder;

        Test.startTest();
        WoDebriefIMSchildWOController.ChildDebriefAccessResult result =
            WoDebriefIMSchildWOController.getChildDebriefAccess(childWorkOrder.Id);
        Test.stopTest();

        System.assertEquals(false, result.allowed);
        System.assert(result.blockMessage != null && result.blockMessage.contains('no Asset'));
    }

    /**
     * @description Verifies null product returns empty repair-code result.
     */
    @IsTest
    static void getRepairCodesForProduct_nullProduct_returnsEmpty() {
        Test.startTest();
        WoDebriefIMSchildWOController.RepairCodesForProductResult result =
            WoDebriefIMSchildWOController.getRepairCodesForProduct(null);
        Test.stopTest();

        System.assertEquals('', result.baseServiceCode);
        System.assertEquals(0, result.options.size());
    }

    /**
     * @description Verifies unknown product Id returns an empty result.
     */
    @IsTest
    static void getRepairCodesForProduct_unknownProduct_returnsEmpty() {
        Id fakeProductId = '01t000000000001AAA';

        Test.startTest();
        WoDebriefIMSchildWOController.RepairCodesForProductResult result =
            WoDebriefIMSchildWOController.getRepairCodesForProduct(fakeProductId);
        Test.stopTest();

        System.assertEquals('', result.baseServiceCode);
        System.assertEquals(0, result.options.size());
    }

    /**
     * @description Verifies part without Base Service Code returns empty options.
     */
    @IsTest
    static void getRepairCodesForProduct_partWithNoBaseCode_returnsEmpty() {
        Product2 part = createProduct('PART-NOBASE', 'Part', null);

        Test.startTest();
        WoDebriefIMSchildWOController.RepairCodesForProductResult result =
            WoDebriefIMSchildWOController.getRepairCodesForProduct(part.Id);
        Test.stopTest();

        System.assertEquals('', result.baseServiceCode);
        System.assertEquals(0, result.options.size());
    }

    /**
     * @description Verifies matching Service Code products are returned for a part base code.
     */
    @IsTest
    static void getRepairCodesForProduct_matchingPart_returnsServiceCodes() {
        Product2 part = createProduct('PART-123', 'Part', '123');
        Product2 matchingServiceCode = createProduct('SVC-123A', 'Service Code', '123A');
        Product2 nonMatchingServiceCode = createProduct('SVC-456', 'Service Code', '456');

        Test.startTest();
        WoDebriefIMSchildWOController.RepairCodesForProductResult result =
            WoDebriefIMSchildWOController.getRepairCodesForProduct(part.Id);
        Test.stopTest();

        System.assertEquals('123', result.baseServiceCode);
        System.assertEquals(1, result.options.size(), 'Expected only service codes matching base code 123');
        System.assertEquals(matchingServiceCode.Id, result.options[0].id);
        System.assertEquals('SVC-123A', result.options[0].productCode);
        System.assertEquals('Test SVC-123A', result.options[0].name);
        System.assertEquals('SVC-123A — Test SVC-123A', result.options[0].label);
        System.assertNotEquals(nonMatchingServiceCode.Id, result.options[0].id);
    }

    /**
     * @description Verifies base code is returned even when no Service Code products match.
     */
    @IsTest
    static void getRepairCodesForProduct_partWithBaseCodeButNoMatches_returnsEmptyOptions() {
        Product2 part = createProduct('PART-999', 'Part', '999');

        Test.startTest();
        WoDebriefIMSchildWOController.RepairCodesForProductResult result =
            WoDebriefIMSchildWOController.getRepairCodesForProduct(part.Id);
        Test.stopTest();

        System.assertEquals('999', result.baseServiceCode);
        System.assertEquals(0, result.options.size());
    }

    /**
     * @description Verifies Service Code products are matched by Item Number / ProductCode prefix
     *              (SC.ONL.130 base → SC.ONL1304) as well as BaseServiceCode__c.
     */
    @IsTest
    static void getRepairCodesForProduct_matchesProductCodePrefix() {
        Product2 deviceType = createProduct('DT.130', 'Service Asset', 'SC.ONL.130');
        Product2 matchingByItemNumber = createProduct('SC.ONL1304', 'Service Code', null);
        Product2 nonMatching = createProduct('SC.OTHER1', 'Service Code', null);

        Test.startTest();
        WoDebriefIMSchildWOController.RepairCodesForProductResult result =
            WoDebriefIMSchildWOController.getRepairCodesForProduct(deviceType.Id);
        Test.stopTest();

        System.assertEquals('SC.ONL.130', result.baseServiceCode);
        System.assertEquals(1, result.options.size(), 'Expected the Item Number prefix match only');
        System.assertEquals(matchingByItemNumber.Id, result.options[0].id);
        System.assertEquals('SC.ONL1304', result.options[0].productCode);
        System.assertNotEquals(nonMatching.Id, result.options[0].id);
    }

    /**
     * @description Verifies beyond-repair Service Codes (BR in place of NL) are returned with NL codes.
     */
    @IsTest
    static void getRepairCodesForProduct_includesBeyondRepairCodes() {
        String token = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        Product2 deviceType = createProduct('DT.BR' + token, 'Service Asset', 'SC.ONL.' + token);
        Product2 normalCode = createProduct('SC.ONL' + token + '4', 'Service Code', null);
        Product2 beyondRepairCode = createProduct('SC.OBR' + token + '5', 'Service Code', null);
        Product2 beyondRepairByBase = createProduct('SC.OBRBASE' + token, 'Service Code', 'SC.OBR.' + token);
        Product2 nonMatching = createProduct('SC.OTHER' + token, 'Service Code', null);

        Test.startTest();
        WoDebriefIMSchildWOController.RepairCodesForProductResult result =
            WoDebriefIMSchildWOController.getRepairCodesForProduct(deviceType.Id);
        Test.stopTest();

        Set<Id> optionIds = new Set<Id>();
        for (WoDebriefIMSchildWOController.RepairCodeOption option : result.options) {
            optionIds.add(option.id);
        }
        System.assertEquals(3, result.options.size(), 'Expected NL and BR service codes only');
        System.assert(optionIds.contains(normalCode.Id), 'Expected the NL service code');
        System.assert(optionIds.contains(beyondRepairCode.Id), 'Expected the BR item-number service code');
        System.assert(optionIds.contains(beyondRepairByBase.Id), 'Expected the BR base service code');
        System.assert(!optionIds.contains(nonMatching.Id), 'Unrelated service codes stay excluded');
    }

    /**
     * @description Verifies a blank asset returns no Tray Planner rows.
     */
    @IsTest
    static void getTrayPlanners_nullAsset_returnsEmpty() {
        Test.startTest();
        List<WoDebriefIMSchildWOController.TrayPlannerRow> rows =
            WoDebriefIMSchildWOController.getTrayPlanners(null);
        Test.stopTest();

        System.assertEquals(0, rows.size());
    }

    /**
     * @description Verifies Tray Planner rows for an asset include the loaded list columns.
     */
    @IsTest
    static void getTrayPlanners_returnsRowsForAsset() {
        String token = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        Account account = new Account(
            Name = 'Tray Planner Account ' + token,
            SourceSystemID__c = 'ORACLE-TP-' + token
        );
        insert account;
        Product2 device = createProduct('DT.TP' + token, 'Service Asset', null);
        Asset asset = new Asset(
            Name = 'Instrument Tray ' + token,
            AccountId = account.Id,
            Product2Id = device.Id,
            SerialNumber = 'SN-TP-' + token
        );
        insert asset;
        insert new TrayPlanner__c(
            Name = 'METRIC RULER LENGTH 6"(15CM)',
            Asset__c = asset.Id,
            DeviceType__c = device.Id,
            Quantity__c = 1,
            SupplierMake__c = 'V Mueller',
            CatalogNumber__c = 'OP2720',
            VMuellerNumber__c = 'OP2720, OA2720'
        );

        Test.startTest();
        List<WoDebriefIMSchildWOController.TrayPlannerRow> rows =
            WoDebriefIMSchildWOController.getTrayPlanners(asset.Id);
        Test.stopTest();

        System.assertEquals(1, rows.size());
        System.assertEquals('METRIC RULER LENGTH 6"(15CM)', rows[0].componentName);
        System.assertEquals(1, rows[0].quantity);
        System.assertEquals('V Mueller', rows[0].supplier);
        System.assertEquals('OP2720', rows[0].catalogNumber);
        System.assertEquals('OP2720, OA2720', rows[0].vMuellerNumber);
        System.assertEquals('Test DT.TP' + token, rows[0].deviceName);
        System.assertEquals('DT.TP' + token, rows[0].itemNumber);
    }

    /**
     * @description Verifies null Work Order or product returns no Pricebook Entry.
     */
    @IsTest
    static void resolvePricebookEntryId_blankInputs_returnsNull() {
        Test.startTest();
        Id noWorkOrder = WoDebriefIMSchildWOController.resolvePricebookEntryId(null, '01t000000000001AAA');
        Id noProduct = WoDebriefIMSchildWOController.resolvePricebookEntryId('0WO000000000001AAA', null);
        Test.stopTest();

        System.assertEquals(null, noWorkOrder);
        System.assertEquals(null, noProduct);
    }

    /**
     * @description Verifies a new labor line is created without writing line Service Disposition.
     */
    @IsTest
    static void saveLaborLine_createsLineWithoutDisposition() {
        Account account = new Account(
            Name = 'GW-3674 Create Account',
            SourceSystemID__c = 'ORACLE-GW3674C-' + String.valueOf(Crypto.getRandomInteger())
        );
        insert account;
        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            Subject = 'GW-3674 Create WO'
        );
        insert workOrder;

        Test.startTest();
        Id lineId = WoDebriefIMSchildWOController.saveLaborLine(
            workOrder.Id,
            null,
            null,
            null,
            2,
            'Labor',
            null
        );
        Test.stopTest();

        WorkOrderLineItem stored = [
            SELECT LineType__c, UnitQty__c, ServiceDisposition__c, BillingType__c, Discount
            FROM WorkOrderLineItem
            WHERE Id = :lineId
        ];
        System.assertEquals('Labor', stored.LineType__c);
        System.assertEquals(2, stored.UnitQty__c);
        System.assertEquals(null, stored.ServiceDisposition__c);
        System.assertEquals('Non-Billable', stored.BillingType__c);
    }

    /**
     * @description Verifies Time labor lines stay Non-Billable even if Courtesy is passed.
     */
    @IsTest
    static void saveLaborLine_timeLinesAreNonBillable() {
        Account account = new Account(
            Name = 'GW-3674 Courtesy Account',
            SourceSystemID__c = 'ORACLE-GW3674D-' + String.valueOf(Crypto.getRandomInteger())
        );
        insert account;
        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            Subject = 'GW-3674 Courtesy WO'
        );
        insert workOrder;

        Test.startTest();
        Id lineId = WoDebriefIMSchildWOController.saveLaborLine(
            workOrder.Id,
            null,
            null,
            null,
            1,
            'Labor',
            'Courtesy'
        );
        Test.stopTest();

        WorkOrderLineItem stored = [
            SELECT BillingType__c
            FROM WorkOrderLineItem
            WHERE Id = :lineId
        ];
        System.assertEquals('Non-Billable', stored.BillingType__c);
    }

    /**
     * @description Verifies formatRepairCodeLabel fallbacks for code+name, code-only, and name-only.
     */
    @IsTest
    static void formatRepairCodeLabel_coversFallbackBranches() {
        System.assertEquals(
            'C1 — N1',
            WoDebriefIMSchildWOController.formatRepairCodeLabel('C1', 'N1')
        );
        System.assertEquals(
            'C1',
            WoDebriefIMSchildWOController.formatRepairCodeLabel('C1', null)
        );
        System.assertEquals(
            'N1',
            WoDebriefIMSchildWOController.formatRepairCodeLabel(null, 'N1')
        );
        System.assertEquals(
            null,
            WoDebriefIMSchildWOController.formatRepairCodeLabel(null, null)
        );
    }

    /**
     * @description Verifies account departments are returned and other accounts are excluded.
     */
    @IsTest
    static void getDepartmentsForAccount_returnsAccountDepartments() {
        String token = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        Account account = new Account(
            Name = 'Repair Center Account ' + token,
            SourceSystemID__c = 'ORACLE-RC-' + token
        );
        Account otherAccount = new Account(
            Name = 'Other Account ' + token,
            SourceSystemID__c = 'ORACLE-RC2-' + token
        );
        insert new List<Account>{ account, otherAccount };

        Department__c surgery = new Department__c(Name = 'Surgery ' + token);
        Department__c other = new Department__c(Name = 'Other ' + token);
        insert new List<Department__c>{ surgery, other };
        insert new List<AccountDepartment__c>{
            new AccountDepartment__c(Account__c = account.Id, Department__c = surgery.Id),
            new AccountDepartment__c(Account__c = otherAccount.Id, Department__c = other.Id)
        };

        Test.startTest();
        List<WoDebriefIMSchildWOController.DepartmentOption> none =
            WoDebriefIMSchildWOController.getDepartmentsForAccount(null);
        List<WoDebriefIMSchildWOController.DepartmentOption> rows =
            WoDebriefIMSchildWOController.getDepartmentsForAccount(account.Id);
        Test.stopTest();

        System.assertEquals(0, none.size());
        System.assertEquals(1, rows.size());
        System.assertEquals(surgery.Id, rows[0].id);
        System.assertEquals('Surgery ' + token, rows[0].name);
    }

    /**
     * @description Verifies a picture uploaded before the line exists can be linked to it.
     */
    @IsTest
    static void linkFilesToRecord_linksContentDocument() {
        String token = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        Account account = new Account(
            Name = 'Picture Account ' + token,
            SourceSystemID__c = 'ORACLE-PIC-' + token
        );
        insert account;
        ContentVersion version = new ContentVersion(
            Title = 'Repair photo',
            PathOnClient = 'repair.png',
            VersionData = Blob.valueOf('photo')
        );
        insert version;
        version = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id];

        Test.startTest();
        WoDebriefIMSchildWOController.linkFilesToRecord(null, new List<Id>{ version.ContentDocumentId });
        WoDebriefIMSchildWOController.linkFilesToRecord(account.Id, new List<Id>{ version.ContentDocumentId });
        WoDebriefIMSchildWOController.linkFilesToRecord(account.Id, new List<Id>{ version.ContentDocumentId });
        Test.stopTest();

        System.assertEquals(1, [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :account.Id
                AND ContentDocumentId = :version.ContentDocumentId
        ]);
    }

    /**
     * @description GW-375 - A mobile device picture is stored on the primary record and the parent record,
     *              and only those pictures are returned.
     */
    @IsTest
    static void saveMobileDevicePicture_linksPrimaryAndParent() {
        String token = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        Account instrumentLine = new Account(
            Name = 'Picture Line ' + token,
            SourceSystemID__c = 'ORACLE-PIC-LINE-' + token
        );
        Account siteVisit = new Account(
            Name = 'Picture Site Visit ' + token,
            SourceSystemID__c = 'ORACLE-PIC-SV-' + token
        );
        insert new List<Account>{ instrumentLine, siteVisit };
        ContentVersion otherFile = new ContentVersion(
            Title = 'Repair photo',
            PathOnClient = 'repair.png',
            VersionData = Blob.valueOf('other'),
            FirstPublishLocationId = instrumentLine.Id
        );
        insert otherFile;

        Test.startTest();
        WoDebriefIMSchildWOController.MobileDevicePicture saved =
            WoDebriefIMSchildWOController.saveMobileDevicePicture(
                instrumentLine.Id,
                siteVisit.Id,
                EncodingUtil.base64Encode(Blob.valueOf('mobile-picture')),
                'folder/tray.png',
                null
            );
        System.assertEquals(
            EncodingUtil.base64Encode(Blob.valueOf('mobile-picture')),
            WoDebriefIMSchildWOController.getMobileDevicePictureData(saved.contentVersionId)
        );
        List<WoDebriefIMSchildWOController.MobileDevicePicture> listed =
            WoDebriefIMSchildWOController.getMobileDevicePictures(
                new List<String>{
                    String.valueOf(instrumentLine.Id),
                    String.valueOf(siteVisit.Id),
                    null
                }
            );
        WoDebriefIMSchildWOController.MobileDevicePicture savedLower =
            WoDebriefIMSchildWOController.saveMobileDevicePicture(
                String.valueOf(instrumentLine.Id).toLowerCase(),
                null,
                EncodingUtil.base64Encode(Blob.valueOf('lower-case-id')),
                'MobileDevicePicture.jpg',
                null
            );
        System.assertEquals(instrumentLine.Id, savedLower.linkedEntityId);
        WoDebriefIMSchildWOController.saveMobileDevicePicture(
            instrumentLine.Id,
            instrumentLine.Id,
            'data:image/jpeg;base64,' + EncodingUtil.base64Encode(Blob.valueOf('same-record')),
            'notes.txt',
            null
        );
        Test.stopTest();

        System.assertEquals('Mobile Device Picture', saved.title);
        System.assertEquals(instrumentLine.Id, saved.linkedEntityId);
        System.assertEquals(2, listed.size(), 'Parent and primary each list the same mobile picture.');
        Set<Id> linkedIds = new Set<Id>();
        for (WoDebriefIMSchildWOController.MobileDevicePicture picture : listed) {
            System.assertEquals(saved.contentDocumentId, picture.contentDocumentId);
            linkedIds.add(picture.linkedEntityId);
        }
        System.assertEquals(new Set<Id>{ instrumentLine.Id, siteVisit.Id }, linkedIds);
        System.assertEquals(1, [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :saved.contentDocumentId
                AND LinkedEntityId = :siteVisit.Id
        ]);
        System.assertEquals(3, [
            SELECT COUNT()
            FROM ContentVersion
            WHERE Description = :WoDebriefIMSchildWOController.MOBILE_DEVICE_PICTURE_MARKER
                AND Title = :WoDebriefIMSchildWOController.MOBILE_DEVICE_PICTURE_TITLE
        ]);
    }

    /**
     * @description GW-375 - Empty requests and non-mobile files do not save or delete.
     */
    @IsTest
    static void mobileDevicePicture_guardsEmptyAndOtherFiles() {
        String token = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        Account account = new Account(
            Name = 'Picture Guard ' + token,
            SourceSystemID__c = 'ORACLE-PIC-GUARD-' + token
        );
        insert account;
        ContentVersion otherFile = new ContentVersion(
            Title = 'Not a mobile picture',
            PathOnClient = 'other.png',
            VersionData = Blob.valueOf('other'),
            Description = 'OtherCamera',
            FirstPublishLocationId = account.Id
        );
        insert otherFile;
        Id otherVersionId = otherFile.Id;
        otherFile = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :otherVersionId];

        List<WoDebriefIMSchildWOController.MobileDevicePicture> none =
            WoDebriefIMSchildWOController.getMobileDevicePictures(null);
        System.assertEquals(0, none.size());
        System.assertEquals(0, WoDebriefIMSchildWOController.getMobileDevicePictures(new List<String>()).size());
        System.assertEquals(0, WoDebriefIMSchildWOController.listMobileDevicePictures(null).size());
        System.assertEquals(0, WoDebriefIMSchildWOController.listMobileDevicePictures(' , ').size());
        WoDebriefIMSchildWOController.deleteMobileDevicePicture(null);

        Boolean blockedDelete = false;
        try {
            WoDebriefIMSchildWOController.deleteMobileDevicePicture(otherFile.ContentDocumentId);
        } catch (AuraHandledException ex) {
            blockedDelete = ex.getMessage().contains('Only a Mobile Device Picture');
        }
        System.assertEquals(true, blockedDelete);
        System.assertEquals(1, [SELECT COUNT() FROM ContentDocument WHERE Id = :otherFile.ContentDocumentId]);

        Boolean blockedSave = false;
        try {
            WoDebriefIMSchildWOController.saveMobileDevicePicture(null, account.Id, 'YQ==', 'a.jpg', null);
        } catch (AuraHandledException ex) {
            blockedSave = ex.getMessage().contains('record is required');
        }
        System.assertEquals(true, blockedSave);

        Boolean blockedPreview = false;
        try {
            WoDebriefIMSchildWOController.getMobileDevicePictureData(null);
        } catch (AuraHandledException ex) {
            blockedPreview = ex.getMessage().contains('picture is required');
        }
        System.assertEquals(true, blockedPreview);

        Boolean blockedOtherPreview = false;
        try {
            WoDebriefIMSchildWOController.getMobileDevicePictureData(otherFile.Id);
        } catch (AuraHandledException ex) {
            blockedOtherPreview = ex.getMessage().contains('could not be previewed');
        }
        System.assertEquals(true, blockedOtherPreview);
    }

    /**
     * @description GW-375 - Deleting a mobile device picture removes it from the primary record and the parent.
     */
    @IsTest
    static void deleteMobileDevicePicture_removesBothLinks() {
        String token = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        Account instrumentLine = new Account(
            Name = 'Delete Line ' + token,
            SourceSystemID__c = 'ORACLE-PIC-DEL-L-' + token
        );
        Account siteVisit = new Account(
            Name = 'Delete Site Visit ' + token,
            SourceSystemID__c = 'ORACLE-PIC-DEL-S-' + token
        );
        insert new List<Account>{ instrumentLine, siteVisit };
        WoDebriefIMSchildWOController.MobileDevicePicture saved =
            WoDebriefIMSchildWOController.saveMobileDevicePicture(
                instrumentLine.Id,
                siteVisit.Id,
                EncodingUtil.base64Encode(Blob.valueOf('delete-me')),
                'MobileDevicePicture.jpg',
                null
            );

        Test.startTest();
        WoDebriefIMSchildWOController.deleteMobileDevicePicture(saved.contentDocumentId);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM ContentDocument WHERE Id = :saved.contentDocumentId]);
        System.assertEquals(0, WoDebriefIMSchildWOController.getMobileDevicePictures(
            new List<String>{
                String.valueOf(instrumentLine.Id),
                String.valueOf(siteVisit.Id)
            }
        ).size());
    }

    /**
     * @description GW-375 - A line id whose case was removed still resolves to that line.
     */
    @IsTest
    static void resolveMobilePictureRecordId_matchesDamagedLineId() {
        String token = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        Account account = new Account(
            Name = 'Picture Resolve ' + token,
            SourceSystemID__c = 'ORACLE-PIC-RES-' + token
        );
        insert account;
        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            Subject = 'Picture Resolve ' + token
        );
        insert workOrder;
        Id lineId = WoDebriefIMSchildWOController.saveLaborLine(
            workOrder.Id,
            null,
            null,
            null,
            1,
            'Labor',
            null
        );
        String damagedLineId = String.valueOf(lineId).substring(0, 15).toLowerCase();

        Test.startTest();
        String resolved = WoDebriefIMSchildWOController.resolveMobilePictureRecordId(
            damagedLineId,
            String.valueOf(workOrder.Id).toLowerCase()
        );
        String resolvedDirect = WoDebriefIMSchildWOController.resolveMobilePictureRecordId(
            String.valueOf(lineId),
            null
        );
        String missing = WoDebriefIMSchildWOController.resolveMobilePictureRecordId(
            '000000000000000',
            workOrder.Id
        );
        Test.stopTest();

        System.assertEquals(String.valueOf(lineId), resolved);
        System.assertEquals(String.valueOf(lineId), resolvedDirect);
        System.assertEquals(null, missing);
        System.assertEquals(null, WoDebriefIMSchildWOController.resolveMobilePictureRecordId(null, null));
    }

    /**
     * @description GW-375 - A new product serviced line can be found when the mobile id cannot be read.
     */
    @IsTest
    static void findLatestProductServicedLineId_returnsNewestLine() {
        String token = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        Account account = new Account(
            Name = 'Picture Find ' + token,
            SourceSystemID__c = 'ORACLE-PIC-FIND-' + token
        );
        insert account;
        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            Subject = 'Picture Find ' + token
        );
        insert workOrder;
        Id productServicedRecordTypeId = Schema.SObjectType.WorkOrderLineItem
            .getRecordTypeInfosByDeveloperName()
            .get('ProductServiced')
            .getRecordTypeId();
        WorkOrderLineItem line = new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            RecordTypeId = productServicedRecordTypeId,
            LineType__c = 'Product Serviced'
        );
        insert line;

        Test.startTest();
        String found = WoDebriefIMSchildWOController.findLatestProductServicedLineId(
            String.valueOf(workOrder.Id).toLowerCase(),
            null
        );
        String missing = WoDebriefIMSchildWOController.findLatestProductServicedLineId(
            workOrder.Id,
            '000000000000000AAA'
        );
        Test.stopTest();

        System.assertEquals(String.valueOf(line.Id), found);
        System.assertEquals(null, missing);
        System.assertEquals(null, WoDebriefIMSchildWOController.findLatestProductServicedLineId(null, null));
    }

    /**
     * @description GW-375 - CRSS saves a picture when the mobile app lowercases the product serviced line id.
     */
    @IsTest
    static void saveMobileDevicePicture_resolvesDamagedProductServicedLineId() {
        String token = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        Account account = new Account(
            Name = 'Picture CRSS ' + token,
            SourceSystemID__c = 'ORACLE-PIC-CRSS-' + token
        );
        insert account;
        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            Subject = 'Picture CRSS ' + token
        );
        insert workOrder;
        Id productServicedRecordTypeId = Schema.SObjectType.WorkOrderLineItem
            .getRecordTypeInfosByDeveloperName()
            .get('ProductServiced')
            .getRecordTypeId();
        WorkOrderLineItem line = new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            RecordTypeId = productServicedRecordTypeId,
            LineType__c = 'Product Serviced'
        );
        insert line;
        String damagedLineId = String.valueOf(line.Id).substring(0, 15).toLowerCase();
        String damagedWorkOrderId = String.valueOf(workOrder.Id).toLowerCase();

        Test.startTest();
        WoDebriefIMSchildWOController.MobileDevicePicture saved =
            WoDebriefIMSchildWOController.saveMobileDevicePicture(
                damagedLineId,
                null,
                EncodingUtil.base64Encode(Blob.valueOf('crss-line-photo')),
                'MobileDevicePicture.jpg',
                damagedWorkOrderId
            );
        Test.stopTest();

        System.assertEquals(line.Id, saved.linkedEntityId);
        WorkOrderLineItem counted = [
            SELECT MobileDevicePictureCount__c
            FROM WorkOrderLineItem
            WHERE Id = :line.Id
        ];
        System.assertEquals(1, counted.MobileDevicePictureCount__c);
    }

    /**
     * @description GW-375 - CRSS can send the work order id inside the primary token when Aura drops extra params.
     */
    @IsTest
    static void saveMobileDevicePicture_parsesCompositePrimaryRecordId() {
        String token = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        Account account = new Account(
            Name = 'Picture Composite ' + token,
            SourceSystemID__c = 'ORACLE-PIC-COMP-' + token
        );
        insert account;
        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            Subject = 'Picture Composite ' + token
        );
        insert workOrder;
        Id productServicedRecordTypeId = Schema.SObjectType.WorkOrderLineItem
            .getRecordTypeInfosByDeveloperName()
            .get('ProductServiced')
            .getRecordTypeId();
        WorkOrderLineItem line = new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            RecordTypeId = productServicedRecordTypeId,
            LineType__c = 'Product Serviced'
        );
        insert line;
        String damagedLineId = String.valueOf(line.Id).substring(0, 15).toLowerCase();
        String damagedWorkOrderId = String.valueOf(workOrder.Id).toLowerCase();
        String compositePrimary = damagedLineId + '::' + damagedWorkOrderId;

        Test.startTest();
        WoDebriefIMSchildWOController.MobileDevicePicture saved =
            WoDebriefIMSchildWOController.saveMobileDevicePicture(
                compositePrimary,
                null,
                EncodingUtil.base64Encode(Blob.valueOf('composite-line-photo')),
                'MobileDevicePicture.jpg',
                null
            );
        Test.stopTest();

        System.assertEquals(line.Id, saved.linkedEntityId);
    }

    /**
     * @description GW-375 - The instrument line stores how many Mobile Device Pictures it has.
     */
    @IsTest
    static void saveMobileDevicePicture_stampsLineCount() {
        String token = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        Account account = new Account(
            Name = 'Picture Count ' + token,
            SourceSystemID__c = 'ORACLE-PIC-CNT-' + token
        );
        insert account;
        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            Subject = 'Picture Count ' + token
        );
        insert workOrder;
        Id lineId = WoDebriefIMSchildWOController.saveLaborLine(
            workOrder.Id,
            null,
            null,
            null,
            1,
            'Labor',
            null
        );

        Test.startTest();
        WoDebriefIMSchildWOController.MobileDevicePicture firstPicture =
            WoDebriefIMSchildWOController.saveMobileDevicePicture(
                lineId,
                workOrder.Id,
                EncodingUtil.base64Encode(Blob.valueOf('line-photo-1')),
                'MobileDevicePicture.jpg',
                null
            );
        WoDebriefIMSchildWOController.saveMobileDevicePicture(
            lineId,
            workOrder.Id,
            EncodingUtil.base64Encode(Blob.valueOf('line-photo-2')),
            'MobileDevicePicture.jpg',
            null
        );
        WorkOrderLineItem afterSave = [
            SELECT MobileDevicePictureCount__c
            FROM WorkOrderLineItem
            WHERE Id = :lineId
        ];
        WoDebriefIMSchildWOController.deleteMobileDevicePicture(firstPicture.contentDocumentId);
        Test.stopTest();

        WorkOrderLineItem afterDelete = [
            SELECT MobileDevicePictureCount__c
            FROM WorkOrderLineItem
            WHERE Id = :lineId
        ];
        System.assertEquals(2, afterSave.MobileDevicePictureCount__c);
        System.assertEquals(1, afterDelete.MobileDevicePictureCount__c);
    }

    /**
     * @description GW-312 - Record type used by Instrument lines.
     * @return ProductServiced record type Id
     */
    private static Id instrumentRecordTypeId() {
        return Schema.SObjectType.WorkOrderLineItem
            .getRecordTypeInfosByDeveloperName()
            .get('ProductServiced')
            .getRecordTypeId();
    }

    /**
     * @description GW-312 - Inserts a child Work Order for the Complete Work Order tests.
     * @param token Unique suffix
     * @return Inserted child Work Order
     */
    private static WorkOrder createChildWorkOrderForCompletion(String token) {
        Account account = new Account(
            Name = 'Complete Child ' + token,
            SourceSystemID__c = 'ORACLE-CMP-' + token
        );
        insert account;
        WorkOrder siteVisit = new WorkOrder(AccountId = account.Id, Subject = 'Complete Site Visit ' + token);
        insert siteVisit;
        WorkOrder child = new WorkOrder(
            AccountId = account.Id,
            ParentWorkOrderId = siteVisit.Id,
            Subject = 'Complete Child ' + token
        );
        insert child;
        return child;
    }

    /**
     * @description GW-312 - Lines missing a Service Code or a picture block completion.
     */
    @IsTest
    static void completeChildWorkOrder_missingServiceCodeOrPicture_blocks() {
        String token = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        WorkOrder child = createChildWorkOrderForCompletion(token);
        insert new List<WorkOrderLineItem>{
            new WorkOrderLineItem(
                WorkOrderId = child.Id,
                RecordTypeId = instrumentRecordTypeId(),
                LineType__c = 'Instrument',
                MobileDevicePictureCount__c = 1
            ),
            new WorkOrderLineItem(
                WorkOrderId = child.Id,
                RecordTypeId = instrumentRecordTypeId(),
                LineType__c = 'Instrument',
                RepairLevel__c = '1'
            ),
            new WorkOrderLineItem(WorkOrderId = child.Id, LineType__c = 'Labor')
        };

        Test.startTest();
        WoDebriefIMSchildWOController.CompletionCheckResult check =
            WoDebriefIMSchildWOController.getCompletionCheck(child.Id);
        Boolean blocked = false;
        try {
            WoDebriefIMSchildWOController.completeChildWorkOrder(child.Id);
        } catch (AuraHandledException ex) {
            blocked = ex.getMessage().contains('cannot be completed');
        }
        Test.stopTest();

        System.assertEquals(false, check.canComplete);
        System.assertEquals(2, check.missingLines.size(), 'Only instrument lines are checked.');
        System.assert(check.missingLines[0].contains('Service Code') || check.missingLines[1].contains('Service Code'));
        System.assert(check.missingLines[0].contains('2 pictures'), 'One picture is not enough.');
        System.assert(check.missingLines[1].contains('2 pictures'), 'A line without pictures is blocked.');
        System.assertEquals(true, blocked);
        System.assertNotEquals('Completed', [SELECT Status FROM WorkOrder WHERE Id = :child.Id].Status);
    }

    /**
     * @description GW-312 - A child Work Order without instrument lines cannot be completed.
     */
    @IsTest
    static void completeChildWorkOrder_noInstrumentLines_blocks() {
        String token = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        WorkOrder child = createChildWorkOrderForCompletion(token);
        insert new WorkOrderLineItem(WorkOrderId = child.Id, LineType__c = 'Labor');

        Test.startTest();
        WoDebriefIMSchildWOController.CompletionCheckResult check =
            WoDebriefIMSchildWOController.getCompletionCheck(child.Id);
        Test.stopTest();

        System.assertEquals(false, check.canComplete);
        System.assertEquals(1, check.missingLines.size());
        System.assert(check.missingLines[0].contains('at least one instrument line'), check.missingLines[0]);
    }

    /**
     * @description GW-312 - Complete lines set the child to Completed and list Repair Center lines.
     */
    @IsTest
    static void completeChildWorkOrder_allLinesReady_setsCompleted() {
        String token = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        WorkOrder child = createChildWorkOrderForCompletion(token);
        insert new List<WorkOrderLineItem>{
            new WorkOrderLineItem(
                WorkOrderId = child.Id,
                RecordTypeId = instrumentRecordTypeId(),
                LineType__c = 'Instrument',
                RepairLevel__c = '1',
                MobileDevicePictureCount__c = 2,
                SendToRepairCenter__c = true
            ),
            new WorkOrderLineItem(
                WorkOrderId = child.Id,
                RecordTypeId = instrumentRecordTypeId(),
                LineType__c = 'Instrument',
                Status = 'Canceled'
            )
        };

        Test.startTest();
        WoDebriefIMSchildWOController.CompletionCheckResult result =
            WoDebriefIMSchildWOController.completeChildWorkOrder(child.Id);
        Test.stopTest();

        System.assertEquals(true, result.canComplete, 'Canceled lines are skipped.');
        System.assertEquals(1, result.repairCenterLines.size());
        System.assertEquals('Completed', [SELECT Status FROM WorkOrder WHERE Id = :child.Id].Status);
    }

    /**
     * @description GW-312 - A missing Work Order Id cannot be checked.
     */
    @IsTest
    static void getCompletionCheck_nullWorkOrder_throws() {
        Boolean blocked = false;
        try {
            WoDebriefIMSchildWOController.getCompletionCheck(null);
        } catch (AuraHandledException ex) {
            blocked = ex.getMessage().contains('could not be identified');
        }
        System.assertEquals(true, blocked);
    }

    /**
     * @description A Beyond Repair picture is saved on the line and is not counted as a Mobile Device Picture.
     */
    @IsTest
    static void saveBeyondRepairPicture_savesOnLineWithoutCounting() {
        String token = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        WorkOrder child = createChildWorkOrderForCompletion(token);
        WorkOrderLineItem line = new WorkOrderLineItem(
            WorkOrderId = child.Id,
            RecordTypeId = instrumentRecordTypeId(),
            LineType__c = 'Instrument'
        );
        insert line;

        Test.startTest();
        WoDebriefIMSchildWOController.MobileDevicePicture saved =
            WoDebriefIMSchildWOController.saveBeyondRepairPicture(
                line.Id,
                EncodingUtil.base64Encode(Blob.valueOf('beyond-repair')),
                'BeyondRepairPicture.jpg'
            );
        Boolean blocked = false;
        try {
            WoDebriefIMSchildWOController.saveBeyondRepairPicture(
                child.Id,
                EncodingUtil.base64Encode(Blob.valueOf('beyond-repair')),
                'BeyondRepairPicture.jpg'
            );
        } catch (AuraHandledException ex) {
            blocked = true;
        }
        Test.stopTest();

        System.assertNotEquals(null, saved.contentDocumentId);
        System.assertEquals(1, [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :saved.contentDocumentId
                AND LinkedEntityId = :line.Id
        ]);
        Decimal pictureCount = [SELECT MobileDevicePictureCount__c FROM WorkOrderLineItem WHERE Id = :line.Id]
            .MobileDevicePictureCount__c;
        System.assertEquals(
            0,
            pictureCount == null ? 0 : pictureCount,
            'Beyond Repair pictures do not count as Mobile Device Pictures'
        );
        System.assertEquals(true, blocked, 'Only an instrument line can hold a Beyond Repair picture');
    }
}