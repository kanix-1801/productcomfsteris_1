/**
 * @description GW-2710 - Tests for Tech Account Alignment upload, template download, and assignment rules.
 */
@IsTest
private class TechAccountAlignmentControllerTest {
    private static final String ORACLE_ADDRESS_VALID = '2710001';
    private static final String ORACLE_ADDRESS_BILL_TO = '2710002';
    private static final String ORACLE_ADDRESS_INACTIVE = '2710003';
    private static final String ORACLE_ADDRESS_NOT_SERVICEABLE = '2710004';
    private static final String ORACLE_ADDRESS_DISTRIBUTOR = '2710005';
    private static final String WORK_TYPE_NAME = 'GW2710 Installation';

    @TestSetup
    static void setupData() {
        Account customer = new Account(
            Name = 'GW2710 Customer',
            AccountNumber = '2710-C',
            OrgIDs__c = '82',
            SourceSystemID__c = 'GW2710CUST01',
            SystemID__c = 'GW2710CUST02'
        );
        Account distributorParent = new Account(
            Name = 'GW2710 Distributor',
            AccountNumber = '2710-D',
            OrgIDs__c = '82',
            SourceSystemID__c = 'GW2710DIST01',
            SystemID__c = 'GW2710DIST02',
            SMI__c = 'Distributor HC'
        );
        insert new List<Account>{ customer, distributorParent };

        Account validAddress = addressAccount('GW2710 Valid Ship To', customer.Id, ORACLE_ADDRESS_VALID, 'Active', null, false, 'GW2710ADDR01');
        Account billToOnly = addressAccount('GW2710 Bill To Only', customer.Id, ORACLE_ADDRESS_BILL_TO, 'Inactive', 'Primary', false, 'GW2710ADDR02');
        Account inactiveShipTo = addressAccount('GW2710 Inactive Ship To', customer.Id, ORACLE_ADDRESS_INACTIVE, 'Inactive', null, false, 'GW2710ADDR03');
        Account notServiceable = addressAccount('GW2710 No Equipment Here', customer.Id, ORACLE_ADDRESS_NOT_SERVICEABLE, 'Active', null, true, 'GW2710ADDR04');
        Account distributorAddress = addressAccount('GW2710 Distributor Address', distributorParent.Id, ORACLE_ADDRESS_DISTRIBUTOR, 'Active', null, false, 'GW2710ADDR05');
        insert new List<Account>{ validAddress, billToOnly, inactiveShipTo, notServiceable, distributorAddress };

        insert new WorkType(
            Name = WORK_TYPE_NAME,
            EstimatedDuration = 1,
            DurationType = 'Hours'
        );

        insert new ServiceResource(
            Name = 'GW2710 Technician',
            IsActive = true,
            RelatedRecordId = UserInfo.getUserId(),
            ResourceType = 'T',
            ExternalID__c = 'GW2710-' + String.valueOf(Crypto.getRandomInteger())
        );
    }

    @IsTest
    static void processUpload_createsPreferredAssignment() {
        Id documentId = insertCsv(
            headerRow() +
            csvRow(ORACLE_ADDRESS_VALID, UserInfo.getUserId(), 'Surgical', WORK_TYPE_NAME, 'Preferred')
        );

        Test.startTest();
        TechAccountAlignmentService.ProcessResult result =
            TechAccountAlignmentController.processUpload(documentId);
        Test.stopTest();

        Assert.areEqual(1, result.processedCount);
        Assert.areEqual(1, result.createdCount);
        Assert.areEqual(0, result.skippedCount);

        Account addressAccount = [SELECT Id FROM Account WHERE OracleAddressId__c = :ORACLE_ADDRESS_VALID];
        AddressResourcePreference__c preference = [
            SELECT
                Name,
                AddressAccount__c,
                ServiceResource__c,
                PreferenceLevel__c,
                TerritoryType__c,
                WorkType__c
            FROM AddressResourcePreference__c
            WHERE AddressAccount__c = :addressAccount.Id
            LIMIT 1
        ];
        Assert.areEqual(addressAccount.Id, preference.AddressAccount__c);
        Assert.areEqual('Preferred', preference.PreferenceLevel__c);
        Assert.areEqual('Surgical', preference.TerritoryType__c);
        Assert.isTrue(preference.Name.contains('Surgical'));
    }

