/**
 * @author Suraj Thapliyal
 * @date 05-18-2026
 * @description SOQL-only selector for OrderLineContact team access batch processing.
 *              GC-3278 - TAS class rename (formerly OrderLineContactTeamAccessSelector).
 *              This class owns query logic only and does not perform business processing or DML.
 *              Batch query locator returns pending Insert/Delete rows for nightly TAS processing.
 *              GC-3352 - Locator also selects TerritoryNumber__c, TAS_Sales_Category__c, and
 *              SalesCategoryDescription__c so insert can stamp AccountTeamMember coverage fields.
 *              GC-2596 - Delete freeze window logic is in TASFreezeWindowUtil; selector omits Delete Record during active freeze.
 *              Realtime selector methods are commented out — realtime team access disabled (GC-3112).
 *              Batch queries run in system mode (without sharing, no WITH USER_MODE).
 */
public without sharing class TASTeamAccessSelector {

    public static final String DELTA_INSERT_RECORD = 'Insert Record';
    public static final String DELTA_DELETE_RECORD = 'Delete Record';

    private static final List<String> PENDING_DELTA_SCENARIOS = new List<String>{
        DELTA_INSERT_RECORD,
        DELTA_DELETE_RECORD
    };

    /**
     * @description GC-2596 - Resolves delta scenarios for the batch locator; omits Delete Record during an active freeze.
     *              Insert Record rows continue to process while delete processing is paused.
     * @return Pending DeltaScenario__c values for OrderLineContact__c batch query.
     */
    private static List<String> resolveBatchScenarios() {
        List<String> batchScenarios;
        // GC-2596 - Query-only skip: exclude Delete Record while freeze window is active.
        if (TASFreezeWindowUtil.isDeleteFreezeActive()) {
            batchScenarios = new List<String>{ DELTA_INSERT_RECORD };
        } else {
            batchScenarios = new List<String>(PENDING_DELTA_SCENARIOS);
        }
        return batchScenarios;
    }

    /**
     * @description Query locator for pending OrderLineContact__c staging rows.
     *              Used by TASTeamAccessBatch.start().
     *              Designed for high volume processing because Database.QueryLocator allows Salesforce
     *              to page records into execute chunks.
     *              Only rows whose AssignedSalesRep__c user has the Healthcare Sales profile are included.
     *              Active User validation is intentionally handled in the service per execute scope.
     *              Batch locator runs in system mode (class is without sharing; no WITH USER_MODE).
     *              GC-3352 - Includes TAS territory number and sales category fields for AccountTeamMember insert.
     * @return Query locator for Insert/Delete rows with HRIS, TAS address, and eligible sales rep populated.
     */
    public static Database.QueryLocator getOrderLineContactsQueryLocator() {
        Id healthcareSalesProfileId = UserSelector.getHealthcareSalesProfileId();
        if (healthcareSalesProfileId == null) {
            throw new TASTeamAccessException(
                'Healthcare Sales profile not found: ' +
                UserSelector.HEALTHCARE_SALES_PROFILE_NAME
            );
        }

        List<String> pendingDeltaScenarios = resolveBatchScenarios(); // GC-2596 - Insert only during active delete freeze

        return Database.getQueryLocator([
            SELECT
                Id,
                HRISSalesRepId__c,
                TASAddressId__c,
                DeltaScenario__c,
                AssignedSalesRep__c,
                AssignedSalesRep__r.ProfileId,
                TerritoryNumber__c,
                TAS_Sales_Category__c,
                SalesCategoryDescription__c
            FROM OrderLineContact__c
            WHERE DeltaScenario__c IN :pendingDeltaScenarios
              AND AssignedSalesRep__c != null
              AND AssignedSalesRep__r.ProfileId = :healthcareSalesProfileId
              AND AssignedSalesRep__r.IsActive = true
              AND HRISSalesRepId__c != null
              AND TASAddressId__c != null
        ]);
    }

    /**
     * @description [GCL-1]: Query locator for pending OrderLineContact__c staging rows for LS.
     *              Used by LS_TASTeamAccessBatch.start().
     *              Designed for high volume processing because Database.QueryLocator allows Salesforce
     *              to page records into execute chunks.
     *              Only rows whose AssignedSalesRep__c user has the Life Sciences Sales profile are included.
     *              Active User validation is intentionally handled in the service per execute scope.
     *              Batch locator runs in system mode (class is without sharing; no WITH USER_MODE).
     *              GC-3352 - Includes TAS territory number and sales category fields for AccountTeamMember insert.
     * @return Query locator for Insert/Delete rows with HRIS, TAS address, and eligible sales rep populated.
     */
    public static Database.QueryLocator getLSOrderLineContactsQueryLocator() {
        Id lifeSciencesSalesProfileId = UserSelector.getLifeSciencesSalesProfileId();
        if (lifeSciencesSalesProfileId == null) {
            throw new TASTeamAccessException(
                'Life Sciences Sales profile not found: ' +
                UserSelector.LIFESCIENCES_SALES_PROFILE_NAME
            );
        }

        List<String> pendingDeltaScenarios = resolveBatchScenarios(); // GC-2596 - Insert only during active delete freeze

        return Database.getQueryLocator([
            SELECT
                Id,
                HRISSalesRepId__c,
                TASAddressId__c,
                DeltaScenario__c,
                AssignedSalesRep__c,
                AssignedSalesRep__r.ProfileId,
                TerritoryNumber__c,
                TAS_Sales_Category__c,
                SalesCategoryDescription__c
            FROM OrderLineContact__c
            WHERE DeltaScenario__c IN :pendingDeltaScenarios
              AND AssignedSalesRep__c != null
              AND AssignedSalesRep__r.ProfileId = :lifeSciencesSalesProfileId
              AND AssignedSalesRep__r.IsActive = true
              AND HRISSalesRepId__c != null
              AND TASAddressId__c != null
        ]);
    }

    /**
     * @description Unused — HRIS user lookup delegated to UserSelector.
     *              Realtime team access disabled (GC-3112).
     * @param employeeNumbers Set of EmployeeNumber__c values from TAS assignment rows.
     * @return Map of EmployeeNumber__c to active User.
     
    public static Map<String, User> selectActiveUsersByEmployeeNumber(Set<String> employeeNumbers) {
        Map<String, User> userByEmployeeNumber = new Map<String, User>();

        if (employeeNumbers == null || employeeNumbers.isEmpty()) {
            return userByEmployeeNumber;
        }

        for (User activeUser : [
            SELECT Id, EmployeeNumber__c
            FROM User
            WHERE EmployeeNumber__c IN :employeeNumbers
              AND IsActive = true
              AND EmployeeNumber__c != null
            WITH USER_MODE
        ]) {
            String employeeNumber = activeUser.EmployeeNumber__c.trim();

            if (!userByEmployeeNumber.containsKey(employeeNumber)) {
                userByEmployeeNumber.put(employeeNumber, activeUser);
            }
        }

        return userByEmployeeNumber;
    }*/

    /**
     * @description Loads Account records by OracleAddressId__c for batch team access processing.
     *              Map key matches OrderLineContact__c.TASAddressId__c.
     *              Duplicate Oracle address ids use first-account-wins map population.
     * @param tasAddressIds TAS address ids from OrderLineContact__c.TASAddressId__c.
     * @return Map of OracleAddressId__c to Account.
     */
    public static Map<String, Account> selectAccountsByOracleAddressId(Set<String> tasAddressIds) {
        Map<String, Account> accountByOracleAddressId = new Map<String, Account>();

        if (tasAddressIds == null || tasAddressIds.isEmpty()) {
            return accountByOracleAddressId;
        }

        for (Account acc : [
            SELECT Id, OracleAddressId__c
            FROM Account
            WHERE OracleAddressId__c IN :tasAddressIds
              AND OracleAddressId__c != null
        ]) {
            if (String.isBlank(acc.OracleAddressId__c)) {
                continue;
            }

            String oracleAddressKey = acc.OracleAddressId__c.trim();

            if (!accountByOracleAddressId.containsKey(oracleAddressKey)) {
                accountByOracleAddressId.put(oracleAddressKey, acc);
            }
        }

        return accountByOracleAddressId;
    }

    /**
     * @description Unused — realtime Address lookup. Realtime team access disabled (GC-3112).
     * @param addressIds External TAS Address Id values from OrderLineContact__c.TASAddressId__c.
     * @return Map of AddressID__c to Address record.
     
    public static Map<String, Schema.Address> selectAddressesByAddressId(Set<String> addressIds) {
        if (addressIds == null || addressIds.isEmpty()) {
            return new Map<String, Schema.Address>();
        }

        Map<String, Schema.Address> addressByExternalId = new Map<String, Schema.Address>();

        for (Schema.Address addr : [
            SELECT Id, AddressID__c, Customer__c
            FROM Address
            WHERE AddressID__c IN :addressIds
              AND Customer__c != NULL
            WITH USER_MODE
        ]) {
            if (String.isBlank(addr.AddressID__c)) {
                continue;
            }

            String addressKey = addr.AddressID__c.trim();

            if (!addressByExternalId.containsKey(addressKey)) {
                addressByExternalId.put(addressKey, addr);
            }
        }

        return addressByExternalId;
    }*/

    /**
     * @description Unused — realtime Opportunity lookup. Realtime team access disabled (GC-3112).
     * @param addressIds External TAS Address Id values from OrderLineContact__c.TASAddressId__c.
     * @return Map of Address.AddressID__c to child Opportunity records.
     
    public static Map<String, List<Opportunity>> opportunitiesByAddressId(Set<String> addressIds) {
        Map<String, List<Opportunity>> resultByAddressId = new Map<String, List<Opportunity>>();

        if (addressIds == null || addressIds.isEmpty()) {
            return resultByAddressId;
        }

        for (SObject row : Database.query(
            'SELECT Id, Address__r.AddressID__c FROM Opportunity' +
            ' WHERE Address__r.AddressID__c IN :addressIds' +
            ' AND Address__r.Customer__c != NULL' +
            ' WITH USER_MODE'
        )) {
            SObject addressRel = row.getSObject('Address__r');

            if (addressRel == null) {
                continue;
            }

            String addressKey = (String) addressRel.get('AddressID__c');

            if (String.isBlank(addressKey)) {
                continue;
            }

            addressKey = addressKey.trim();

            if (!resultByAddressId.containsKey(addressKey)) {
                resultByAddressId.put(addressKey, new List<Opportunity>());
            }

            resultByAddressId.get(addressKey).add((Opportunity) row);
        }

        return resultByAddressId;
    }*/

    /**
     * @description Returns composite keys for existing AccountTeamMember rows.
     *              Used before insert to prevent duplicate Account Team records.
     * @param accountIds Account Ids resolved from Address.Customer__c.
     * @param userIds User Ids resolved from HRIS / EmployeeNumber__c mapping.
     * @return Set of keys in accountId|userId format.
     */
    public static Set<String> selectExistingAccountTeamKeys(Set<Id> accountIds, Set<Id> userIds) {
        Set<String> keys = new Set<String>();

        if (accountIds == null || accountIds.isEmpty() || userIds == null || userIds.isEmpty()) {
            return keys;
        }

        for (AccountTeamMember atm : [
            SELECT AccountId, UserId
            FROM AccountTeamMember
            WHERE AccountId IN :accountIds
              AND UserId IN :userIds
        ]) {
            keys.add(buildAccountTeamKey(atm.AccountId, atm.UserId));
        }

        return keys;
    }

    /**
     * @description Unused — realtime Opportunity Team duplicate check. Realtime disabled (GC-3112).
     * @param opportunityIds Opportunity Ids linked to the TAS Address.
     * @param userIds User Ids resolved from HRIS / EmployeeNumber__c mapping.
     * @return Set of keys in opportunityId|userId format.
     
    public static Set<String> selectExistingOpportunityTeamKeys(Set<Id> opportunityIds, Set<Id> userIds) {
        Set<String> keys = new Set<String>();

        if (opportunityIds == null || opportunityIds.isEmpty() || userIds == null || userIds.isEmpty()) {
            return keys;
        }

        for (OpportunityTeamMember otm :
            OpportunityTeamMemberSelector.selectByOpportunitiesAndUsers(opportunityIds, userIds)
        ) {
            keys.add(buildOpportunityTeamKey(otm.OpportunityId, otm.UserId));
        }

        return keys;
    }*/

    /**
     * @description Queries AccountTeamMember rows eligible for batch TAS delete.
     *              Only rows with the given TeamMemberRole and AssignmentType__c are returned.
     * @param accountIds Account Ids resolved from Account.OracleAddressId__c.
     * @param userIds Assigned sales rep User Ids from staging rows.
     * @param teamMemberRole Team member role to match.
     * @param assignmentType AssignmentType__c value; required for TAS-driven delete safety.
     * @return AccountTeamMember SObjects matching account, user, role, and assignment type.
     */
    public static List<SObject> selectAccountTeamMembersForDelete(
        Set<Id> accountIds,
        Set<Id> userIds,
        String teamMemberRole,
        String assignmentType
    ) {
        List<SObject> records = new List<SObject>();
        if (accountIds == null || accountIds.isEmpty() || userIds == null || userIds.isEmpty()) {
            return records;
        }

        if (String.isBlank(assignmentType)) {
            throw new TASTeamAccessException(
                'AssignmentType__c is required when selecting AccountTeamMember rows for delete'
            );
        }

        records.addAll([
            SELECT Id, AccountId, UserId, TeamMemberRole, AssignmentType__c
            FROM AccountTeamMember
            WHERE AccountId IN :accountIds
              AND UserId IN :userIds
              AND TeamMemberRole = :teamMemberRole
              AND AssignmentType__c = :assignmentType
        ]);
        return records;
    }

    /**
     * @description Unused at runtime — batch is Account Team only. Realtime disabled (GC-3112).
     * @param opportunityIds Opportunity Ids linked to the TAS Address.
     * @param userIds User Ids resolved from HRIS / EmployeeNumber__c mapping.
     * @param teamMemberRole Team member role to match. Expected value is Oracle Assigned.
     * @return OpportunityTeamMember SObjects matching opportunity, user, and role.
     
    public static List<SObject> selectOpportunityTeamMembersForDelete(
        Set<Id> opportunityIds,
        Set<Id> userIds,
        String teamMemberRole
    ) {
        if (opportunityIds == null || opportunityIds.isEmpty() || userIds == null || userIds.isEmpty()) {
            return new List<SObject>();
        }

        List<SObject> records = new List<SObject>();
        records.addAll(
            OpportunityTeamMemberSelector.selectByOpportunitiesUsersAndRole(
                opportunityIds,
                userIds,
                teamMemberRole
            )
        );
        return records;
    }*/

    /**
     * @description Builds the Account Team composite key used for duplicate prevention and safe delete.
     * @param accountId Account Id.
     * @param userId User Id.
     * @return Composite key in accountId|userId format.
     */
    public static String buildAccountTeamKey(Id accountId, Id userId) {
        String accountTeamKey = String.valueOf(accountId) + '|' + String.valueOf(userId);
        return accountTeamKey;
    }

    /**
     * @description Unused — Opportunity Team composite key; batch is Account Team only (GC-3112).
     * @param opportunityId Opportunity Id.
     * @param userId User Id.
     * @return Composite key in opportunityId|userId format.
     
    public static String buildOpportunityTeamKey(Id opportunityId, Id userId) {
        return String.valueOf(opportunityId) + '|' + String.valueOf(userId);
    }*/

    /**
     * @description Unused — scheduler helper. Realtime team access disabled (GC-3112).
     * @param jobName CronJobDetail.Name value to match.
     * @return Matching CronTrigger records.
     
    public static List<CronTrigger> selectCronTriggersByJobName(String jobName) {
        if (String.isBlank(jobName)) {
            return new List<CronTrigger>();
        }

        return [
            SELECT Id, CronExpression, CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name = :jobName
            WITH USER_MODE
        ];
    }*/

    /**
     * @description Indicates whether an OrderLineContact__c row should grant team access.
     * @param deltaScenario OrderLineContact__c.DeltaScenario__c value.
     * @return True when value equals Insert Record.
     */
    public static Boolean isInsertScenario(String deltaScenario) {
        Boolean isInsert = DELTA_INSERT_RECORD == deltaScenario;
        return isInsert;
    }

    /**
     * @description Indicates whether an OrderLineContact__c row should revoke team access.
     * @param deltaScenario OrderLineContact__c.DeltaScenario__c value.
     * @return True when value equals Delete Record.
     */
    public static Boolean isDeleteScenario(String deltaScenario) {
        Boolean isDelete = DELTA_DELETE_RECORD == deltaScenario;
        return isDelete;
    }

    /**
     * @description Unused — realtime OLC lookup. Realtime team access disabled (GC-3112).
     * @param tasAddressIds External Address Id values from Address.AddressID__c.
     * @return Matching OrderLineContact__c assignment rows.
     
    public static List<OrderLineContact__c> selectOrderLineContactsByTasAddressIds(Set<String> tasAddressIds) {
        if (tasAddressIds == null || tasAddressIds.isEmpty()) {
            return new List<OrderLineContact__c>();
        }

        return [
            SELECT Id, HRISSalesRepId__c, TASAddressId__c, DeltaScenario__c
            FROM OrderLineContact__c
            WHERE TASAddressId__c IN :tasAddressIds
              AND HRISSalesRepId__c != null
              AND TASAddressId__c != null
            WITH USER_MODE
        ];
    }*/

    /**
     * @description Unused — realtime Opportunity trigger helper. Realtime disabled (GC-3112).
     * @param opportunityIds Opportunity Ids from trigger context.
     * @return Map of Address.AddressID__c to Opportunity Ids.
     
    public static Map<String, Set<Id>> selectOpportunityIdsByTasAddress(Set<Id> opportunityIds) {
        Map<String, Set<Id>> resultByTasAddress = new Map<String, Set<Id>>();

        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return resultByTasAddress;
        }

        for (SObject row : Database.query(
            'SELECT Id, Address__r.AddressID__c FROM Opportunity' +
            ' WHERE Id IN :opportunityIds' +
            ' AND Address__c != NULL' +
            ' AND Address__r.AddressID__c != NULL' +
            ' WITH USER_MODE'
        )) {
            SObject addressRel = row.getSObject('Address__r');

            if (addressRel == null) {
                continue;
            }

            String tasAddressId = ((String) addressRel.get('AddressID__c'));

            if (String.isBlank(tasAddressId)) {
                continue;
            }

            tasAddressId = tasAddressId.trim();

            if (!resultByTasAddress.containsKey(tasAddressId)) {
                resultByTasAddress.put(tasAddressId, new Set<Id>());
            }

            resultByTasAddress.get(tasAddressId).add((Id) row.get('Id'));
        }

        return resultByTasAddress;
    }*/

    /**
     * @description Unused — realtime Opportunity address-change helper. Realtime disabled (GC-3112).
     * @param oldAddressIdByOpportunityId Map of Opportunity Id to old Address record Id from Trigger.old.
     * @return Map of old Address.AddressID__c to Opportunity Ids.
     
    public static Map<String, Set<Id>> selectTasAddressIdsForAddressRecordIds(
        Map<Id, Id> oldAddressIdByOpportunityId
    ) {
        Map<String, Set<Id>> resultByTasAddress = new Map<String, Set<Id>>();

        if (oldAddressIdByOpportunityId == null || oldAddressIdByOpportunityId.isEmpty()) {
            return resultByTasAddress;
        }

        Set<Id> addressRecordIds = new Set<Id>();

        for (Id addressId : oldAddressIdByOpportunityId.values()) {
            if (addressId != null) {
                addressRecordIds.add(addressId);
            }
        }

        if (addressRecordIds.isEmpty()) {
            return resultByTasAddress;
        }

        Map<Id, String> tasAddressIdByAddressRecordId = new Map<Id, String>();

        for (Schema.Address addr : [
            SELECT Id, AddressID__c
            FROM Address
            WHERE Id IN :addressRecordIds
              AND AddressID__c != null
            WITH USER_MODE
        ]) {
            tasAddressIdByAddressRecordId.put(addr.Id, addr.AddressID__c.trim());
        }

        for (Id opportunityId : oldAddressIdByOpportunityId.keySet()) {
            Id oldAddressRecordId = oldAddressIdByOpportunityId.get(opportunityId);
            String tasAddressId = tasAddressIdByAddressRecordId.get(oldAddressRecordId);

            if (String.isBlank(tasAddressId)) {
                continue;
            }

            if (!resultByTasAddress.containsKey(tasAddressId)) {
                resultByTasAddress.put(tasAddressId, new Set<Id>());
            }

            resultByTasAddress.get(tasAddressId).add(opportunityId);
        }

        return resultByTasAddress;
    }*/

    /**
     * @description Unused — realtime active assignment lookup. Realtime team access disabled (GC-3112).
     * @param tasAddressIds External Address Id values from Address.AddressID__c.
     * @return Active OrderLineContact__c assignment rows where HRIS and TAS Address are populated.
     
    public static List<OrderLineContact__c> selectActiveRealtimeAssignmentsByTasAddressIds(
        Set<String> tasAddressIds
    ) {
        if (tasAddressIds == null || tasAddressIds.isEmpty()) {
            return new List<OrderLineContact__c>();
        }

        return [
            SELECT Id, HRISSalesRepId__c, TASAddressId__c, DeltaScenario__c
            FROM OrderLineContact__c
            WHERE TASAddressId__c IN :tasAddressIds
              AND HRISSalesRepId__c != null
              AND TASAddressId__c != null
              AND DeltaScenario__c != :DELTA_DELETE_RECORD
            WITH USER_MODE
        ];
    }*/

}