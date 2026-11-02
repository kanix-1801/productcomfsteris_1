/**
 * Author: Akash Dahinde
 * Story: GC-2868
 * @description Determines whether an Account supports enterprise child record visibility.
 */
public with sharing class EnterpriseAccountEligibilityService {
    private static final Set<String> SUPPORTED_ACCOUNT_TYPES = buildSupportedAccountTypes();

    /**
     * @description Returns true for IDN, GPO, or Customer Accounts.
     * @param accountRecord Account being evaluated.
     * @return True when child Opportunities and Contacts should be displayed.
     */
    public static Boolean isSupportedAccount(Account accountRecord) {
        return accountRecord != null
            && !String.isBlank(accountRecord.Type)
            && SUPPORTED_ACCOUNT_TYPES.contains(normalize(accountRecord.Type));
    }

    private static Set<String> buildSupportedAccountTypes() {
        Set<String> supportedTypes = new Set<String>();
        addValue(supportedTypes, System.Label.Account_Type_IDN);
        addValue(supportedTypes, System.Label.Account_Type_GPO);
        addValue(supportedTypes, System.Label.Account_Type_Customer);
        return supportedTypes;
    }

    private static void addValue(Set<String> values, String value) {
        if (!String.isBlank(value)) {
            values.add(normalize(value));
        }
    }

    private static String normalize(String value) {
        return String.isBlank(value) ? null : value.trim().toLowerCase();
    }
}