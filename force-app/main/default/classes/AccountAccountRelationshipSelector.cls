/**
 * @author PWC Developer
 * @date 2026/07/21
 *
 * @group Overlay Assignment
 *
 * @description
 * GC-3180 - SOQL selector for AccountAccountRelationship__c used by Overlay Assignment.
 * GC-3126 - Added selectByChildAccountIds/selectByParentAccountIds for the AccountAccount Relationship tab on Customer 360.
 * GC-3281 - Added InverseRelationshipType__c support now that each relationship is a
 *              single record holding both perspective labels. selectByParentAccountIds
 *              filters on InverseRelationshipType__c (confirmed to hold the Parent's
 *              perspective label, e.g. 'Has IDN Member') to guard against mislabeled
 *              records; selectByChildAccountIds has no filter, since a Customer/Address
 *              account legitimately shows both IDN and GPO relationships together.
 * GC-3213 - IDN/GPO picklist split: RelationshipType__c = Is...Member Of;
 *              InverseRelationshipType__c = Has...Member.
 * GC-2860 - Supports competitive installed base hierarchy resolution.
 */
public with sharing class AccountAccountRelationshipSelector {
    public static final String RELATIONSHIP_TYPE_HAS_GPO_MEMBER = System.Label.AAR_RelationshipType_HasGPOMember;
    public static final String RELATIONSHIP_TYPE_HAS_IDN_MEMBER = System.Label.AAR_RelationshipType_HasIDNMember;
    public static final String RELATIONSHIP_TYPE_IS_IDN_MEMBER_OF = System.Label.AAR_RelationshipType_IsIDNMemberOf;
    public static final String RELATIONSHIP_TYPE_IS_GPO_MEMBER_OF = System.Label.AAR_RelationshipType_IsGPOMemberOf;

    @TestVisible
    private static List<AccountAccountRelationship__c> testAccountAccountRelationships;

    /**
     * @description
     * GC-3180 AC1 / GC-3213 - Returns IDN/GPO affiliations for customer/address accounts.
     *              ParentAccount__c = IDN/GPO (source), ChildAccount__c = Customer/Address (target).
     *              RelationshipType__c = Is IDN/GPO Member Of;
     *              InverseRelationshipType__c = Has IDN/GPO Member.
     *
     * @param accountIds Child address account Ids and/or parent customer account Ids.
     * @return Matching AccountAccountRelationship__c records.
     */
    public static List<AccountAccountRelationship__c> selectGpoIdnAffiliationsByAccountIds(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new List<AccountAccountRelationship__c>();
        }

        if (Test.isRunningTest() && testAccountAccountRelationships != null) {
            return testAccountAccountRelationships;
        }

        // GC-3213 - START
        return [
            SELECT Id,
                   ChildAccount__c,
                   ParentAccount__c,
                   ParentAccount__r.Name,
                   ParentAccount__r.Type,
                   RelationshipType__c,
                   InverseRelationshipType__c,
                   CreatedDate
            FROM AccountAccountRelationship__c
            WHERE ChildAccount__c IN :accountIds
              AND (
                RelationshipType__c = :RELATIONSHIP_TYPE_IS_IDN_MEMBER_OF
                OR RelationshipType__c = :RELATIONSHIP_TYPE_IS_GPO_MEMBER_OF
                OR InverseRelationshipType__c = :RELATIONSHIP_TYPE_HAS_IDN_MEMBER
                OR InverseRelationshipType__c = :RELATIONSHIP_TYPE_HAS_GPO_MEMBER
              )
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC, Id DESC
        ];
        // GC-3213 - END
    }

    /**
     * @description
     * GC-3180 AC2 - Returns member affiliations for selected GPO/IDN parent accounts.
     *              ParentAccount__c = IDN/GPO (source), ChildAccount__c = member Customer/Address (target).
     *
     * @param parentAccountIds Selected GPO/IDN Account Ids from overlay submit.
     * @return Matching AccountAccountRelationship__c records for cascade expansion.
     */
    public static List<AccountAccountRelationship__c> selectMembersByParentIds(Set<Id> parentAccountIds) {
        if (parentAccountIds == null || parentAccountIds.isEmpty()) {
            return new List<AccountAccountRelationship__c>();
        }

        return [
            SELECT Id,
                   ChildAccount__c,
                   ParentAccount__c,
                   RelationshipType__c
            FROM AccountAccountRelationship__c
            WHERE ParentAccount__c IN :parentAccountIds
              AND (RelationshipType__c = :RELATIONSHIP_TYPE_HAS_GPO_MEMBER
                OR RelationshipType__c = :RELATIONSHIP_TYPE_HAS_IDN_MEMBER
                OR RelationshipType__c = :RELATIONSHIP_TYPE_IS_IDN_MEMBER_OF
                OR RelationshipType__c = :RELATIONSHIP_TYPE_IS_GPO_MEMBER_OF)
            WITH SECURITY_ENFORCED
        ];
    }

    /**
     * @description
     * GC-3281 - Returns all AccountAccountRelationship__c records where the given
     *              Account is on the Child side (Customer/Address). No relationship-type
     *              filtering is applied - each relationship is now a single record, with
     *              RelationshipType__c and InverseRelationshipType__c holding the
     *              Parent's and Child's perspective labels respectively.
     *              ChildAccount__c = Customer/Address (this account), ParentAccount__c = IDN/GPO (related).
     *
     * @param accountIdSet Set of Customer/Address Account Ids
     * @return List of matching AccountAccountRelationship__c records
     */
    public static List<AccountAccountRelationship__c> selectByChildAccountIds(Set<Id> accountIdSet) {
        return [
            SELECT Id, Name, ParentAccount__c, ParentAccount__r.Name,
                   ChildAccount__c, RelationshipType__c, InverseRelationshipType__c
            FROM AccountAccountRelationship__c
            WHERE ChildAccount__c IN :accountIdSet
            WITH SECURITY_ENFORCED
        ];
    }

    /**
     * @description
     * GC-3126, GC-3281 - Returns all AccountAccountRelationship__c records where the given
     *              Account is on the Parent side (IDN/GPO). This guards against an IDN
     *              Account ever showing a record mislabeled as a GPO relationship
     *              (or vice versa).
     *              NOTE: InverseRelationshipType__c holds the Parent's-perspective
     *              label ('Has...'); RelationshipType__c holds the Child's-perspective label ('Is...').
     *              ParentAccount__c = IDN/GPO (this account), ChildAccount__c = Customer/Address (related).
     *
     * @param accountIdSet Set of IDN/GPO Account Ids
     * @param expectedRelationshipType RELATIONSHIP_TYPE_HAS_IDN_MEMBER or RELATIONSHIP_TYPE_HAS_GPO_MEMBER,
     *        matching whether the Account being viewed is IDN or GPO
     * @return List of matching AccountAccountRelationship__c records
     */
    public static List<AccountAccountRelationship__c> selectByParentAccountIds(
        Set<Id> accountIdSet,
        String expectedRelationshipType
    ) {
        return [
            SELECT Id, Name, ChildAccount__c, ChildAccount__r.Name,
                   ParentAccount__c, RelationshipType__c, InverseRelationshipType__c
            FROM AccountAccountRelationship__c
            WHERE ParentAccount__c IN :accountIdSet
              AND InverseRelationshipType__c = :expectedRelationshipType
            WITH SECURITY_ENFORCED
        ];
    }
    
    // GC-3213 - START
    /**
     * @description
     * True when AAR is IDN: RelationshipType Is IDN Member Of
     * and/or InverseRelationshipType Has IDN Member.
     *
     * @param relationship AAR record.
     * @return True when the record is IDN-relevant.
     */
    public static Boolean isIdnRelationshipType(AccountAccountRelationship__c relationship) {
        return relationship != null
            && (
                relationship.RelationshipType__c == RELATIONSHIP_TYPE_IS_IDN_MEMBER_OF
                || relationship.InverseRelationshipType__c == RELATIONSHIP_TYPE_HAS_IDN_MEMBER
            );
    }

    /**
     * @description
     * True when AAR is GPO: RelationshipType Is GPO Member Of
     * and/or InverseRelationshipType Has GPO Member.
     *
     * @param relationship AAR record.
     * @return True when the record is GPO-relevant.
     */
    public static Boolean isGpoRelationshipType(AccountAccountRelationship__c relationship) {
        return relationship != null
            && (
                relationship.RelationshipType__c == RELATIONSHIP_TYPE_IS_GPO_MEMBER_OF
                || relationship.InverseRelationshipType__c == RELATIONSHIP_TYPE_HAS_GPO_MEMBER
            );
    }

    /**
     * @description True when AAR is IDN or GPO relevant.
     * @param relationship AAR record.
     * @return True when either type field indicates IDN/GPO.
     */
    public static Boolean isIdnOrGpoRelationshipType(AccountAccountRelationship__c relationship) {
        return isIdnRelationshipType(relationship) || isGpoRelationshipType(relationship);
    }
    // GC-3213 - END

    /**
     * @description GC-2860 Returns affiliations where either side of the relationship matches the given account Ids.
     * @param accountIds Account Ids to match against ParentAccount__c or ChildAccount__c.
     * @return Affiliation rows for hierarchy expansion.
     */
    public static List<AccountAccountRelationship__c> selectAffiliationsByAccountIds(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new List<AccountAccountRelationship__c>();
        }

        return [
            SELECT Id,
                   ParentAccount__c,
                   ChildAccount__c,
                   RelationshipType__c
            FROM AccountAccountRelationship__c
            WHERE ParentAccount__c IN :accountIds
               OR ChildAccount__c IN :accountIds
            WITH USER_MODE
        ];
    }

    /**
     * @description GW-6075 Returns Account Account relationship matches the given account Id.
     * @param quoteAccountId Account Id to match against ChildAccount__c.
     * @return List of Account Account Relationship records
     */
    public static List<AccountAccountRelationship__c> selectAccountRelationships(Id quoteAccountId) {
        if (quoteAccountId == null) {
            return new List<AccountAccountRelationship__c>();
        }

        return (List<AccountAccountRelationship__c>) SoqlQueryBuilder.fromObject('AccountAccountRelationship__c')
                                                                     .selectFields(new List<String>{ 'ParentAccount__c' })
                                                                     .whereEquals('ChildAccount__c', quoteAccountId)
                                                                     .whereField('ParentAccount__c', '!=', null)
                                                                     .execute();
    }
}