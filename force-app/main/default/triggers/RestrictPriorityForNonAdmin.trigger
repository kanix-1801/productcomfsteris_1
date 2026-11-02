trigger RestrictPriorityForNonAdmin on Task (before insert, before update) {

    Profile p = [
        SELECT Name
        FROM Profile
        WHERE Id = :UserInfo.getProfileId()
        LIMIT 1
    ];
    Boolean isSysAdmin = (p.Name == 'System Administrator');

    for (Task t : Trigger.new) {

        // Always allow System Admin; do not touch bypass flag
        if (isSysAdmin) {
            continue;
        }

        // If bypass is checked, allow the change but reset it (one-time bypass)
        if (t.BypassValidation__c == true) {
            t.BypassValidation__c = false;
            continue;
        }

        // Match original VR behavior: do nothing on insert
        if (Trigger.isInsert) {
            continue;
        }

        // On update, block only when Priority changes
        Task oldT = Trigger.oldMap.get(t.Id);
        if (oldT != null && t.Priority != oldT.Priority) {
            t.Priority.addError('Urgency is not Editable for you');
        }
    }
}