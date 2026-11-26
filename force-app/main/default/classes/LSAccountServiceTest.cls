/**
 * @description Covers LSAccountService.
 */
@IsTest
private class LSAccountServiceTest {

    @IsTest
    static void testIsLifeSciencesAccount_WhenClassCodeIsSC_ReturnsTrue() {
        Assert.isTrue(LSAccountService.isLifeSciencesAccount(new Account(CustomerClassCode__c = 'SC')));
    }

    @IsTest
    static void testIsLifeSciencesAccount_WhenClassCodeHasCaseOrWhitespace_ReturnsTrue() {
        Assert.isTrue(LSAccountService.isLifeSciencesAccount(new Account(CustomerClassCode__c = 'sc')));
        Assert.isTrue(LSAccountService.isLifeSciencesAccount(new Account(CustomerClassCode__c = ' SC ')));
    }

    @IsTest
    static void testIsLifeSciencesAccount_WhenClassCodeIsNotLifeSciences_ReturnsFalse() {
        Assert.isFalse(LSAccountService.isLifeSciencesAccount(new Account(CustomerClassCode__c = 'HC')));
        Assert.isFalse(LSAccountService.isLifeSciencesAccount(new Account(CustomerClassCode__c = 'IC')));
    }

    @IsTest
    static void testIsLifeSciencesAccount_WhenClassCodeBlank_ReturnsFalse() {
        Assert.isFalse(LSAccountService.isLifeSciencesAccount(new Account()));
        Assert.isFalse(LSAccountService.isLifeSciencesAccount(new Account(CustomerClassCode__c = '')));
        Assert.isFalse(LSAccountService.isLifeSciencesAccount(new Account(CustomerClassCode__c = '   ')));
    }

    @IsTest
    static void testIsLifeSciencesAccount_WhenAccountIsNull_ReturnsFalse() {
        Assert.isFalse(LSAccountService.isLifeSciencesAccount(null));
    }
}