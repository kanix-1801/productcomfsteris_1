trigger EmailMessageTrigger2 on EmailMessage (before insert, before update, before delete, after insert, after update, after delete, after undelete) {
    // Single line orchestration into TriggerHandler per standards
    new EmailMessageTriggerHandler().run();
}