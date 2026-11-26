/*****************************************************************************
 * Class Name       : GeneralUtilityTest
 * Author           : Sarthak Pani
 * Date of Dev      : 18th November 2026
 * Last Modified Date   : 25th November 2026
 * Description          : Tests for GeneralUtility business line resolution.
*****************************************************************************/
@IsTest(SeeAllData=false)
private class GeneralUtilityTest {
    private static final String HC_USER = 'GU HC User';
    private static final String LS_USER = 'GU LS User';
    private static final String OTHER = 'Other';

    @TestSetup
    static void setupUsers() {
        Id profileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id;
        User hcUser = buildUser(profileId, HC_USER);
        User lsUser = buildUser(profileId, LS_USER);
        insert new List<User>{ hcUser, lsUser };

        String permissionSetName = 'LSGenUtil' + Math.abs(Crypto.getRandomInteger());
        PermissionSet lsPermissionSet = new PermissionSet(Name = permissionSetName, Label = permissionSetName);
        insert lsPermissionSet;
        insert new PermissionSetAssignment(AssigneeId = lsUser.Id, PermissionSetId = lsPermissionSet.Id);
    }

    @IsTest
    static void constructorLoadsContextForCurrentUser() {
        System.runAs(userByLastName(HC_USER)) {
            new GeneralUtility();
        }

        Assert.areEqual('System Administrator', GeneralUtility.userProfileName);
        Assert.areEqual(GeneralUtility.HC_STR, GeneralUtility.userPermission);
        Assert.isNull(GeneralUtility.appName);
        Assert.areEqual(GeneralUtility.HC_STR, GeneralUtility.currentBusinessLine);
    }

    @IsTest
    static void loadUserPermissionReflectsLifeSciencesPermissionSet() {
        System.runAs(userByLastName(HC_USER)) {
            GeneralUtility.loadUserPermission();
        }
        Assert.areEqual(GeneralUtility.HC_STR, GeneralUtility.userPermission);

        System.runAs(userByLastName(LS_USER)) {
            GeneralUtility.loadUserPermission();
        }
        Assert.areEqual(GeneralUtility.LS_STR, GeneralUtility.userPermission);
    }

    @IsTest
    static void loadCurrentAppNameReturnsLastUsedApp() {
        User hcUser = userByLastName(HC_USER);
        System.runAs(hcUser) {
            GeneralUtility.loadCurrentAppName();
        }
        Assert.isNull(GeneralUtility.appName);

        AppDefinition app = [SELECT DurableId, DeveloperName FROM AppDefinition LIMIT 1];
        insert new UserAppInfo(UserId = hcUser.Id, AppDefinitionId = app.DurableId, FormFactor = 'Large');
        System.runAs(hcUser) {
            GeneralUtility.loadCurrentAppName();
        }
        Assert.areEqual(app.DeveloperName, GeneralUtility.appName);
    }

    @IsTest
    static void loadCurrentBusinessLineAppliesEveryRule() {
        String hc = GeneralUtility.HC_STR;
        String ls = GeneralUtility.LS_STR;

        Assert.areEqual(hc, resolve(GeneralUtility.HEALTHCARE_SALES_PROFILE_NAME, null, ls), 'HC sales profile');
        Assert.areEqual(hc, resolve(GeneralUtility.HEALTHCARE_DEALER_PROFILE_NAME, null, ls), 'HC dealer profile');
        Assert.areEqual(hc, resolve(OTHER, GeneralUtility.HEALTHCARE_SALES_APP_NAME, ls), 'HC app');
        Assert.areEqual(hc, resolve(OTHER, null, hc), 'HC permission');
        Assert.areEqual(ls, resolve(GeneralUtility.LIFESCIENCES_SALES_PROFILE_NAME, null, ''), 'LS profile');
        Assert.areEqual(ls, resolve(OTHER, GeneralUtility.LIFESCIENCES_SALES_APP_NAME, ''), 'LS app');
        Assert.areEqual(ls, resolve(OTHER, null, ls), 'LS permission');
        Assert.areEqual('', resolve(OTHER, null, ''), 'no rule matches');
    }

    @IsTest
    static void getCurrentBusinessLineUsesCacheOrLoadsWhenBlank() {
        GeneralUtility.currentBusinessLine = GeneralUtility.LS_STR;
        Assert.areEqual(GeneralUtility.LS_STR, GeneralUtility.getCurrentBusinessLine());
        Assert.areEqual('', GeneralUtility.userProfileName, 'Cached value must not reload context');

        GeneralUtility.currentBusinessLine = '';
        System.runAs(userByLastName(LS_USER)) {
            Assert.areEqual(GeneralUtility.LS_STR, GeneralUtility.getCurrentBusinessLine());
        }
        Assert.areEqual('System Administrator', GeneralUtility.userProfileName);
    }

