@IsTest
private class LSOpportunityNamingServiceTest {

    private static final String NUMBER_VALUE = 'LS-000001';

    @IsTest
    static void buildsNumberAccountNameAndApplications() {
        Assert.areEqual(
            'LS-000001 - Acme Hospital - Washer, Sterilizer',
            LSOpportunityNamingService.buildName(
                NUMBER_VALUE,
                'Acme Hospital',
                'Washer;Sterilizer'
            )
        );
    }

    @IsTest
    static void buildsNumberAndApplicationsWhenAccountIsBlank() {
        Assert.areEqual(
            'LS-000001 - Washer, Sterilizer',
            LSOpportunityNamingService.buildName(NUMBER_VALUE, null, 'Washer;Sterilizer')
        );
        Assert.areEqual(
            'LS-000001 - Washer, Sterilizer',
            LSOpportunityNamingService.buildName(NUMBER_VALUE, '  ', ' Washer ; Sterilizer ')
        );
    }

    @IsTest
    static void returnsNumberWhenAccountAndApplicationAreBlank() {
        Assert.areEqual(
            NUMBER_VALUE,
            LSOpportunityNamingService.buildName(NUMBER_VALUE, null, null)
        );
        Assert.areEqual(
            NUMBER_VALUE,
            LSOpportunityNamingService.buildName(NUMBER_VALUE, null, ' ; ')
        );
    }

    @IsTest
    static void omitsEntireApplicationValueThatWouldExceed120Characters() {
        String first = 'B'.repeat(90);
        String omitted = 'C'.repeat(20);

        String result = LSOpportunityNamingService.buildName(
            NUMBER_VALUE,
            'Acme',
            first + ';' + omitted
        );

        Assert.areEqual('LS-000001 - Acme - ' + first, result);
        Assert.areEqual(109, result.length());
        Assert.isFalse(result.contains('C'));
        Assert.isFalse(result.endsWith(','));
        Assert.isFalse(result.endsWith(', '));
    }

    @IsTest
    static void shortensAccountNameAndSkipsApplicationsWhenAccountDoesNotFit() {
        String accountName = 'A'.repeat(109);

        String result = LSOpportunityNamingService.buildName(
            NUMBER_VALUE,
            accountName,
            'Washer'
        );

        Assert.areEqual(120, result.length());
        Assert.isTrue(result.startsWith('LS-000001 - A'));
        Assert.isFalse(result.contains('Washer'));
    }

    @IsTest
    static void includesApplicationWhenNameIsExactly120Characters() {
        // LS-000001 -  = 12 characters, so 108 application characters land on 120.
        String exactFit = 'A'.repeat(108);

        String result = LSOpportunityNamingService.buildName(
            NUMBER_VALUE,
            null,
            exactFit
        );

        Assert.areEqual(120, result.length());
        Assert.isTrue(result.endsWith(exactFit));
    }

    @IsTest
    static void assignsOneSequenceOnlyToTheTwoLsRecordTypes() {
        Account account = new Account(Name = 'Acme Hospital');
        insert account;

        Id inScopeRecordTypeId = Id.valueOf('012000000000001AAA');
        Id outOfScopeRecordTypeId = Id.valueOf('012000000000002AAA');
        LSOpportunityNamingService.inScopeRecordTypeIds =
            new Set<Id>{ inScopeRecordTypeId };

        Opportunity scoped = new Opportunity(
            RecordTypeId = inScopeRecordTypeId,
            AccountId = account.Id,
            Name = 'Free text',
            StageName = 'Prospecting',
            Application__c = 'Washer;Sterilizer'
        );
        Opportunity other = new Opportunity(
            RecordTypeId = outOfScopeRecordTypeId,
            AccountId = account.Id,
            Name = 'Keep me',
            StageName = 'Prospecting',
            Application__c = 'Washer'
        );

        LSOpportunityNamingService.applyNames(
            new List<Opportunity>{ scoped, other }
        );

        Assert.areEqual(1, scoped.LSOpportunityNumber__c);
        Assert.areEqual(
            'LS-00001 - Acme Hospital - Washer, Sterilizer',
            scoped.Name
        );
        Assert.areEqual('Keep me', other.Name);
        Assert.isNull(other.LSOpportunityNumber__c);

        scoped.Application__c = 'Washer';
        LSOpportunityNamingService.applyNames(
            new List<Opportunity>{ scoped }
        );

        Assert.areEqual(
            1,
            scoped.LSOpportunityNumber__c,
            'A later save must reuse the same sequence.'
        );
        Assert.areEqual('LS-00001 - Acme Hospital - Washer', scoped.Name);
    }

