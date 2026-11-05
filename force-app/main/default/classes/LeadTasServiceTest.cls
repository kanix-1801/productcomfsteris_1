/**
 * @author Abhishek Mishra
 * @date 10-08-2026
 * @description #GC-3279 Test class for Lead TAS assignment (trigger → queueable → integration).
 */
@IsTest
private class LeadTasServiceTest {

    /**
     * @description Creates Healthcare Sales users and assigns Sales Rep plus Lead create/update
     *              permission sets to the running user for Lead TAS tests.
     */
    @testSetup
    static void setupData() {
        Profile healthcareSalesProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Healthcare Sales'
            LIMIT 1
        ];

        Map<String, Id> permissionSetIdsByName = new Map<String, Id>();
        for (PermissionSet permissionSetRecord : [
            SELECT Id, Name
            FROM PermissionSet
            WHERE Name IN (
                'SalesFieldRepAccountManager',
                'LeadCreatePS',
                'LeadUpdatePS'
            )
        ]) {
            permissionSetIdsByName.put(permissionSetRecord.Name, permissionSetRecord.Id);
        }

        Long uniqueSeed = System.currentTimeMillis();
        Id internalRoleId = [
            SELECT Id
            FROM UserRole
            WHERE PortalType = 'None'
            LIMIT 1
        ].Id;

        User runningUser = createUser(
            healthcareSalesProfile.Id,
            'leadtasrun' + uniqueSeed + '@test.com',
            'RUN' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );
        User tasRep = createUser(
            healthcareSalesProfile.Id,
            'leadtasrep' + uniqueSeed + '@test.com',
            'TAS' + uniqueSeed
        );
        runningUser.UserRoleId = internalRoleId;
        tasRep.UserRoleId = internalRoleId;
        insert new List<User>{ runningUser, tasRep };

