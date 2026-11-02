/*poc shiv*/
trigger EmailMessageBeforeInsertTEST on EmailMessage (after insert) {
        Set<Id> emailMessageIds = new Set<Id>();

    for (EmailMessage em : Trigger.new) {
        emailMessageIds.add(em.Id);
    }

    if (!emailMessageIds.isEmpty()) {
        EmailMessageRelationHelper.nullifyRelationId(emailMessageIds);
    }
}