    @IsTest
    static void processUpload_skipsAssignmentRuleViolations() {
        String userId = UserInfo.getUserId();
        Id documentId = insertCsv(
            headerRow() +
            csvRow(ORACLE_ADDRESS_BILL_TO, userId, 'IPTLS', '', 'Preferred') +
            csvRow(ORACLE_ADDRESS_INACTIVE, userId, 'IPTLS', '', 'Preferred') +
            csvRow(ORACLE_ADDRESS_NOT_SERVICEABLE, userId, 'IPTLS', '', 'Preferred') +
            csvRow(ORACLE_ADDRESS_DISTRIBUTOR, userId, 'IPTLS', '', 'Preferred') +
            csvRow('9999999', userId, 'IPTLS', '', 'Preferred') +
            csvRow(ORACLE_ADDRESS_VALID, 'not-a-user-id', 'IPTLS', '', 'Preferred')
        );

        Test.startTest();
        TechAccountAlignmentService.ProcessResult result =
            TechAccountAlignmentController.processUpload(documentId);
        Test.stopTest();

        Assert.areEqual(6, result.processedCount);
        Assert.areEqual(0, result.createdCount);
        Assert.areEqual(6, result.skippedCount);
        Assert.isTrue(containsMessage(result.errors, 'Bill-To-only'));
        Assert.isTrue(containsMessage(result.errors, 'active ship-to'));
        Assert.isTrue(containsMessage(result.errors, 'No Equipment Here'));
        Assert.isTrue(containsMessage(result.errors, 'distributor'));
        Assert.isTrue(containsMessage(result.errors, 'No Address account found'));
        Assert.isTrue(containsMessage(result.errors, 'User ID must match'));
    }

    @IsTest
    static void processUpload_skipsDuplicatePreference() {
        String userId = UserInfo.getUserId();
        Id firstDocumentId = insertCsv(
            headerRow() +
            csvRow(ORACLE_ADDRESS_VALID, userId, 'Low Temp', '', 'Preferred')
        );
        TechAccountAlignmentController.processUpload(firstDocumentId);

        Id secondDocumentId = insertCsv(
            headerRow() +
            csvRow(ORACLE_ADDRESS_VALID, userId, 'Low Temp', '', 'Preferred')
        );

        Test.startTest();
        TechAccountAlignmentService.ProcessResult result =
            TechAccountAlignmentController.processUpload(secondDocumentId);
        Test.stopTest();

        Assert.areEqual(1, result.processedCount);
        Assert.areEqual(0, result.createdCount);
        Assert.areEqual(1, result.skippedCount);
        Assert.isTrue(containsMessage(result.errors, 'already exists'));
        Assert.areEqual(1, [SELECT COUNT() FROM AddressResourcePreference__c]);
    }

    @IsTest
    static void processUpload_throwsWhenFileMissing() {
        AuraHandledException thrown;
        try {
            TechAccountAlignmentController.processUpload(null);
        } catch (AuraHandledException e) {
            thrown = e;
        }
        Assert.isNotNull(thrown);
        Assert.isTrue(thrown.getMessage().contains('Upload a file'));
    }

    @IsTest
    static void processUpload_throwsWhenColumnsMissing() {
        Id documentId = insertCsv('Wrong Header,Another Header\n1,2\n');
        AuraHandledException thrown;
        try {
            TechAccountAlignmentController.processUpload(documentId);
        } catch (AuraHandledException e) {
            thrown = e;
        }
        Assert.isNotNull(thrown);
        Assert.isTrue(thrown.getMessage().contains('Address ID and User ID'));
    }

    @IsTest
    static void getTemplateDownloadUrl_returnsFileUrl() {
        Test.startTest();
        String url = TechAccountAlignmentController.getTemplateDownloadUrl();
        Test.stopTest();

        Assert.isTrue(url.startsWith('/sfc/servlet.shepherd/document/download/'));
        Id documentId = Id.valueOf(url.substringAfterLast('/'));
        Assert.areEqual(1, [SELECT COUNT() FROM ContentDocument WHERE Id = :documentId]);
        FieldServiceBackofficeConfig__c config = FieldServiceBackofficeConfig__c.getOrgDefaults();
        Assert.areEqual(String.valueOf(documentId), config.TechAccountAlignmentTemplateId__c);
    }