    @IsTest
    static void businessLineFromOpportunityUsesRecordTypePrefix() {
        Id accountId = insertAccount();
        Id lsOpportunityId = insertOpportunity(accountId, 'LSSalesConsumables');
        Id hcOpportunityId = insertOpportunity(accountId, 'Healthcare_Sales');

        Assert.areEqual(GeneralUtility.LS_STR, GeneralUtility.getCurrentBusinessLineFromOpportunity(lsOpportunityId));
        Assert.areEqual(
            GeneralUtility.LS_STR,
            GeneralUtility.getCurrentBusinessLineFromOpportunity(hcOpportunityId),
            'Cached value is returned'
        );

        GeneralUtility.currentBusinessLine = '';
        Assert.areEqual(GeneralUtility.HC_STR, GeneralUtility.getCurrentBusinessLineFromOpportunity(hcOpportunityId));
    }

    @IsTest
    static void businessLineFromAccountUsesRecordTypePrefix() {
        Id accountId = insertAccount();

        Assert.areEqual(GeneralUtility.HC_STR, GeneralUtility.getCurrentBusinessLineFromAccount(accountId));

        GeneralUtility.currentBusinessLine = GeneralUtility.LS_STR;
        Assert.areEqual(
            GeneralUtility.LS_STR,
            GeneralUtility.getCurrentBusinessLineFromAccount(accountId),
            'Cached value is returned'
        );
    }

    @IsTest
    static void businessLineFromQuoteUsesRecordTypePrefix() {
        Id opportunityId = insertOpportunity(insertAccount(), 'LSSalesConsumables');
        Id lsQuoteId = insertQuote(opportunityId, 'LSSales');
        Id hcQuoteId = insertQuote(opportunityId, 'HCSales');

        Assert.areEqual(GeneralUtility.LS_STR, GeneralUtility.getCurrentBusinessLineFromQuote(lsQuoteId));
        Assert.areEqual(
            GeneralUtility.LS_STR,
            GeneralUtility.getCurrentBusinessLineFromQuote(hcQuoteId),
            'Cached value is returned'
        );

        GeneralUtility.currentBusinessLine = '';
        Assert.areEqual(GeneralUtility.HC_STR, GeneralUtility.getCurrentBusinessLineFromQuote(hcQuoteId));
    }

    private static String resolve(String profileName, String app, String permission) {
        GeneralUtility.userProfileName = profileName;
        GeneralUtility.appName = app;
        GeneralUtility.userPermission = permission;
        GeneralUtility.currentBusinessLine = '';
        GeneralUtility.loadCurrentBusinessLine();
        return GeneralUtility.currentBusinessLine;
    }

    private static Id recordTypeId(Schema.SObjectType objectType, String developerName) {
        return objectType.getDescribe().getRecordTypeInfosByDeveloperName().get(developerName).getRecordTypeId();
    }

    private static Id insertAccount() {
        Account accountRecord = new Account(
            Name = 'GU Account',
            RecordTypeId = recordTypeId(Account.SObjectType, 'Customer')
        );
        insert accountRecord;
        return accountRecord.Id;
    }

    private static Id insertOpportunity(Id accountId, String recordTypeName) {
        Contact contactRecord = new Contact(LastName = 'GU Contact ' + recordTypeName, AccountId = accountId);
        insert contactRecord;

        Opportunity opportunityRecord = new Opportunity(
            Name = 'GU ' + recordTypeName,
            AccountId = accountId,
            PrimaryContact__c = contactRecord.Id,
            RecordTypeId = recordTypeId(Opportunity.SObjectType, recordTypeName),
            StageName = 'Discovery',
            CloseDate = Date.today().addDays(30),
            Amount = 1000,
            Type = Opportunity.Type.getDescribe().getPicklistValues()[0].getValue(),
            BypassValidations__c = true
        );
        if (recordTypeName.startsWith(GeneralUtility.LS_STR)) {
            opportunityRecord.PositionInFunnel__c = 'Above Funnel';
        }
        insert opportunityRecord;
        return opportunityRecord.Id;
    }

    private static Id insertQuote(Id opportunityId, String recordTypeName) {
        Quote quoteRecord = new Quote(
            Name = 'GU ' + recordTypeName,
            OpportunityId = opportunityId,
            RecordTypeId = recordTypeId(Quote.SObjectType, recordTypeName)
        );
        insert quoteRecord;
        return quoteRecord.Id;
    }

    private static User buildUser(Id profileId, String lastName) {
        String uniqueName = lastName.replace(' ', '') + Math.abs(Crypto.getRandomInteger());
        return new User(
            LastName = lastName,
            Alias = uniqueName.left(8),
            Email = uniqueName + '@test.invalid',
            Username = uniqueName + '@test.invalid',
            ProfileId = profileId,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }

    private static User userByLastName(String lastName) {
        return [SELECT Id FROM User WHERE LastName = :lastName LIMIT 1];
    }
}