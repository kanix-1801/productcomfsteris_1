/**
 * @author Divya Sree
 * @date 2026/05/25
 *
 * @group Account Management
 *
 * @description
 * Data transfer object (DTO) that shapes Account Team Member data for display
 * in the AccountTeamMemberDetails Lightning Web Component. Decouples the UI
 * from the AccountTeamMember sObject by exposing only the fields needed for
 * rendering (name, role, sales category, email, and phone).
 */
public class AccountTeamMemberDTO {
    /** @description GCL-117 display values. These are panel labels only. */
    public static final String LIFE_SCIENCES_OWNER_ROLE = 'Account Owner';
    public static final String LIFE_SCIENCES_OWNER_ASSIGNMENT = 'Manually Assigned';

    /** @description Salesforce Id of the AccountTeamMember record. */
    @AuraEnabled public Id id;

    /** @description GCL-117 - User Id, used when the owner row has no team-member record yet. */
    @AuraEnabled public Id userId;

    /** @description Display name of the team member (from related User.Name). */
    @AuraEnabled public String teamMember;

    /** @description Display Job title of the team member (from related User.JobTitle). */
    @AuraEnabled public String teamJobTitle;

    /** @description Role assigned to the team member on the Account. */
    @AuraEnabled public String teamRole;

    /** @description Sales category description custom field value. */
    @AuraEnabled public String salesCategoryDescription;

    /** @description Email address of the team member (from related User.Email). */
    @AuraEnabled public String email;

    /** @description Phone number of the team member (from related User.Phone). */
    @AuraEnabled public String phone;

    @AuraEnabled public Boolean canViewAccessFields;
    @AuraEnabled public String accountAccess;
    @AuraEnabled public String caseAccess;
    @AuraEnabled public String contactAccess;
    @AuraEnabled public String opportunityAccess;
    /** @description GC-3109 - Expiry date for temporary team member assignments. */
    @AuraEnabled public Date expiryDate;
    /** @description GC-3112 - Assignment type for temporary team member assignments. */
    @AuraEnabled public String assignmentType;
    /** @description GC-3352 - Territory code for the Account Team Member. */
    @AuraEnabled public String territoryCode;
    /** @description GC-3352 - Sales category code for the Account Team Member. */
    @AuraEnabled public String salesCategoryCode;
    /** @description Default constructor used by the Life Sciences factory method. */
    public AccountTeamMemberDTO() {
    }

    /**
     * @description
     * GCL-2 - Maps an AccountTeamMember into the Life Sciences Coverage Panel DTO.
     * GCL-326 - Territory Number is AccountTeamMember.TerritoryCode__c. That value
     * is populated from OrderLineContact.TerritoryNumber__c only.
     * Email, phone, sales category code, job title, and expiry date stay empty
     * because the Life Sciences panel does not display them.
     *
     * @param accountTeamMember AccountTeamMember record with User relationship populated.
     * @return DTO shaped for the Life Sciences panel.
     */
    public static AccountTeamMemberDTO fromLifeSciencesAccountTeamMember(
        AccountTeamMember accountTeamMember
    ) {
        AccountTeamMemberDTO dto = new AccountTeamMemberDTO();
        dto.id = accountTeamMember.Id;
        dto.userId = accountTeamMember.UserId;
        dto.teamMember = accountTeamMember.User.Name;
        dto.teamRole = accountTeamMember.TeamMemberRole;
        dto.assignmentType = accountTeamMember.AssignmentType__c;
        dto.territoryCode = accountTeamMember.TerritoryCode__c;
        dto.salesCategoryDescription = accountTeamMember.SalesCategoryDescription__c;
        dto.canViewAccessFields = false;
        return dto;
    }

    /**
     * @description GCL-117 - Builds the Account Owner display row. This does not
     *              create or change an Account Team Member record.
     * @param accountRecord Account whose Owner is displayed.
     * @return Display row for the Account Owner.
     */
    public static AccountTeamMemberDTO fromAccountOwner(Account accountRecord) {
        AccountTeamMemberDTO dto = new AccountTeamMemberDTO();
        dto.userId = accountRecord.OwnerId;
        dto.teamMember = accountRecord.Owner.Name;
        dto.teamRole = LIFE_SCIENCES_OWNER_ROLE;
        dto.assignmentType = LIFE_SCIENCES_OWNER_ASSIGNMENT;
        dto.canViewAccessFields = false;
        return dto;
    }

    /**
     * @description
     * Maps an AccountTeamMember sObject (including related User fields) into
     * a DTO suitable for Aura/LWC consumption.
     *
     * @param accountTeamMember AccountTeamMember record with User relationship populated.
     */
    public AccountTeamMemberDTO(AccountTeamMember accountTeamMember, Boolean canViewAccessFields) {
        id = accountTeamMember.Id;
        teamMember = accountTeamMember.User.Name;
        teamJobTitle = accountTeamMember.User.Title;
        teamRole = accountTeamMember.TeamMemberRole;
        salesCategoryDescription = accountTeamMember.SalesCategoryDescription__c;
        expiryDate = accountTeamMember.ExpiryDate__c;// GC-3109
        assignmentType = accountTeamMember.AssignmentType__c;// GC-3112
        territoryCode = accountTeamMember.TerritoryCode__c;// GC-3352
        salesCategoryCode = accountTeamMember.SalesCategoryCode__c;// GC-3352
        email = accountTeamMember.User.Email;
        phone = accountTeamMember.User.Phone;
        this.canViewAccessFields = canViewAccessFields;

        if (canViewAccessFields) {
            accountAccess = accountTeamMember.AccountAccessLevel;
            caseAccess = accountTeamMember.CaseAccessLevel;
            contactAccess = accountTeamMember.ContactAccessLevel;
            opportunityAccess = accountTeamMember.OpportunityAccessLevel;
        }

    }
}