    @IsTest
    static void processUpload_coversRemainingSkipAndSuccessPaths() {
        String userId = UserInfo.getUserId();
        Id documentId = insertCsv(
            'Address ID,User ID,Territory Type,Work Type,Preference Level,District Type,Preference Type\n' +
            csvRow(ORACLE_ADDRESS_VALID, userId, '', '', '') +
            csvRow(ORACLE_ADDRESS_VALID, userId, 'Surgical', '', '') +
            csvRow(ORACLE_ADDRESS_VALID, userId, 'Surgical', '', 'Preferred') +
            csvRow('', userId, 'Surgical', '', 'Preferred') +
            csvRow(ORACLE_ADDRESS_VALID, '', 'Surgical', '', 'Preferred') +
            csvRow(ORACLE_ADDRESS_VALID, '005000000000001AAA', 'Surgical', '', 'Preferred') +
            csvRow(ORACLE_ADDRESS_VALID, userId, 'NotATerritory', '', 'Preferred') +
            csvRow(ORACLE_ADDRESS_VALID, userId, 'Surgical', 'Missing Work Type', 'Preferred') +
            csvRow(ORACLE_ADDRESS_VALID, userId, 'IPTLS', '', 'Maybe') +
            '"' + ORACLE_ADDRESS_VALID + '","' + userId + '","Low Temp","' + WORK_TYPE_NAME + '","Preferred"\n'
        );

        Test.startTest();
        TechAccountAlignmentService.ProcessResult result =
            TechAccountAlignmentController.processUpload(documentId);
        Test.stopTest();

        Assert.isTrue(result.createdCount >= 2);
        Assert.isTrue(containsMessage(result.errors, 'Address ID is required'));
        Assert.isTrue(containsMessage(result.errors, 'User ID is required'));
        Assert.isTrue(containsMessage(result.errors, 'active Service Resource'));
        Assert.isTrue(containsMessage(result.errors, 'Territory Type is not valid'));
        Assert.isTrue(containsMessage(result.errors, 'Work Type not found'));
        Assert.isTrue(containsMessage(result.errors, 'Preference Level is not valid'));
        Assert.isTrue(containsMessage(result.errors, 'already exists'));
    }

    @IsTest
    static void processUpload_readsExcelTemplate() {
        Id documentId = insertFile(
            'gw2710.xlsx',
            buildXlsx(
                ORACLE_ADDRESS_VALID,
                UserInfo.getUserId(),
                'On Location',
                WORK_TYPE_NAME,
                'Required'
            )
        );

        Test.startTest();
        TechAccountAlignmentService.ProcessResult result =
            TechAccountAlignmentController.processUpload(documentId);
        Test.stopTest();

        Assert.areEqual(1, result.processedCount);
        Assert.areEqual(1, result.createdCount);
        AddressResourcePreference__c preference = [
            SELECT PreferenceLevel__c, TerritoryType__c
            FROM AddressResourcePreference__c
            LIMIT 1
        ];
        Assert.areEqual('Required', preference.PreferenceLevel__c);
        Assert.areEqual('On Location', preference.TerritoryType__c);
    }

    @IsTest
    static void processUpload_throwsWhenExcelCannotBeRead() {
        Id documentId = insertFile('gw2710.xlsx', Blob.valueOf('not-a-zip'));
        AuraHandledException thrown;
        try {
            TechAccountAlignmentController.processUpload(documentId);
        } catch (AuraHandledException e) {
            thrown = e;
        }
        Assert.isNotNull(thrown);
        Assert.isTrue(thrown.getMessage().contains('Excel'));
    }

    @IsTest
    static void processUpload_throwsWhenFileEmpty() {
        Id documentId = insertCsv('\n');
        AuraHandledException thrown;
        try {
            TechAccountAlignmentController.processUpload(documentId);
        } catch (AuraHandledException e) {
            thrown = e;
        }
        Assert.isNotNull(thrown);
        Assert.isTrue(thrown.getMessage().contains('empty'));
    }

    @IsTest
    static void getTemplateDownloadUrl_reusesStoredDocument() {
        String firstUrl = TechAccountAlignmentController.getTemplateDownloadUrl();
        FieldServiceBackofficeConfig__c config = FieldServiceBackofficeConfig__c.getOrgDefaults();
        config.TechAccountAlignmentTemplateId__c = 'not-an-id';
        upsert config;

        Test.startTest();
        String secondUrl = TechAccountAlignmentController.getTemplateDownloadUrl();
        Test.stopTest();

        Assert.areEqual(firstUrl.substringAfterLast('/').left(15), secondUrl.substringAfterLast('/').left(15));
    }

