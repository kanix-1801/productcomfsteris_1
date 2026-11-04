trigger ClinicalParticipantTrigger on ClinicalParticipant__c(before insert, before update) {
    ClinicalParticipantService.blockDuplicateEmailOnReview(Trigger.new);
}