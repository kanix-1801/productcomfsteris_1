/**
 * @description Life Sciences class code check for the shared Healthcare TAS classes.
 * author PWC Developer
 * @date 2026/06/10
 *
 *  GCL-4 / GCL-83: Life Sciences Prospect and Customer TAS run through AccountService,
 *  AccountProspectTasQueueable and AccountCustomerTasQueueable.
 *  Class code Life Science = SC.
 */
public with sharing class LSAccountService {

    private static final Set<String> LS_CLASS_CODES = new Set<String>{
        'SC'
    };

    /**
     * @description Single source of truth for Life Sciences branching.
     * @param acc Account record to evaluate.
     * @return True when the Account belongs to the Life Sciences business unit.
     */
    public static Boolean isLifeSciencesAccount(Account acc) {
        return acc != null
            && String.isNotBlank(acc.CustomerClassCode__c)
            && LS_CLASS_CODES.contains(acc.CustomerClassCode__c.trim().toUpperCase());
    }
}