    @IsTest
    static void selector_returnsEmptyForBlankFilters() {
        Assert.areEqual(0, AccountSelector.selectAddressAccountsByOracleAddressIds(new Set<String>()).size());
        Assert.areEqual(0, ServiceResourcesSelector.selectActiveByRelatedRecordIds(new Set<Id>()).size());
        Assert.areEqual(0, WorkTypesSelector.selectByNames(new Set<String>()).size());
        Assert.areEqual(0, AddressResourcePreferencesSelector.selectByAddressAccountIds(new Set<Id>()).size());
        Assert.areEqual(0, ContentVersionsSelector.selectLatestByContentDocumentId(null).size());
        Assert.areEqual(0, ContentVersionsSelector.selectDocumentIdByVersionId(null).size());
        Assert.areEqual(0, ContentDocumentsSelector.selectIdAndTitleByIds(null).size());
        Assert.areEqual(0, ContentDocumentsSelector.selectLatestByTitle(null).size());
        Assert.areEqual(0, StaticResourcesSelector.selectByName(null).size());
    }

    private static Account addressAccount(
        String name,
        Id parentId,
        String oracleAddressId,
        String shipToStatus,
        String billToStatus,
        Boolean notServiceable,
        String sourceSystemId
    ) {
        return new Account(
            Name = name,
            ParentId = parentId,
            Type = 'Address',
            OracleAddressId__c = oracleAddressId,
            ShiptoAddressStatus__c = shipToStatus,
            BilltoAddressStatus__c = billToStatus,
            NotServiceable__c = notServiceable,
            OrgIDs__c = '82',
            SourceSystemID__c = sourceSystemId,
            SystemID__c = sourceSystemId.left(12) + 'X',
            AccountNumber = oracleAddressId
        );
    }

    private static String headerRow() {
        return 'Address ID,User ID,Territory Type,Work Type,Preference Level\n';
    }

    private static String csvRow(
        String addressId,
        String userId,
        String territoryType,
        String workTypeName,
        String preferenceLevel
    ) {
        return addressId +
            ',' +
            userId +
            ',' +
            territoryType +
            ',' +
            workTypeName +
            ',' +
            preferenceLevel +
            '\n';
    }

    private static Id insertCsv(String csvBody) {
        return insertFile('gw2710.csv', Blob.valueOf(csvBody));
    }

    private static Id insertFile(String pathOnClient, Blob versionData) {
        ContentVersion version = new ContentVersion(
            Title = 'GW2710 Upload',
            PathOnClient = pathOnClient,
            VersionData = versionData,
            IsMajorVersion = true
        );
        insert version;
        return [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
        ].ContentDocumentId;
    }

    private static Blob buildXlsx(
        String addressId,
        String userId,
        String territoryType,
        String workTypeName,
        String preferenceLevel
    ) {
        String sharedStrings =
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
            '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' +
            '<si><t>Address ID</t></si>' +
            '<si><t>User ID</t></si>' +
            '<si><t>Territory Type</t></si>' +
            '<si><t>Work Type</t></si>' +
            '<si><t>Preference Level</t></si>' +
            '<si><t>' + addressId + '</t></si>' +
            '<si><t>' + userId + '</t></si>' +
            '<si><t>' + territoryType + '</t></si>' +
            '<si><t>' + workTypeName + '</t></si>' +
            '<si><t>' + preferenceLevel + '</t></si>' +
            '</sst>';
        String sheet =
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
            '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' +
            '<sheetData>' +
            '<row r="1">' +
            '<c r="A1" t="s"><v>0</v></c>' +
            '<c r="B1" t="s"><v>1</v></c>' +
            '<c r="C1" t="s"><v>2</v></c>' +
            '<c r="D1" t="s"><v>3</v></c>' +
            '<c r="E1" t="s"><v>4</v></c>' +
            '</row>' +
            '<row r="2">' +
            '<c r="A2" t="s"><v>5</v></c>' +
            '<c r="B2" t="s"><v>6</v></c>' +
            '<c r="C2" t="s"><v>7</v></c>' +
            '<c r="D2" t="inlineStr"><is><t>' + workTypeName + '</t></is></c>' +
            '<c r="E2" t="s"><v>9</v></c>' +
            '</row>' +
            '</sheetData></worksheet>';

        Compression.ZipWriter writer = new Compression.ZipWriter();
        writer.addEntry('xl/sharedStrings.xml', Blob.valueOf(sharedStrings));
        writer.addEntry('xl/worksheets/sheet1.xml', Blob.valueOf(sheet));
        return writer.getArchive();
    }

    private static Boolean containsMessage(List<String> errors, String fragment) {
        if (errors == null) {
            return false;
        }
        for (String error : errors) {
            if (error != null && error.contains(fragment)) {
                return true;
            }
        }
        return false;
    }
}