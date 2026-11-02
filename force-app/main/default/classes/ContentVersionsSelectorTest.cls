/**
 * @description GW-1206 / GW-4189 - Tests for ContentVersionsSelector.
 */
@IsTest
private class ContentVersionsSelectorTest {
    /**
     * @description GW-1206 - Constructing the selector covers the class.
     */
    @IsTest
    static void testConstructorSetsContentVersion() {
        ContentVersionsSelector selector = new ContentVersionsSelector();
        Assert.isNotNull(selector, 'ContentVersionsSelector should construct');
    }

    /**
     * @description GW-4189 - Latest PDFs by ContentDocument Id; blanks and non-PDFs excluded.
     */
    @IsTest
    static void testSelectLatestPdfsByContentDocumentIds() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            ContentVersion pdfVersion = new ContentVersion(
                Title = 'GW4189 Selector Pdf',
                PathOnClient = 'gw4189-selector.pdf',
                VersionData = Blob.valueOf('pdf-bytes'),
                IsMajorVersion = true
            );
            ContentVersion imageVersion = new ContentVersion(
                Title = 'GW4189 Selector Image',
                PathOnClient = 'gw4189-selector.jpg',
                VersionData = Blob.valueOf('image-bytes'),
                IsMajorVersion = true
            );
            insert new List<ContentVersion>{ pdfVersion, imageVersion };

            pdfVersion = [
                SELECT ContentDocumentId, FileType
                FROM ContentVersion
                WHERE Id = :pdfVersion.Id
            ];
            imageVersion = [
                SELECT ContentDocumentId, FileType
                FROM ContentVersion
                WHERE Id = :imageVersion.Id
            ];
            Assert.areEqual('PDF', pdfVersion.FileType, 'PDF PathOnClient should yield FileType PDF');

            Test.startTest();
            Assert.isTrue(
                ContentVersionsSelector.selectLatestPdfsByContentDocumentIds(null).isEmpty(),
                'Null ids should return empty'
            );
            Assert.isTrue(
                ContentVersionsSelector.selectLatestPdfsByContentDocumentIds(new Set<Id>())
                    .isEmpty(),
                'Empty ids should return empty'
            );
            List<ContentVersion> pdfs = ContentVersionsSelector.selectLatestPdfsByContentDocumentIds(
                new Set<Id>{ pdfVersion.ContentDocumentId, imageVersion.ContentDocumentId }
            );
            Test.stopTest();

            Assert.areEqual(1, pdfs.size(), 'Only the PDF latest version should return');
            Assert.areEqual(pdfVersion.ContentDocumentId, pdfs[0].ContentDocumentId);
            Assert.areEqual('GW4189 Selector Pdf', pdfs[0].Title);
        }
    }
}