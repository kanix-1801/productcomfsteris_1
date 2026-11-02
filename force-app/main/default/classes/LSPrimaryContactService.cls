/**
 * @author Akash Dahinde
 * @date 09-25-2026
 * @story GCL-11
 * @description Keeps Opportunity.PrimaryContact__c and the Primary
 *              OpportunityContactRole synchronized for LSSalesConsumables and
 *              LSEquipmentService Opportunities.
 *
 *              Opportunity.PrimaryContact__c is the source of truth. Creating an
 *              Opportunity creates or promotes its matching contact role. Changing
 *              PrimaryContact__c demotes the previous role and creates or promotes
 *              the new role. A manually inserted or promoted second Primary role is
 *              rejected because IsPrimary is unavailable in validation-rule formulas.
 *
 *              SOQL is delegated to OpportunityContactRoleSelector and
 *              OpportunitySelector. Nebula Logger follows the existing STERIS
 *              service pattern: errors are logged and rethrown, and each public
 *              entry point persists logs in a finally block.
 */
public with sharing class LSPrimaryContactService {

    private static final String CLASS_NAME = 'LSPrimaryContactService';
    public static final String DEFAULT_ROLE = 'Decision Maker';

    public static final Set<String> IN_SCOPE_RECORD_TYPE_DEVELOPER_NAMES =
        new Set<String>{ 'LSSalesConsumables', 'LSEquipmentService' };

    /**
     * Prevents this service's own OCR DML from being rejected by its validation
     * methods. The previous value is always restored in a finally block.
     */
    @TestVisible
    private static Boolean guardsSuspended = false;

    private static Set<Id> inScopeRecordTypeIds;

    @TestVisible
    private static OpportunityContactRoleSelector ocrSelector =
        new OpportunityContactRoleSelector();

    @TestVisible
    private static OpportunitySelector opportunitySelector = new OpportunitySelector();

    /**
     * @description Creates or promotes one Primary contact role from
     *              Opportunity.PrimaryContact__c after Opportunity insert.
     * @param newOpportunities Newly inserted Opportunities from Trigger.new.
     */
    public static void syncRolesOnInsert(List<Opportunity> newOpportunities) {
        try {
            if (newOpportunities == null || newOpportunities.isEmpty()) {
                Logger.debug(CLASS_NAME + '.syncRolesOnInsert: no Opportunities supplied');
                return;
            }

            Map<Id, Id> contactByOpportunityId = new Map<Id, Id>();
            for (Opportunity opp : newOpportunities) {
                if (isInScope(opp) && opp.PrimaryContact__c != null) {
                    contactByOpportunityId.put(opp.Id, opp.PrimaryContact__c);
                }
            }

            Logger.info(
                CLASS_NAME + '.syncRolesOnInsert: eligibleOpportunityCount=' +
                contactByOpportunityId.size()
            );
            applyPrimary(contactByOpportunityId);
        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.syncRolesOnInsert', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Moves the Primary OCR when Opportunity.PrimaryContact__c changes.
     *              The previous OCR remains related to the Opportunity but is demoted.
     * @param newOpportunities Updated Opportunities from Trigger.new.
     * @param oldMap Previous Opportunity values from Trigger.oldMap.
     */
    public static void syncRolesOnUpdate(
        List<Opportunity> newOpportunities,
        Map<Id, Opportunity> oldMap
    ) {
        try {
            if (
                newOpportunities == null ||
                newOpportunities.isEmpty() ||
                oldMap == null ||
                oldMap.isEmpty()
            ) {
                Logger.debug(CLASS_NAME + '.syncRolesOnUpdate: incomplete trigger input');
                return;
            }

            Map<Id, Id> contactByOpportunityId = new Map<Id, Id>();
            for (Opportunity opp : newOpportunities) {
                Opportunity previous = oldMap.get(opp.Id);
                if (
                    isInScope(opp) &&
                    previous != null &&
                    opp.PrimaryContact__c != previous.PrimaryContact__c
                ) {
                    contactByOpportunityId.put(opp.Id, opp.PrimaryContact__c);
                }
            }

            Logger.info(
                CLASS_NAME + '.syncRolesOnUpdate: changedOpportunityCount=' +
                contactByOpportunityId.size()
            );
            applyPrimary(contactByOpportunityId);
        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.syncRolesOnUpdate', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Validates OCR inserts and rejects a new Primary role when the
     *              same in-scope Opportunity already has a Primary role.
     * @param newRoles New OpportunityContactRole records from Trigger.new.
     */
    public static void guardPrimaryOnInsert(List<OpportunityContactRole> newRoles) {
        if (guardsSuspended) {
            return;
        }

        try {
            rejectExtraPrimaries(inScopeRoles(newRoles), null);
        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.guardPrimaryOnInsert', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Validates OCR updates. Rejects promotion of a second Primary
     *              role and prevents users from manually demoting the OCR selected
     *              by Opportunity.PrimaryContact__c.
     * @param newRoles Updated OpportunityContactRole records from Trigger.new.
     * @param oldMap Previous OpportunityContactRole values from Trigger.oldMap.
     */
    public static void guardPrimaryOnUpdate(
        List<OpportunityContactRole> newRoles,
        Map<Id, OpportunityContactRole> oldMap
    ) {
        if (guardsSuspended) {
            return;
        }

        try {
            List<OpportunityContactRole> scopedRoles = inScopeRoles(newRoles);
            if (scopedRoles.isEmpty()) {
                return;
            }

            rejectExtraPrimaries(scopedRoles, oldMap);
            rejectPrimaryRemoval(scopedRoles, oldMap);
        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.guardPrimaryOnUpdate', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Builds OCR DML required to make each Opportunity's selected
     *              Contact its only Primary role.
     * @param contactByOpportunityId Opportunity Id to desired Primary Contact Id.
     *        A null Contact Id demotes the current Primary without creating a role.
     */
    private static void applyPrimary(Map<Id, Id> contactByOpportunityId) {
        if (contactByOpportunityId == null || contactByOpportunityId.isEmpty()) {
            return;
        }

        Map<Id, List<OpportunityContactRole>> rolesByOpportunity =
            groupByOpportunity(
                ocrSelector.selectByOpportunityIds(contactByOpportunityId.keySet())
            );

        List<OpportunityContactRole> demotions = new List<OpportunityContactRole>();
        List<OpportunityContactRole> promotions = new List<OpportunityContactRole>();
        List<OpportunityContactRole> creations = new List<OpportunityContactRole>();

        for (Id opportunityId : contactByOpportunityId.keySet()) {
            Id desiredContactId = contactByOpportunityId.get(opportunityId);
            List<OpportunityContactRole> existingRoles =
                rolesByOpportunity.get(opportunityId);
            if (existingRoles == null) {
                existingRoles = new List<OpportunityContactRole>();
            }

            OpportunityContactRole targetRole;
            for (OpportunityContactRole role : existingRoles) {
                if (desiredContactId != null && role.ContactId == desiredContactId) {
                    targetRole = role;
                } else if (role.IsPrimary) {
                    demotions.add(
                        new OpportunityContactRole(Id = role.Id, IsPrimary = false)
                    );
                }
            }

            if (desiredContactId == null) {
                continue;
            }

            if (targetRole == null) {
                creations.add(new OpportunityContactRole(
                    OpportunityId = opportunityId,
                    ContactId = desiredContactId,
                    Role = DEFAULT_ROLE,
                    IsPrimary = true
                ));
            } else if (!targetRole.IsPrimary) {
                promotions.add(
                    new OpportunityContactRole(Id = targetRole.Id, IsPrimary = true)
                );
            }
        }

        if (demotions.isEmpty() && promotions.isEmpty() && creations.isEmpty()) {
            Logger.debug(CLASS_NAME + '.applyPrimary: no OCR changes required');
            return;
        }

        Logger.info(
            CLASS_NAME + '.applyPrimary: demotions=' + demotions.size() +
            ', promotions=' + promotions.size() +
            ', creations=' + creations.size()
        );

        Boolean previousGuardState = guardsSuspended;
        guardsSuspended = true;
        try {
            if (!demotions.isEmpty()) {
                update demotions;
            }
            if (!promotions.isEmpty()) {
                update promotions;
            }
            if (!creations.isEmpty()) {
                insert creations;
            }
        } finally {
            guardsSuspended = previousGuardState;
        }
    }

    /**
     * @description Detects OCR records newly marked Primary, including multiple
     *              Primary records in the same bulk request, and adds a user-facing
     *              error when another committed Primary role already exists.
     * @param newRoles In-scope OCR records from Trigger.new.
     * @param oldMap Previous values for update, or null for insert.
     */
    private static void rejectExtraPrimaries(
        List<OpportunityContactRole> newRoles,
        Map<Id, OpportunityContactRole> oldMap
    ) {
        if (newRoles == null || newRoles.isEmpty()) {
            return;
        }

        List<OpportunityContactRole> promotedRoles =
            new List<OpportunityContactRole>();
        Set<Id> opportunityIds = new Set<Id>();
        Set<Id> demotedRoleIds = new Set<Id>();

        for (OpportunityContactRole role : newRoles) {
            OpportunityContactRole oldRole =
                oldMap == null ? null : oldMap.get(role.Id);
            Boolean wasPrimary = oldRole != null && oldRole.IsPrimary;

            if (role.Id != null && !role.IsPrimary) {
                demotedRoleIds.add(role.Id);
            }
            if (role.IsPrimary && !wasPrimary) {
                promotedRoles.add(role);
                opportunityIds.add(role.OpportunityId);
            }
        }

        if (promotedRoles.isEmpty()) {
            return;
        }

        Map<Id, OpportunityContactRole> firstPromotionByOpportunity =
            new Map<Id, OpportunityContactRole>();
        for (OpportunityContactRole role : promotedRoles) {
            if (firstPromotionByOpportunity.containsKey(role.OpportunityId)) {
                addMultiplePrimaryError(role);
            } else {
                firstPromotionByOpportunity.put(role.OpportunityId, role);
            }
        }

        Set<Id> opportunitiesWithPrimary = new Set<Id>();
        for (
            OpportunityContactRole role :
            ocrSelector.selectPrimaryByOpportunityIds(opportunityIds)
        ) {
            if (!demotedRoleIds.contains(role.Id)) {
                opportunitiesWithPrimary.add(role.OpportunityId);
            }
        }

        for (Id opportunityId : opportunitiesWithPrimary) {
            OpportunityContactRole promotedRole =
                firstPromotionByOpportunity.get(opportunityId);
            if (promotedRole != null) {
                addMultiplePrimaryError(promotedRole);
            }
        }
    }

    /**
     * @description Prevents direct removal of the Primary flag from the OCR that
     *              matches Opportunity.PrimaryContact__c. Users must change the
     *              Opportunity lookup so both records stay synchronized.
     * @param newRoles In-scope OCR records from Trigger.new.
     * @param oldMap Previous OCR values from Trigger.oldMap.
     */
    private static void rejectPrimaryRemoval(
        List<OpportunityContactRole> newRoles,
        Map<Id, OpportunityContactRole> oldMap
    ) {
        if (oldMap == null || oldMap.isEmpty()) {
            return;
        }

        List<OpportunityContactRole> demotedRoles =
            new List<OpportunityContactRole>();
        Set<Id> opportunityIds = new Set<Id>();

        for (OpportunityContactRole role : newRoles) {
            OpportunityContactRole oldRole = oldMap.get(role.Id);
            if (oldRole != null && oldRole.IsPrimary && !role.IsPrimary) {
                demotedRoles.add(role);
                opportunityIds.add(role.OpportunityId);
            }
        }

        if (demotedRoles.isEmpty()) {
            return;
        }

        Map<Id, Opportunity> opportunities =
            opportunitySelector.selectByIdsForPrimaryContact(opportunityIds);
        for (OpportunityContactRole role : demotedRoles) {
            Opportunity opp = opportunities.get(role.OpportunityId);
            if (opp != null && opp.PrimaryContact__c == role.ContactId) {
                Logger.info(
                    CLASS_NAME + '.rejectPrimaryRemoval: rejected OpportunityId=' +
                    role.OpportunityId
                );
                role.addError(Label.LS_OCRPrimaryRemovalErrors);
            }
        }
    }

    /**
     * @description Adds the localized duplicate-Primary error and a Nebula log.
     * @param role OCR record receiving the validation error.
     */
    private static void addMultiplePrimaryError(OpportunityContactRole role) {
        Logger.info(
            CLASS_NAME + '.rejectExtraPrimaries: rejected OpportunityId=' +
            role.OpportunityId
        );
        role.addError(Label.LS_OCRPrimaryRemovalError);
    }

    /**
     * @description Filters OCR records to the two Opportunity record types covered
     *              by GCL-11.
     * @param roles OCR records to evaluate.
     * @return OCR records whose parent Opportunity is in scope.
     */
    private static List<OpportunityContactRole> inScopeRoles(
        List<OpportunityContactRole> roles
    ) {
        if (roles == null || roles.isEmpty()) {
            return new List<OpportunityContactRole>();
        }

        Set<Id> opportunityIds = new Set<Id>();
        for (OpportunityContactRole role : roles) {
            if (role.OpportunityId != null) {
                opportunityIds.add(role.OpportunityId);
            }
        }

        Map<Id, Opportunity> opportunities =
            opportunitySelector.selectByIdsForPrimaryContact(opportunityIds);
        List<OpportunityContactRole> scopedRoles =
            new List<OpportunityContactRole>();

        for (OpportunityContactRole role : roles) {
            if (isInScope(opportunities.get(role.OpportunityId))) {
                scopedRoles.add(role);
            }
        }
        return scopedRoles;
    }

    /**
     * @description Determines whether an Opportunity belongs to either GCL-11
     *              record type.
     * @param opp Opportunity to evaluate.
     * @return True for LSSalesConsumables or LSEquipmentService.
     */
    private static Boolean isInScope(Opportunity opp) {
        return opp != null &&
            opp.RecordTypeId != null &&
            getInScopeRecordTypeIds().contains(opp.RecordTypeId);
    }

    /**
     * @description Resolves and caches in-scope Opportunity record type Ids by
     *              developer name without SOQL.
     * @return Set of record type Ids found in the current org.
     */
    private static Set<Id> getInScopeRecordTypeIds() {
        if (inScopeRecordTypeIds != null) {
            return inScopeRecordTypeIds;
        }

        inScopeRecordTypeIds = new Set<Id>();
        Map<String, Schema.RecordTypeInfo> byDeveloperName =
            Opportunity.SObjectType.getDescribe()
                .getRecordTypeInfosByDeveloperName();

        for (String developerName : IN_SCOPE_RECORD_TYPE_DEVELOPER_NAMES) {
            Schema.RecordTypeInfo recordTypeInfo =
                byDeveloperName.get(developerName);
            if (recordTypeInfo != null) {
                inScopeRecordTypeIds.add(recordTypeInfo.getRecordTypeId());
            } else {
                Logger.debug(
                    CLASS_NAME + '.getInScopeRecordTypeIds: record type not found=' +
                    developerName
                );
            }
        }
        return inScopeRecordTypeIds;
    }

    /**
     * @description Groups selected OCR records by Opportunity Id.
     * @param roles OCR records returned by OpportunityContactRoleSelector.
     * @return Opportunity Id to related OCR records.
     */
    private static Map<Id, List<OpportunityContactRole>> groupByOpportunity(
        List<OpportunityContactRole> roles
    ) {
        Map<Id, List<OpportunityContactRole>> rolesByOpportunity =
            new Map<Id, List<OpportunityContactRole>>();

        for (OpportunityContactRole role : roles) {
            if (!rolesByOpportunity.containsKey(role.OpportunityId)) {
                rolesByOpportunity.put(
                    role.OpportunityId,
                    new List<OpportunityContactRole>()
                );
            }
            rolesByOpportunity.get(role.OpportunityId).add(role);
        }
        return rolesByOpportunity;
    }
}