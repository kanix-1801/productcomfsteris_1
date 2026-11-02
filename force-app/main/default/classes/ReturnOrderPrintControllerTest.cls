@IsTest
private class ReturnOrderPrintControllerTest {

    @TestSetup
    static void setupTestData() {
        // Build and persist an Account to parent the ReturnOrders
        adb_Account accountBuilder = new adb_Account();
        accountBuilder.persist();

        // Build and persist ReturnOrders for test coverage
        List<ReturnOrder> returnOrderList = new List<ReturnOrder>();

        for (Integer i = 0; i < 10; i++) {
            ReturnOrder ro = new ReturnOrder(
                AccountId = accountBuilder.id,
                Status = 'Draft'
            );

            returnOrderList.add(ro);
        }

        insert returnOrderList;
    }

    /**
     * Tests the happy path where both the RO Form and Shipping Label
     * documents exist and are successfully returned as Base64.
     */
    @IsTest
    static void getPrintDocuments_happyPath() {
        ReturnOrder returnOrder = getTestReturnOrder();

        Blob roFormBody = Blob.valueOf('RO Form Test Content');
        Blob shippingLabelBody = Blob.valueOf('Shipping Label Test Content');

        ContentVersion roForm = new ContentVersion(
            Title = 'RO Form',
            PathOnClient = 'RO Form.pdf',
            VersionData = roFormBody
        );

        ContentVersion shippingLabel = new ContentVersion(
            Title = 'Shipping Label',
            PathOnClient = 'Shipping Label.pdf',
            VersionData = shippingLabelBody
        );

        insert new List<ContentVersion>{
            roForm,
            shippingLabel
        };

        linkFileToReturnOrder(roForm.Id, returnOrder.Id);
        linkFileToReturnOrder(shippingLabel.Id, returnOrder.Id);

        Test.startTest();

        ReturnOrderPrintController.PrintDocumentWrapper result =
            ReturnOrderPrintController.getPrintDocuments(returnOrder.Id);

        Test.stopTest();

        System.assertNotEquals(
            null,
            result,
            'A wrapper should be returned.'
        );

        System.assertEquals(
            null,
            result.missingDocuments,
            'No documents should be missing.'
        );

        System.assertEquals(
            EncodingUtil.base64Encode(roFormBody),
            result.roFormBase64,
            'The RO Form Base64 should match the uploaded file.'
        );

        System.assertEquals(
            EncodingUtil.base64Encode(shippingLabelBody),
            result.shippingLabelBase64,
            'The Shipping Label Base64 should match the uploaded file.'
        );
    }

    /**
     * Tests the scenario where the RO Form is missing but the
     * Shipping Label document exists.
     */
    @IsTest
    static void getPrintDocuments_missingRoForm() {
        ReturnOrder returnOrder = getTestReturnOrder();

        ContentVersion shippingLabel = new ContentVersion(
            Title = 'Shipping Label',
            PathOnClient = 'Shipping Label.pdf',
            VersionData = Blob.valueOf('Shipping Label Test Content')
        );

        insert shippingLabel;

        linkFileToReturnOrder(shippingLabel.Id, returnOrder.Id);

        Test.startTest();

        ReturnOrderPrintController.PrintDocumentWrapper result =
            ReturnOrderPrintController.getPrintDocuments(returnOrder.Id);

        Test.stopTest();

        System.assertNotEquals(
            null,
            result,
            'A wrapper should be returned.'
        );

        System.assertEquals(
            1,
            result.missingDocuments.size(),
            'Only one document should be missing.'
        );

        System.assertEquals(
            'RO Form',
            result.missingDocuments[0],
            'RO Form should be reported as missing.'
        );

        System.assertEquals(
            null,
            result.roFormBase64,
            'RO Form Base64 should be null.'
        );

        System.assertEquals(
            null,
            result.shippingLabelBase64,
            'Shipping Label Base64 should be null when any required document is missing.'
        );
    }

    /**
     * Tests the scenario where the Shipping Label is missing but
     * the RO Form document exists.
     */
    @IsTest
    static void getPrintDocuments_missingShippingLabel() {
        ReturnOrder returnOrder = getTestReturnOrder();

        ContentVersion roForm = new ContentVersion(
            Title = 'RO Form',
            PathOnClient = 'RO Form.pdf',
            VersionData = Blob.valueOf('RO Form Test Content')
        );

        insert roForm;

        linkFileToReturnOrder(roForm.Id, returnOrder.Id);

        Test.startTest();

        ReturnOrderPrintController.PrintDocumentWrapper result =
            ReturnOrderPrintController.getPrintDocuments(returnOrder.Id);

        Test.stopTest();

        System.assertNotEquals(
            null,
            result,
            'A wrapper should be returned.'
        );

        System.assertEquals(
            1,
            result.missingDocuments.size(),
            'Only one document should be missing.'
        );

        System.assertEquals(
            'Shipping Label',
            result.missingDocuments[0],
            'Shipping Label should be reported as missing.'
        );

        System.assertEquals(
            null,
            result.roFormBase64,
            'RO Form Base64 should be null when any required document is missing.'
        );

        System.assertEquals(
            null,
            result.shippingLabelBase64,
            'Shipping Label Base64 should be null.'
        );
    }

    /**
     * Tests the scenario where neither the RO Form nor the Shipping Label
     * documents exist and both are reported as missing.
     */
    @IsTest
    static void getPrintDocuments_missingBothDocuments() {
        ReturnOrder returnOrder = getTestReturnOrder();

        Test.startTest();

        ReturnOrderPrintController.PrintDocumentWrapper result =
            ReturnOrderPrintController.getPrintDocuments(returnOrder.Id);

        Test.stopTest();

        System.assertNotEquals(
            null,
            result,
            'A wrapper should be returned.'
        );

        System.assertEquals(
            2,
            result.missingDocuments.size(),
            'Both required documents should be reported as missing.'
        );

        System.assert(
            result.missingDocuments.contains('RO Form'),
            'RO Form should be reported as missing.'
        );

        System.assert(
            result.missingDocuments.contains('Shipping Label'),
            'Shipping Label should be reported as missing.'
        );

        System.assertEquals(
            null,
            result.roFormBase64,
            'RO Form Base64 should be null.'
        );

        System.assertEquals(
            null,
            result.shippingLabelBase64,
            'Shipping Label Base64 should be null.'
        );
    }

    /**
     * Returns a Return Order created by the test setup.
     */
    private static ReturnOrder getTestReturnOrder() {
        return [
            SELECT Id
            FROM ReturnOrder
            LIMIT 1
        ];
    }

    /**
     * Links a ContentVersion to the Return Order through its
     * ContentDocument.
     */
    private static void linkFileToReturnOrder(
        Id contentVersionId,
        Id returnOrderId
    ) {
        ContentVersion contentVersion = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :contentVersionId
            LIMIT 1
        ];

        insert new ContentDocumentLink(
            ContentDocumentId = contentVersion.ContentDocumentId,
            LinkedEntityId = returnOrderId,
            ShareType = 'V'
        );
    }
}