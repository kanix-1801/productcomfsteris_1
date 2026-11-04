/**
 * @description GW-2706 - Tests for District Zone Alignment upload, error file, template download and row rules.
 */
@IsTest
private class DistrictZoneAlignmentControllerTest {
    private static final String ZONE_BY_REGION = 'Z2706-R';
    private static final String ZONE_BY_NAME = 'Z2706-NAME';
    private static final String ZONE_DUPLICATE_NAME = 'Z2706-DUP';
    private static final String DISTRICT_ONE = 'D2706-1';
    private static final String DISTRICT_TWO = 'D2706-2';
    private static final String ASM_NAME = 'Gwasm Twosevenzerosix';
    private static final String DUPLICATE_ASM_NAME = 'Gwdup Twosevenzerosix';

    @TestSetup
    static void setupData() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new List<User>{
                asmUser('Gwasm', 'a'),
                asmUser('Gwdup', 'b'),
                asmUser('Gwdup', 'c')
            };
        }

        OperatingHours hours = new OperatingHours(Name = 'GW2706 Hours', TimeZone = 'America/New_York');
        insert hours;

        ServiceTerritory zoneByRegion = zone('GW2706 Zone Region', ZONE_BY_REGION, hours.Id);
        ServiceTerritory zoneByName = zone(ZONE_BY_NAME, null, hours.Id);
        insert new List<ServiceTerritory>{ zoneByRegion, zoneByName};

        insert new List<ServiceTerritory>{
            new ServiceTerritory(
                Name = 'GW2706 District One',
                RegionNumber__c = DISTRICT_ONE,
                ParentTerritoryId = zoneByName.Id,
                OperatingHoursId = hours.Id,
                IsActive = true
            ),
            new ServiceTerritory(
                Name = 'GW2706 District Two',
                RegionNumber__c = DISTRICT_TWO,
                ParentTerritoryId = zoneByRegion.Id,
                TerritoryManager__c = UserInfo.getUserId(),
                OperatingHoursId = hours.Id,
                IsActive = true
            )
        };
    }

    @IsTest
    static void processUpload_createsDistrictUnderZone() {
        Id documentId = insertCsv(
            headerRow() +
            csvRow('-', 'D2706-NEW', ASM_NAME, 'SVC D2706 - (SC) East', ZONE_BY_NAME)
        );

        Test.startTest();
        DistrictZoneAlignmentService.ProcessResult result = DistrictZoneAlignmentController.processUpload(documentId);
        Test.stopTest();

        Assert.areEqual(1, result.processedCount);
        Assert.areEqual(1, result.createdCount);
        Assert.areEqual(0, result.skippedCount);

        ServiceTerritory zone = [SELECT Id, OperatingHoursId FROM ServiceTerritory WHERE Name = :ZONE_BY_NAME];
        ServiceTerritory district = [
            SELECT Name, ParentTerritoryId, TerritoryManager__c, OperatingHoursId, IsActive
            FROM ServiceTerritory
            WHERE RegionNumber__c = 'D2706-NEW'
        ];
        Assert.areEqual('SVC D2706 - (SC) East', district.Name);
        Assert.areEqual(zone.Id, district.ParentTerritoryId);
        Assert.areEqual(zone.OperatingHoursId, district.OperatingHoursId);
        Assert.areEqual(asmUserId(), district.TerritoryManager__c);
        Assert.isTrue(district.IsActive);
    }

    @IsTest
    static void processUpload_updatesManagerZoneNumberAndName() {
        Id documentId = insertCsv(
            headerRow() +
            csvRow(DISTRICT_ONE, 'D2706-1B', ASM_NAME, 'GW2706 District One Renamed', ZONE_BY_REGION) +
            csvRow(DISTRICT_TWO, DISTRICT_TWO, '', '', ZONE_BY_REGION)
        );

        Test.startTest();
        DistrictZoneAlignmentService.ProcessResult result = DistrictZoneAlignmentController.processUpload(documentId);
        Test.stopTest();

        Assert.areEqual(2, result.processedCount);
        Assert.areEqual(1, result.updatedCount);
        Assert.areEqual(1, result.unchangedCount);
        Assert.areEqual(0, result.skippedCount);

        ServiceTerritory zone = [SELECT Id FROM ServiceTerritory WHERE RegionNumber__c = :ZONE_BY_REGION];
        ServiceTerritory district = [
            SELECT Name, ParentTerritoryId, TerritoryManager__c
            FROM ServiceTerritory
            WHERE RegionNumber__c = 'D2706-1B'
        ];
        Assert.areEqual('GW2706 District One Renamed', district.Name);
        Assert.areEqual(zone.Id, district.ParentTerritoryId);
        Assert.areEqual(asmUserId(), district.TerritoryManager__c);
    }

    @IsTest
    static void processUpload_skipsInvalidRowsIntoErrorFile() {
        Id documentId = insertCsv(
            headerRow() +
            csvRow('-', '', '', '', ZONE_BY_REGION) +
            csvRow('-', 'D2706-X', '', '', '') +
            csvRow('-', 'D2706-X', '', '', 'NO-SUCH-ZONE') +
            csvRow('-', 'D2706-X', '', '', ZONE_DUPLICATE_NAME) +
            csvRow('-', DISTRICT_ONE, '', '', ZONE_BY_REGION) +
            csvRow('-', 'D2706-Y', 'Nobody Twosevenzerosix', '', ZONE_BY_REGION) +
            csvRow('-', 'D2706-Z', DUPLICATE_ASM_NAME, '', ZONE_BY_REGION) +
            csvRow('NO-SUCH-DISTRICT', 'D2706-Q', '', '', ZONE_BY_REGION) +
            csvRow(DISTRICT_TWO, DISTRICT_ONE, '', '', ZONE_BY_REGION) +
            csvRow(ZONE_BY_REGION, ZONE_BY_REGION, '', '', ZONE_BY_REGION) +
            csvRow(DISTRICT_TWO, DISTRICT_TWO, '', '', ZONE_BY_REGION) +
            csvRow(DISTRICT_TWO, DISTRICT_TWO, '', '', ZONE_BY_REGION)
        );

        Test.startTest();
        DistrictZoneAlignmentService.ProcessResult result = DistrictZoneAlignmentController.processUpload(documentId);
        Test.stopTest();

        Assert.areEqual(12, result.processedCount);
        Assert.areEqual(0, result.createdCount);
        Assert.areEqual(0, result.updatedCount);
        Assert.areEqual(1, result.unchangedCount);
        Assert.areEqual(11, result.skippedCount);
        Assert.isTrue(containsMessage(result.errors, 'Row 2: Invalid future district#: Future District # is required'));
        Assert.isTrue(containsMessage(result.errors, 'Invalid future zone#: Future Zone # is required'));
        Assert.isTrue(containsMessage(result.errors, 'No Zone territory found'));
        Assert.isTrue(containsMessage(result.errors, 'More than one Zone territory'));
        Assert.isTrue(containsMessage(result.errors, 'already exists'));
        Assert.isTrue(containsMessage(result.errors, 'Invalid future ASM: No active user found'));
        Assert.isTrue(containsMessage(result.errors, 'Invalid future ASM: More than one active user'));
        Assert.isTrue(containsMessage(result.errors, 'Invalid current district#: No territory found'));
        Assert.isTrue(containsMessage(result.errors, 'already used by another territory'));
        Assert.isTrue(containsMessage(result.errors, 'cannot be its own zone'));
        Assert.isTrue(containsMessage(result.errors, 'appears more than once'));

        Assert.isNotNull(result.errorFileDocumentId);
        ContentVersion errorFile = [
            SELECT VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :result.errorFileDocumentId AND IsLatest = TRUE
        ];
        List<String> lines = errorFile.VersionData.toString().split('\n');
        Assert.areEqual(12, lines.size(), 'Header plus one line per skipped row.');
        Assert.areEqual('Row,' + headerRow().trim() + ',Error', lines[0]);
        Assert.isTrue(lines[3].startsWith('4,-,'));
        Assert.isTrue(lines[3].contains('NO-SUCH-ZONE'));
        Assert.isTrue(lines[3].endsWith('No Zone territory found for NO-SUCH-ZONE.'));
    }

    @IsTest
    static void processUpload_reusesErrorFileAcrossRuns() {
        DistrictZoneAlignmentService.ProcessResult first = DistrictZoneAlignmentController.processUpload(
            insertCsv(headerRow() + csvRow('-', '', '', '', ZONE_BY_REGION))
        );

        Test.startTest();
        DistrictZoneAlignmentService.ProcessResult second = DistrictZoneAlignmentController.processUpload(
            insertCsv(headerRow() + csvRow(DISTRICT_TWO, DISTRICT_TWO, '', '', ZONE_BY_REGION))
        );
        Test.stopTest();

        Assert.areEqual(first.errorFileDocumentId, second.errorFileDocumentId);
        Assert.areEqual(2, [SELECT COUNT() FROM ContentVersion WHERE ContentDocumentId = :second.errorFileDocumentId]);
        Assert.areEqual(
            DistrictZoneAlignmentService.DOWNLOAD_URL_PREFIX + second.errorFileDocumentId,
            DistrictZoneAlignmentController.getErrorFileDownloadUrl()
        );
        FieldServiceBackofficeConfig__c userConfig = FieldServiceBackofficeConfig__c.getValues(UserInfo.getUserId());
        Assert.areEqual(String.valueOf(second.errorFileDocumentId), userConfig.DistrictZoneAlignmentErrorFileId__c);
    }

    @IsTest
    static void getErrorFileDownloadUrl_throwsBeforeFirstUpload() {
        AuraHandledException thrown;
        try {
            DistrictZoneAlignmentController.getErrorFileDownloadUrl();
        } catch (AuraHandledException e) {
            thrown = e;
        }
        Assert.isNotNull(thrown);
        Assert.isTrue(thrown.getMessage().contains('No error file yet'));
    }

    @IsTest
    static void processUpload_throwsWhenFileMissingOrColumnsMissing() {
        AuraHandledException thrown;
        try {
            DistrictZoneAlignmentController.processUpload(null);
        } catch (AuraHandledException e) {
            thrown = e;
        }
        Assert.isNotNull(thrown);
        Assert.isTrue(thrown.getMessage().contains('Upload a file'));

        thrown = null;
        try {
            DistrictZoneAlignmentController.processUpload(insertCsv('Current District #,Future District #\nA,B\n'));
        } catch (AuraHandledException e) {
            thrown = e;
        }
        Assert.isNotNull(thrown);
        Assert.isTrue(thrown.getMessage().contains('Future ASM Names'));
    }

    @IsTest
    static void getTemplateDownloadUrl_storesAndReusesDocument() {
        Test.startTest();
        String firstUrl = DistrictZoneAlignmentController.getTemplateDownloadUrl();
        String secondUrl = DistrictZoneAlignmentController.getTemplateDownloadUrl();
        Test.stopTest();

        Assert.isTrue(firstUrl.startsWith(DistrictZoneAlignmentService.DOWNLOAD_URL_PREFIX));
        Assert.areEqual(firstUrl, secondUrl);
        Id documentId = Id.valueOf(firstUrl.substringAfterLast('/'));
        FieldServiceBackofficeConfig__c config = FieldServiceBackofficeConfig__c.getOrgDefaults();
        Assert.areEqual(String.valueOf(documentId), config.DistrictZoneAlignmentTemplateId__c);
        ContentVersion template = [SELECT VersionData FROM ContentVersion WHERE ContentDocumentId = :documentId];
        Assert.isTrue(template.VersionData.toString().startsWith('Current District #,Current District Name'));
    }

    @IsTest
    static void controller_wrapsUnexpectedErrors() {
        DistrictZoneAlignmentController.throwTestException = true;
        List<String> messages = new List<String>();
        try {
            DistrictZoneAlignmentController.getTemplateDownloadUrl();
        } catch (AuraHandledException e) {
            messages.add(e.getMessage());
        }
        try {
            DistrictZoneAlignmentController.getErrorFileDownloadUrl();
        } catch (AuraHandledException e) {
            messages.add(e.getMessage());
        }
        try {
            DistrictZoneAlignmentController.processUpload(UserInfo.getUserId());
        } catch (AuraHandledException e) {
            messages.add(e.getMessage());
        }
        Assert.areEqual(3, messages.size());
        Assert.isTrue(containsMessage(messages, 'Unable to resolve the District Zone Alignment template'));
        Assert.isTrue(containsMessage(messages, 'Unable to resolve the District Zone Alignment error file'));
        Assert.isTrue(containsMessage(messages, 'Unable to process'));
    }

    @IsTest
    static void selectorAndParser_handleBlankInputs() {
        Assert.areEqual(0, DistrictZoneAlignmentSelector.selectTerritoriesByRegionNumbers(new Set<String>()).size());
        Assert.areEqual(0, DistrictZoneAlignmentSelector.selectZonesByRegionNumberOrName(null).size());
        Assert.areEqual(0, DistrictZoneAlignmentSelector.selectActiveUsers(null, new Set<String>()).size());
        Assert.areEqual(0, DistrictZoneAlignmentSelector.selectLatestVersion(null).size());
        Assert.areEqual(0, DistrictZoneAlignmentSelector.selectDocumentsById(null).size());
        Assert.areEqual(0, DistrictZoneAlignmentSelector.selectDocumentsByTitle(null).size());
        Assert.areEqual(0, DistrictZoneAlignmentSelector.selectTemplateResource(null).size());
        Assert.areEqual('', BackofficeUploadFileParser.csvEscape(null));
        Assert.areEqual('"a,""b"""', BackofficeUploadFileParser.csvEscape('a,"b"'));
        Assert.areEqual('futureasmnames', BackofficeUploadFileParser.normalizeHeader('Future ASM Names'));
    }

    private static User asmUser(String firstName, String suffix) {
        String unique = String.valueOf(Math.abs(Crypto.getRandomInteger())) + suffix;
        String username = 'gw2706.' + unique + '@example.invalid';
        return new User(
            FirstName = firstName,
            LastName = 'Twosevenzerosix',
            Alias = ('g' + unique).left(8),
            Email = username,
            Username = username,
            CommunityNickname = ('gw2706' + unique).left(40),
            ProfileId = UserInfo.getProfileId(),
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }

    private static Id asmUserId() {
        return [SELECT Id FROM User WHERE Name = :ASM_NAME AND IsActive = TRUE LIMIT 1].Id;
    }

    private static ServiceTerritory zone(String name, String regionNumber, Id operatingHoursId) {
        return new ServiceTerritory(
            Name = name,
            RegionNumber__c = regionNumber,
            TerritoryType__c = 'Zone',
            OperatingHoursId = operatingHoursId,
            IsActive = true
        );
    }

    private static String headerRow() {
        return 'Current District #,Current District Name,Current Zone #,Current Zone Name,' +
            'Future District #,Future ASM Names,Future District Name,Future Zone #,Zone Name\n';
    }

    /**
     * @description One template row; the reference columns (current names/zone, zone name) are filled with
     *              "-" for new districts and placeholder text otherwise, as in the business template.
     */
    private static String csvRow(
        String currentDistrict,
        String futureDistrict,
        String futureAsm,
        String futureDistrictName,
        String futureZone
    ) {
        String reference = currentDistrict == '-' ? '-' : 'Ref';
        return String.join(
            new List<String>{
                currentDistrict,
                reference,
                reference,
                reference,
                futureDistrict,
                futureAsm,
                futureDistrictName,
                futureZone,
                'Zone Ref'
            },
            ','
        ) + '\n';
    }

    private static Id insertCsv(String csvBody) {
        ContentVersion version = new ContentVersion(
            Title = 'GW2706 Upload',
            PathOnClient = 'gw2706.csv',
            VersionData = Blob.valueOf(csvBody),
            IsMajorVersion = true
        );
        insert version;
        return [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
        ].ContentDocumentId;
    }

    private static Boolean containsMessage(List<String> messages, String fragment) {
        if (messages == null) {
            return false;
        }
        for (String message : messages) {
            if (message != null && message.contains(fragment)) {
                return true;
            }
        }
        return false;
    }
}