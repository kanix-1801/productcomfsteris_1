/**
 * @author Abhishek Mishra
 * @date 04-06-2026
 * @description Prevents recursive trigger execution within the same transaction.
 *              Each object and trigger context is tracked separately
 *              (e.g. Account:afterInsert, Lead:afterInsert).
 */
public with sharing class TriggerControl {

    private static Map<String, Boolean> executedFlags = new Map<String, Boolean>();

    /**
     * @description Marks before insert as executed for the given SObject type.
     * @param sobjectType SObject type to track.
     * @return True when processing can continue; false when already executed.
     */
    public static Boolean enterBeforeInsert(Schema.SObjectType sobjectType) {
        return canExecute(sobjectType, 'beforeInsert');
    }

    /**
     * @description Marks before update as executed for the given SObject type.
     * @param sobjectType SObject type to track.
     * @return True when processing can continue; false when already executed.
     */
    public static Boolean enterBeforeUpdate(Schema.SObjectType sobjectType) {
        return canExecute(sobjectType, 'beforeUpdate');
    }

    /**
     * @description Marks after insert as executed for the given SObject type.
     * @param sobjectType SObject type to track.
     * @return True when processing can continue; false when already executed.
     */
    public static Boolean enterAfterInsert(Schema.SObjectType sobjectType) {
        return canExecute(sobjectType, 'afterInsert');
    }

    /**
     * @description Marks after update as executed for the given SObject type.
     * @param sobjectType SObject type to track.
     * @return True when processing can continue; false when already executed.
     */
    public static Boolean enterAfterUpdate(Schema.SObjectType sobjectType) {
        return canExecute(sobjectType, 'afterUpdate');
    }

    // GC-3213 - START
    /**
     * @description Marks after delete as executed for the given SObject type.
     * @param sobjectType SObject type to track.
     * @return True when processing can continue; false when already executed.
     */
    public static Boolean enterAfterDelete(Schema.SObjectType sobjectType) {
        return canExecute(sobjectType, 'afterDelete');
    }

    /**
     * @description Clears a previously recorded execution flag so a later DML
     *              in the same transaction can run the same context again.
     * @param sobjectType SObject type to clear.
     * @param context Trigger context key (e.g. afterInsert).
     */
    public static void reset(Schema.SObjectType sobjectType, String context) {
        executedFlags.put(sobjectType.getDescribe().getName() + ':' + context, false);
    }

    public static void resetAfterInsert(Schema.SObjectType sobjectType) {
        reset(sobjectType, 'afterInsert');
    }

    public static void resetAfterUpdate(Schema.SObjectType sobjectType) {
        reset(sobjectType, 'afterUpdate');
    }

    public static void resetAfterDelete(Schema.SObjectType sobjectType) {
        reset(sobjectType, 'afterDelete');
    }
    // GC-3213 - END

    private static Boolean canExecute(Schema.SObjectType sobjectType, String context) {
        String key = sobjectType.getDescribe().getName() + ':' + context;

        if (executedFlags.get(key) == true) {
            return false;
        }

        executedFlags.put(key, true);
        return true;
    }
}