        System.runAs(runningUser) {
            insert new List<PermissionSetAssignment>{
                new PermissionSetAssignment(
                    AssigneeId = runningUser.Id,
                    PermissionSetId = permissionSetIdsByName.get('SalesFieldRepAccountManager')
                ),
                new PermissionSetAssignment(
                    AssigneeId = runningUser.Id,
                    PermissionSetId = permissionSetIdsByName.get('LeadCreatePS')
                ),
                new PermissionSetAssignment(
                    AssigneeId = runningUser.Id,
                    PermissionSetId = permissionSetIdsByName.get('LeadUpdatePS')
                )
            };
        }
    }

    /**
     * @description Verifies Lead insert enqueues TAS processing and updates Lead Owner
     *              from territory[0] salesRepEmployeeNumber.
     */
    @IsTest
    static void testLeadInsertAssignsOwnerFromTas() {
        User runningUser = [
            SELECT Id
            FROM User
            WHERE Email LIKE 'leadtasrun%'
            LIMIT 1
        ];
        User tasRep = [
            SELECT Id, EmployeeNumber__c
            FROM User
            WHERE Email LIKE 'leadtasrep%'
            LIMIT 1
        ];

        System.runAs(runningUser) {
            Test.startTest();
            Lead leadRecord = buildEligibleLead('OwnerAssign');
            insert leadRecord;
            registerTasMock(
                200,
                'OK',
                buildTasResponseJson(leadRecord.Id, tasRep.EmployeeNumber__c)
            );
            Test.stopTest();

            Lead updatedLead = [SELECT OwnerId FROM Lead WHERE Id = :leadRecord.Id];
            System.assertEquals(
                tasRep.Id,
                updatedLead.OwnerId,
                'Lead owner should be set from territory[0] salesRepEmployeeNumber.'
            );
        }
    }

    /**
     * @description Verifies processLeads assigns Lead Owner when the TAS emp number matches
     *              an active Healthcare Sales user, and covers non-assignment paths.
     */
    @IsTest
    static void testProcessLeadsAssignsOwnerFromMatchedEmp() {
        User runningUser = [
            SELECT Id
            FROM User
            WHERE Email LIKE 'leadtasrun%'
            LIMIT 1
        ];
        User tasRep = [
            SELECT Id, EmployeeNumber__c
            FROM User
            WHERE Email LIKE 'leadtasrep%'
            LIMIT 1
        ];

        System.runAs(runningUser) {
            LeadService.assignTAStoLead(null);
            LeadService.assignTAStoLead(
                new List<Lead>{ new Lead(LastName = 'Skip', Company = 'NoTas') }
            );
            System.assertEquals(0, LeadSelector.selectByIds(null).size());
            System.assertEquals(0, LeadSelector.selectByIds(new Set<Id>()).size());
            new LeadTasQueueable(null).execute(null);
            new LeadTasQueueable(new Set<Id>()).execute(null);

            Automation_Setting_Trigger__c bypassSetting = new Automation_Setting_Trigger__c(
                SetupOwnerId = UserInfo.getUserId(),
                LeadTriggerByPass__c = true
            );
            insert bypassSetting;
            insert buildEligibleLead('BypassLead');
            bypassSetting.LeadTriggerByPass__c = false;
            update bypassSetting;

            Lead leadRecord = buildEligibleLead('ProcessAssign');
            insert leadRecord;
            System.assertEquals(false, TriggerControl.enterAfterInsert(Lead.SObjectType));
            new LeadTriggerHandler().afterInsert();

            List<Lead> leads = LeadSelector.selectByIds(new Set<Id>{ leadRecord.Id });

            Test.startTest();

            // Non-assignment paths
            registerTasMock(500, 'Error', '{"error":"TAS down"}');
            LeadTasIntegrationService.processLeads(null);
            LeadTasIntegrationService.processLeads(leads);

            registerTasMock(
                200,
                'OK',
                '{"leadId":"' + leadRecord.Id + '","territoryData":[]}'
            );
            LeadTasIntegrationService.processLeads(leads);

            registerTasMock(
                200,
                'OK',
                '{"leadId":"' +
                    leadRecord.Id +
                    '","territoryData":[{"classCode":"HC","tasSalesCategory":"GI REPROC","territoryId":"71071","territoryNumber":"G66301","territoryDescription":"CLEVELAND, OH","salesRepEmployeeNumber":"","salesRepName":"Ryan Corabi"}]}'
            );
            LeadTasIntegrationService.processLeads(leads);

            registerTasMock(
                200,
                'OK',
                buildTasResponseJson(leadRecord.Id, 'NO_MATCH_EMP')
            );
            LeadTasIntegrationService.processLeads(leads);

            // Successful assignment
            registerTasMock(
                200,
                'OK',
                buildTasResponseJson(leadRecord.Id, tasRep.EmployeeNumber__c)
            );
            LeadTasIntegrationService.processLeads(leads);

            // Owner already matches
            leads = LeadSelector.selectByIds(new Set<Id>{ leadRecord.Id });
            LeadTasIntegrationService.processLeads(leads);
            LeadTasIntegrationService.logSaveResults(null);

            Test.stopTest();

            Lead updatedLead = [SELECT OwnerId FROM Lead WHERE Id = :leadRecord.Id];
            System.assertEquals(
                tasRep.Id,
                updatedLead.OwnerId,
                'processLeads should assign owner from matched Healthcare Sales emp number.'
            );
        }
    }

    /**
     * @description Builds an eligible Lead with required TAS fields populated.
     * @param lastName Lead last name used to distinguish test records.
     * @return Eligible Lead record.
     */
    private static Lead buildEligibleLead(String lastName) {
        return new Lead(
            FirstName = 'TAS',
            LastName = lastName,
            Company = 'Lead TAS Co',
            Email = lastName + '@tas.example.test',
            Phone = '2165550100',
            Street = '100 Main',
            City = 'Cleveland',
            StateCode = 'OH',
            PostalCode = '44113',
            CountryCode = 'US',
            LeadSource = 'Web',
            Org_ID__c = '82',
            Class_Code__c = 'HC',
            Sales_Category__c = 'SURG SPT'
        );
    }

    /**
     * @description Points SF_PROSPECT_TAS at the test provider and registers the HTTP mock.
     * @param statusCode HTTP status code returned by the mock.
     * @param status HTTP status text returned by the mock.
     * @param body JSON response body returned by the mock.
     */
    private static void registerTasMock(Integer statusCode, String status, String body) {
        AccountProspectTasServiceTest.registerTasServiceSetting();
        Test.setMock(
            HttpCalloutMock.class,
            new SO_HttpMockFactory(statusCode, status, body, new Map<String, String>())
        );
    }

    /**
     * @description Creates a Healthcare Sales User with the given username and employee number.
     * @param profileId Profile Id assigned to the user.
     * @param username Username and email for the user.
     * @param employeeNumber Value stored in EmployeeNumber__c.
     * @return User record prepared for insertion.
     */
    private static User createUser(Id profileId, String username, String employeeNumber) {
        String uniqueSuffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        return new User(
            FirstName = 'Lead',
            LastName = 'Tas',
            Alias = ('l' + uniqueSuffix).left(8),
            Email = username,
            Username = username,
            CommunityNickname = 'leadtas' + uniqueSuffix,
            ProfileId = profileId,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            EmployeeNumber__c = employeeNumber
        );
    }

    /**
     * @description Builds a TAS JSON response with one territory for the given Lead and employee number.
     * @param leadId Lead Id returned in the TAS response payload.
     * @param employeeNumber salesRepEmployeeNumber placed on territoryData[0].
     * @return Serialized TAS response JSON.
     */
    private static String buildTasResponseJson(Id leadId, String employeeNumber) {
        Map<String, Object> response = new Map<String, Object>{
            'leadId' => leadId,
            'territoryData' => new List<Object>{
                new Map<String, Object>{
                    'classCode' => 'HC',
                    'tasSalesCategory' => 'GI REPROC',
                    'territoryId' => '71071',
                    'territoryNumber' => 'G66301',
                    'territoryDescription' => 'CLEVELAND, OH',
                    'salesRepEmployeeNumber' => employeeNumber,
                    'salesRepName' => 'Ryan Corabi'
                }
            }
        };
        return JSON.serialize(response);
    }
}