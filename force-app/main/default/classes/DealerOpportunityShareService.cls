/**
* @author PWC Developer
* @date 2026/11/02
*
* @group Dealer Portal
*
* @description
* Dealer Portal R1 - Assigns the STERIS Dealer Manager as owner and shares the opportunity
* back to the dealer who created it and to that dealer organisation's partner roles.
* Without sharing is required because the portal user cannot read Account Team or reassign ownership.
* SOQL and DML use SYSTEM_MODE so that system context stays explicit. It matches this class:
* sharing is already bypassed, and object and field permissions stay ignored.
*/
public without sharing class DealerOpportunityShareService {
    
    /**
* @description
* Dealer Portal R1 - Reads the dealer account name for the stamped display field.
*
* @param accountId Dealer Partner Account.
* @return Account name, or null when the account does not exist.
*/
    public static String selectAccountName(Id accountId) {
        if (accountId == null) {
            return null;
        }
        List<Account> accounts = [
            SELECT Name
            FROM Account
            WHERE Id = :accountId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return accounts.isEmpty() ? null : accounts[0].Name;
    }
    
    /**
* @description
* Dealer Portal R1 - Moves ownership to the primary Dealer Manager and restores Edit access
* for the submitting dealer user and the dealer organisation.
*
* @param opportunityId Opportunity that was just created.
* @param submitterId User who created the opportunity.
*/
    public static void assignOwnerAndShare(Id opportunityId, Id submitterId) {
        if (opportunityId == null) {
            return;
        }
        
        Opportunity opportunityRecord = [
            SELECT Id, AccountId, OwnerId
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        
        Id managerId = resolveManagerId(opportunityRecord.AccountId);
        if (managerId != null && managerId != opportunityRecord.OwnerId) {
            Database.update(
                new Opportunity(
                    Id = opportunityRecord.Id,
                    OwnerId = managerId
                ),
                AccessLevel.SYSTEM_MODE
            );
            opportunityRecord.OwnerId = managerId;
        }
        
        List<OpportunityShare> shares = new List<OpportunityShare>();
        if (submitterId != null && submitterId != opportunityRecord.OwnerId) {
            shares.add(buildShare(opportunityRecord.Id, submitterId));
        }
        shares.addAll(buildPartnerShares(opportunityRecord.Id, opportunityRecord.AccountId, opportunityRecord.OwnerId));
        if (!shares.isEmpty()) {
            Database.insert(shares, false, AccessLevel.SYSTEM_MODE);
        }
    }
    
    private static Id resolveManagerId(Id accountId) {
        if (accountId == null) {
            return null;
        }
        
        List<AccountTeamMember> teamMembers = [
            SELECT UserId, TeamMemberRole, User.UserType
            FROM AccountTeamMember
            WHERE AccountId = :accountId
            AND User.IsActive = true
            AND User.UserType = 'Standard'
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
        ];
        
        Id fallbackId;
        for (AccountTeamMember teamMember : teamMembers) {
            String roleName = teamMember.TeamMemberRole == null
                ? ''
                : teamMember.TeamMemberRole.toLowerCase();
            if (roleName.contains('dealer manager')) {
                return teamMember.UserId;
            }
            if (fallbackId == null) {
                fallbackId = teamMember.UserId;
            }
        }
        return fallbackId;
    }
    
    private static List<OpportunityShare> buildPartnerShares(Id opportunityId, Id accountId, Id ownerId) {
        List<OpportunityShare> shares = new List<OpportunityShare>();
        if (accountId == null) {
            return shares;
        }
        
        Set<Id> roleIds = new Map<Id, UserRole>([
            SELECT Id
            FROM UserRole
            WHERE PortalAccountId = :accountId
            WITH SYSTEM_MODE
        ]).keySet();
        if (roleIds.isEmpty()) {
            return shares;
        }
        
        for (Group roleGroup : [
            SELECT Id
            FROM Group
            WHERE Type = 'Role'
            AND RelatedId IN :roleIds
            WITH SYSTEM_MODE
        ]) {
            if (roleGroup.Id != ownerId) {
                shares.add(buildShare(opportunityId, roleGroup.Id));
            }
        }
        return shares;
    }
    
    private static OpportunityShare buildShare(Id opportunityId, Id userOrGroupId) {
        OpportunityShare shareRecord = new OpportunityShare();
        shareRecord.OpportunityId = opportunityId;
        shareRecord.UserOrGroupId = userOrGroupId;
        shareRecord.OpportunityAccessLevel = 'Edit';
        shareRecord.RowCause = Schema.OpportunityShare.RowCause.Manual;
        return shareRecord;
    }
}