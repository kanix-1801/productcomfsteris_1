/**
    * @author Divya Sree
    * @date 2026/05/25
    *
    * @group Account Management, Overlay Assignment
    *
    * @description
    * Selector layer for AccountTeamMember queries.
    */
    public with sharing class AccountTeamMemberSelector {
        /**
    * @description
    * Selects Account Team Members by Account Id.
    *
    * @param accountId Account Id.
    * @return List<AccountTeamMember>
    */
    // GC-3099 - Jun12 modified selectByAccountId method
    public static List<AccountTeamMember> selectByAccountId(Id accountId, Boolean includeAccessFields) {
            
            String queryString =
                'SELECT Id, User.Name, User.Email, User.Phone, User.Title, TeamMemberRole, SalesCategoryDescription__c,ExpiryDate__c,AssignmentType__c,TerritoryCode__c,SalesCategoryCode__c';//GC-3352

            if (includeAccessFields) {
                queryString +=
                    ', AccountAccessLevel, CaseAccessLevel, ContactAccessLevel, OpportunityAccessLevel';
            }

            queryString +=
                ' FROM AccountTeamMember' +
                ' WHERE AccountId = :accountId' +
                ' WITH USER_MODE' +
                ' ORDER BY User.Name';

            return Database.query(queryString);
        }

        /**
         * @description GCL-2 - Selects Account Team Members for the Life Sciences
         *              Coverage Panel. Returns TAS-assigned core territory reps and
         *              Salesforce-managed overlay users. GCL-326 selects TerritoryCode__c
         *              for the Territory Number column. That value is stored from
         *              OrderLineContact.TerritoryNumber__c. Email, phone, and sales
         *              category code are excluded from the panel.
         * @param accountId Account Id.
         * @return List<AccountTeamMember> ordered by User.Name.
         */
        public static List<AccountTeamMember> selectByAccountIdForLifeSciences(Id accountId) {
            if (accountId == null) {
                return new List<AccountTeamMember>();
            }

            return [
                SELECT Id,
                       UserId,
                       User.Name,
                       TeamMemberRole,
                       AssignmentType__c,
                       TerritoryCode__c,
                       SalesCategoryDescription__c
                FROM AccountTeamMember
                WHERE AccountId = :accountId
                WITH USER_MODE
                ORDER BY User.Name
            ];
        }

        /**
         * @description GCL-117 - Reads the Account Owner and class code used by the
         *              Life Sciences Coverage Panel. Healthcare rows are ignored by
         *              the caller when Customer Class Code is not SC.
         * @param accountId Account Id.
         * @return Account with Owner fields, or null when the user cannot read it.
         */
        public static Account selectOwnerForCoveragePanel(Id accountId) {
            if (accountId == null) {
                return null;
            }

            List<Account> accounts = [
                SELECT Id,
                       OwnerId,
                       Owner.Name,
                       CustomerClassCode__c
                FROM Account
                WHERE Id = :accountId
                WITH USER_MODE
                LIMIT 1
            ];
            return accounts.isEmpty() ? null : accounts[0];
        }
        
        /**
    * @description
    * GC-3088 - Selects existing Account Team Members for duplicate prevention.
    * GC-3179 - Modified: WITH USER_MODE replaces WITH SECURITY_ENFORCED for user-mode access.
    * 
    * @param accountIdSet Account IDs.
    * @param userIdSet User IDs.
    * @return Existing Account Team Members.
    * 
    * @example
    * AccountTeamMemberSelector.selectByAccountsAndUsers(accountIdSet, userIdSet);
    */
        public static List<AccountTeamMember> selectByAccountsAndUsers(Set<Id> accountIdSet, Set<Id> userIdSet) {
            if (accountIdSet == null || accountIdSet.isEmpty() || userIdSet == null || userIdSet.isEmpty()) {
                return new List<AccountTeamMember>();
            }
            
            return [
                SELECT AccountId,
                UserId
                FROM AccountTeamMember
                WHERE AccountId IN :accountIdSet
                AND UserId IN :userIdSet
                WITH USER_MODE
            ];
        }

        /**@author: Suraj Thapliyal
         * @description GC-2580 Selects Account Team Members by User Id, including access level fields.
         *              GC-3352 - Also selects TerritoryCode__c, SalesCategoryCode__c, and SalesCategoryDescription__c.
         * @param userIds User Ids to query.
         * @return AccountTeamMember rows for the given users.
         */
        public static List<AccountTeamMember> selectByUserIds(Set<Id> userIds) {
            if (userIds == null || userIds.isEmpty()) {
                return new List<AccountTeamMember>();
            }

            return [
                SELECT Id, AccountId, UserId, TeamMemberRole,
                    AccountAccessLevel, OpportunityAccessLevel, CaseAccessLevel,
                    TerritoryCode__c, SalesCategoryCode__c, SalesCategoryDescription__c
                FROM AccountTeamMember
                WHERE UserId IN :userIds
                WITH USER_MODE
            ];
        }

        /**@author: Suraj Thapliyal 
         * @description GC-2580 Selects Account Team Members by account, user, and role.
         * @param accountIdSet Account Ids.
         * @param userIdSet User Ids.
         * @param teamMemberRole Team member role to match.
         * @return Matching AccountTeamMember rows.
         */
        public static List<AccountTeamMember> selectByAccountsUsersAndRole(
            Set<Id> accountIdSet,
            Set<Id> userIdSet,
            String teamMemberRole
        ) {
            if (accountIdSet == null || accountIdSet.isEmpty()
                || userIdSet == null || userIdSet.isEmpty()
                || String.isBlank(teamMemberRole)) {
                return new List<AccountTeamMember>();
            }

            return [
                SELECT Id, AccountId, UserId
                FROM AccountTeamMember
                WHERE AccountId IN :accountIdSet
                AND UserId IN :userIdSet
                AND TeamMemberRole = :teamMemberRole
                WITH USER_MODE
            ];
        }

        /**
         * @description GC-2580 Selects Account Team Members by account, user, role, assignment type, and expiry date.
         * @param accountIdSet Account Ids.
         * @param userIdSet User Ids.
         * @param teamMemberRole Team member role to match.
         * @param assignmentType AssignmentType__c value to match.
         * @param expiryDate ExpiryDate__c value to match.
         * @return Matching AccountTeamMember rows.
         */
        public static List<AccountTeamMember> selectByAccountsUsersRoleAssignmentType(
            Set<Id> accountIdSet,
            Set<Id> userIdSet,
            String teamMemberRole,
            String assignmentType
           
        ) {
            if (accountIdSet == null || accountIdSet.isEmpty()
                || userIdSet == null || userIdSet.isEmpty()
                || String.isBlank(teamMemberRole)
                || String.isBlank(assignmentType)) {

                return new List<AccountTeamMember>();
            }

            return [
                SELECT Id, AccountId, UserId, TeamMemberRole, AssignmentType__c
                FROM AccountTeamMember
                WHERE AccountId IN :accountIdSet
                AND UserId IN :userIdSet
                AND TeamMemberRole = :teamMemberRole
                AND AssignmentType__c = :assignmentType
                WITH USER_MODE
            ];
        }

        /**
         * @description GCL-79 - Existing Account Team rows for a Life Sciences overlay submit.
         *              Healthcare team lookups are unchanged.
         * @param accountIds Account Ids receiving the overlay.
         * @param userIds Overlay user Ids.
         * @return Existing AccountId and UserId pairs.
         */
        public static List<AccountTeamMember> selectLifeSciencesByAccountsAndUsers(
            Set<Id> accountIds,
            Set<Id> userIds
        ) {
            if (accountIds == null || accountIds.isEmpty() || userIds == null || userIds.isEmpty()) {
                return new List<AccountTeamMember>();
            }
            return [
                SELECT AccountId, UserId
                FROM AccountTeamMember
                WHERE AccountId IN :accountIds
                AND UserId IN :userIds
            ];
        }

/**
         * @description
         * GCL-100 - Returns the running user's Account Team row for one Account.
         * Life Sciences territory coverage is assigned through the Account Team.
         *
         * @param accountId Account record Id from the record page.
         * @return The current user's team row, or an empty list when they are not a member.
         *
         * @example
         * AccountTeamMemberSelector.selectCurrentUserTeamMember(accountId);
         */
        public static List<AccountTeamMember> selectCurrentUserTeamMember(Id accountId) {
            if (accountId == null) {
                return new List<AccountTeamMember>();
            }

            return [
                SELECT Id
                FROM AccountTeamMember
                WHERE AccountId = :accountId
                AND UserId = :UserInfo.getUserId()
                LIMIT 1
            ];
        }
    }