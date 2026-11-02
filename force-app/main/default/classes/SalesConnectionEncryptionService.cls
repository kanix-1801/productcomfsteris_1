/**
 * @author Himanshu Chaurasia
 * @date 2026/09/01
 *
 * @group Generate Quote
 *
 * @description AES-256 encryption for Sales Connection create-quote URL payloads.
 */
public with sharing class SalesConnectionEncryptionService {
    private static final String AES256_ALGORITHM = 'AES256';

    @TestVisible
    private static String testEncryptionKeyOverride;

    @TestVisible
    private static Boolean testForceMissingEncryptionKey;

    /**
     * @description Encrypts a Sales Connection URL payload using AES-256.
     * @param plainText Payload string placed after #Quote| when opening Sales Connection.
     * @return Base64-encoded ciphertext including the generated initialization vector.
     */
    public static String encrypt(String plainText) {
        if (String.isBlank(plainText)) {
            throw new AuraHandledException('Sales Connection URL payload is required for encryption.');
        }

        Blob encryptionKey = resolveEncryptionKeyBlob();
        Blob encryptedData = Crypto.encryptWithManagedIV(
            AES256_ALGORITHM,
            encryptionKey,
            Blob.valueOf(plainText)
        );
        return EncodingUtil.base64Encode(encryptedData);
    }

    private static Blob resolveEncryptionKeyBlob() {
        if (Test.isRunningTest() && testForceMissingEncryptionKey == true) {
            throw new AuraHandledException(
                'Sales Connection encryption key is not configured. Please contact your administrator.'
            );
        }

        String encryptionKey = testEncryptionKeyOverride;

        if (String.isBlank(encryptionKey)) {
            ExternalSystemEndpoint__mdt settings = ExternalSystemEndpointSelector.selectSalesConnection();
            encryptionKey = settings == null ? null : settings.SalesConnectionEncryptionKey__c;
        }

        if (String.isBlank(encryptionKey)) {
            throw new AuraHandledException(
                'Sales Connection encryption key is not configured. Please contact your administrator.'
            );
        }

        Blob keyBlob = EncodingUtil.base64Decode(encryptionKey.trim());

        if (keyBlob.size() != 32) {
            throw new AuraHandledException(
                'Sales Connection encryption key must be a Base64-encoded 256-bit AES key.'
            );
        }

        return keyBlob;
    }
}