    @IsTest
    static void assignsConsecutiveNumbersInOneSave() {
        Id inScopeRecordTypeId = Id.valueOf('012000000000001AAA');
        LSOpportunityNamingService.inScopeRecordTypeIds =
            new Set<Id>{ inScopeRecordTypeId };

        Opportunity first = new Opportunity(
            RecordTypeId = inScopeRecordTypeId,
            Name = 'First',
            StageName = 'Prospecting'
        );
        Opportunity second = new Opportunity(
            RecordTypeId = inScopeRecordTypeId,
            Name = 'Second',
            StageName = 'Prospecting'
        );

        LSOpportunityNamingService.applyNames(
            new List<Opportunity>{ first, second }
        );

        Assert.areEqual(1, first.LSOpportunityNumber__c);
        Assert.areEqual(2, second.LSOpportunityNumber__c);
        Assert.areEqual('LS-00001', first.Name);
        Assert.areEqual('LS-00002', second.Name);
    }

    @IsTest
    static void namesAClosedOpportunityOnCreateButNotOnUpdate() {
        Id inScopeRecordTypeId = Id.valueOf('012000000000001AAA');
        LSOpportunityNamingService.inScopeRecordTypeIds =
            new Set<Id>{ inScopeRecordTypeId };

        Opportunity createdClosed = new Opportunity(
            RecordTypeId = inScopeRecordTypeId,
            Name = 'Free text',
            StageName = 'Closed Won',
            Application__c = 'Washer'
        );
        LSOpportunityNamingService.applyNames(
            new List<Opportunity>{ createdClosed }
        );
        Assert.areEqual(1, createdClosed.LSOpportunityNumber__c);
        Assert.areEqual('LS-00001 - Washer', createdClosed.Name);

        Opportunity editedClosed = new Opportunity(
            Id = Id.valueOf('006000000000009AAA'),
            RecordTypeId = inScopeRecordTypeId,
            Name = 'Leave this name',
            StageName = 'Closed Lost',
            Application__c = 'Washer'
        );
        LSOpportunityNamingService.applyNames(
            new List<Opportunity>{ editedClosed }
        );
        Assert.areEqual('Leave this name', editedClosed.Name);
        Assert.isNull(editedClosed.LSOpportunityNumber__c);
    }

    @IsTest
    static void handlesNullInputs() {
        LSOpportunityNamingService.applyNames(null);
        Assert.areEqual('', LSOpportunityNamingService.buildName(null, null, null));
    }

    // ------------------------------------------------------------------
    // End to end. These depend on org record types, required fields, and
    // Application__c picklist values.
    // ------------------------------------------------------------------

    private static Id recordTypeId(String developerName) {
        Schema.RecordTypeInfo info = Opportunity.SObjectType.getDescribe()
            .getRecordTypeInfosByDeveloperName()
            .get(developerName);
        return info == null ? null : info.getRecordTypeId();
    }

    private static List<String> applicationValues(Integer howMany) {
        List<String> values = new List<String>();
        for (
            Schema.PicklistEntry entry :
            Opportunity.Application__c.getDescribe().getPicklistValues()
        ) {
            if (entry.isActive() && values.size() < howMany) {
                values.add(entry.getValue());
            }
        }
        return values;
    }

    @IsTest
    static void generatesNameOnInsertForConsumables() {
        if (recordTypeId('LSSalesConsumables') == null) {
            return;
        }

        Account account = new Account(Name = 'LS Naming Account');
        insert account;
        Contact contact = new Contact(LastName = 'LS Naming Contact');
        insert contact;

        List<String> applications = applicationValues(2);
        Opportunity opp = new Opportunity(
            Name = 'Free text typed by the user',
            StageName = 'Discovery',
            PositionInFunnel__c = 'Above Funnel',
            CloseDate = Date.today().addDays(30),
            RecordTypeId = recordTypeId('LSSalesConsumables'),
            AccountId = account.Id,
            PrimaryContact__c = contact.Id,
            Application__c = applications.isEmpty()
                ? null
                : String.join(applications, ';')
        );

        Test.startTest();
        Database.insert(opp, AccessLevel.SYSTEM_MODE);
        Test.stopTest();

        Opportunity saved = (Opportunity) Database.queryWithBinds(
            'SELECT Id, Name, LSOpportunityNumber__c, Application__c ' +
            'FROM Opportunity WHERE Id = :oppId',
            new Map<String, Object>{ 'oppId' => opp.Id },
            AccessLevel.SYSTEM_MODE
        )[0];

        Assert.isNotNull(saved.LSOpportunityNumber__c);
        Assert.areEqual(
            LSOpportunityNamingService.buildName(
                LSOpportunityNamingService.formatNumber(saved.LSOpportunityNumber__c),
                account.Name,
                saved.Application__c
            ),
            saved.Name
        );
        Assert.isTrue(saved.Name.length() <= 120);
    }
}