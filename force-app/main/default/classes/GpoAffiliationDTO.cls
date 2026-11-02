public without sharing class GpoAffiliationDTO {
    @AuraEnabled public Id id;
    @AuraEnabled public String contract;
    @AuraEnabled public String contractName;
    @AuraEnabled public String status;
    @AuraEnabled public String contractType;
    @AuraEnabled public Date effectiveDate;
    @AuraEnabled public Date expirationDate;

    public GpoAffiliationDTO(AccountAccountRelation accountAccountRelation) {
        id = accountAccountRelation.Id;
        contract = accountAccountRelation.Name;
        contractName = accountAccountRelation.Account != null
            ? accountAccountRelation.Account.Name
            : '';
        status = accountAccountRelation.Status__c;
        //contractType = accountAccountRelation.ContractType__c;
        effectiveDate = accountAccountRelation.StartDate;
        expirationDate = accountAccountRelation.EndDate;
    }
}