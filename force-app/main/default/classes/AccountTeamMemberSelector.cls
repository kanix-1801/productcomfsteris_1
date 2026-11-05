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
    }