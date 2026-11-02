/**
 * @author Himanshu Chaurasia
 * @date 2026/09/01
 *
 * @group Generate Quote
 *
 * @description Test class for SalesConnectionEncryptionService.
 */
@IsTest
private class SalesConnectionEncryptionServiceTest {
    private static final String TEST_ENCRYPTION_KEY =
        'abcdefghijklmnopqrstuvwxyz012345';

    @IsTest
    static void encryptReturnsBase64Ciphertext() {
        SalesConnectionEncryptionService.testEncryptionKeyOverride = EncodingUtil.base64Encode(
            Blob.valueOf(TEST_ENCRYPTION_KEY)
        );

        Test.startTest();
        String encryptedValue = SalesConnectionEncryptionService.encrypt(
            'id=0&addressid=319163&accounttype=C&sfrequest=create&sfopportunityid=006Ou00000VxM2fIAF&sfquoteid=0Q0Ou000004QsdZKAS&employeenumber=12345'
        );
        Test.stopTest();

        System.assertNotEquals(null, encryptedValue);
        System.assertNotEquals(
            'id=0&addressid=319163',
            encryptedValue,
            'Encrypted payload should not match the plain text value.'
        );
    }

    @IsTest
    static void encryptRequiresConfiguredKey() {
        SalesConnectionEncryptionService.testEncryptionKeyOverride = null;
        SalesConnectionEncryptionService.testForceMissingEncryptionKey = true;
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            SalesConnectionEncryptionService.encrypt('id=0');
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        } finally {
            SalesConnectionEncryptionService.testForceMissingEncryptionKey = false;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Missing encryption key should throw an AuraHandledException.');
    }

    @IsTest
    static void encryptRequiresValidKeyLength() {
        SalesConnectionEncryptionService.testEncryptionKeyOverride =
            EncodingUtil.base64Encode(Blob.valueOf('invalid-key'));
        SalesConnectionEncryptionService.testForceMissingEncryptionKey = false;
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            SalesConnectionEncryptionService.encrypt('id=0');
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Invalid encryption key length should throw an AuraHandledException.');
    }

    @IsTest
    static void encryptRequiresPlainText() {
        SalesConnectionEncryptionService.testEncryptionKeyOverride = EncodingUtil.base64Encode(
            Blob.valueOf(TEST_ENCRYPTION_KEY)
        );
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            SalesConnectionEncryptionService.encrypt(' ');
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Blank payload should throw an AuraHandledException.');
    }
}