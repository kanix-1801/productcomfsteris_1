/**
 * @description GW-1505 — Tests for {@link WorkOrderLineItemFileThumbnailRest}.
 */
@IsTest
private class WorkOrderLineItemFileThumbnailRestTest {
    private static final String MIN_PNG_BASE64 =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

    @IsTest
    static void testGetFileThumbnail_returnsImageForContentVersion() {
        WorkOrderLineItem lineItem = createWorkOrderLineItem();
        WorkOrderLineItemCaptureService.saveMicroscopeImage(
            lineItem.Id,
            MIN_PNG_BASE64,
            'Thumbnail_Rest_Test.png',
            'Fixable'
        );

        ContentVersion version = [
            SELECT Id
            FROM ContentVersion
            WHERE Title = 'Thumbnail_Rest_Test.png'
            LIMIT 1
        ];

        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/woli/v1/file-thumbnail/' + version.Id;
        request.httpMethod = 'GET';
        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        WorkOrderLineItemFileThumbnailRest.getFileThumbnail();
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode, 'Thumbnail proxy should return HTTP 200');
        Assert.isTrue(RestContext.response.responseBody.size() > 0, 'Thumbnail body should not be empty');
    }

    @IsTest
    static void testGetFileThumbnail_returnsJpegContentTypeForJpgFile() {
        ContentVersion version = createImageContentVersion('Thumbnail_Jpeg_Test.jpg', 'jpg');
        invokeThumbnailRequest(version.Id);

        Assert.areEqual(200, RestContext.response.statusCode, 'JPEG thumbnail should return HTTP 200');
        Assert.isTrue(
            String.valueOf(RestContext.response.headers.get('Content-Type')).contains('image/jpeg'),
            'JPEG files should return image/jpeg content type'
        );
    }

    @IsTest
    static void testGetFileThumbnail_returnsPngContentTypeForPngFile() {
        ContentVersion version = createImageContentVersion('Thumbnail_Png_Test.png', 'png');
        invokeThumbnailRequest(version.Id);

        Assert.areEqual(200, RestContext.response.statusCode, 'PNG thumbnail should return HTTP 200');
        Assert.isTrue(
            String.valueOf(RestContext.response.headers.get('Content-Type')).contains('image/png'),
            'PNG files should return image/png content type'
        );
    }

    @IsTest
    static void testGetFileThumbnail_returns404ForEmptyThumbnailBlob() {
        ContentVersion version = createImageContentVersion('Thumbnail_Empty_Test.png', 'png');
        WorkOrderLineItemFileThumbnailRest.returnEmptyBlobInTest = true;

        invokeThumbnailRequest(version.Id);

        Assert.areEqual(404, RestContext.response.statusCode, 'Empty thumbnail blob should return HTTP 404');
        WorkOrderLineItemFileThumbnailRest.returnEmptyBlobInTest = false;
    }

    @IsTest
    static void testGetFileThumbnail_returnsGifContentTypeForGifFile() {
        ContentVersion version = createImageContentVersion('Thumbnail_Gif_Test.gif', 'gif');
        invokeThumbnailRequest(version.Id);

        Assert.areEqual(200, RestContext.response.statusCode, 'GIF thumbnail should return HTTP 200');
        Assert.isTrue(
            String.valueOf(RestContext.response.headers.get('Content-Type')).contains('image/gif'),
            'GIF files should return image/gif content type'
        );
    }

    @IsTest
    static void testGetFileThumbnail_returns400ForBlankVersionId() {
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/woli/v1/file-thumbnail/';
        request.httpMethod = 'GET';
        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        WorkOrderLineItemFileThumbnailRest.getFileThumbnail();
        Test.stopTest();

        Assert.areEqual(400, RestContext.response.statusCode, 'Blank version Id should return HTTP 400');
    }

    @IsTest
    static void testGetFileThumbnail_returns404ForMissingVersion() {
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/woli/v1/file-thumbnail/068000000000000AAA';
        request.httpMethod = 'GET';
        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        WorkOrderLineItemFileThumbnailRest.getFileThumbnail();
        Test.stopTest();

        Assert.areEqual(404, RestContext.response.statusCode, 'Missing version should return HTTP 404');
    }

    private static void invokeThumbnailRequest(Id versionId) {
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/woli/v1/file-thumbnail/' + versionId;
        request.httpMethod = 'GET';
        RestContext.request = request;
        RestContext.response = new RestResponse();
        WorkOrderLineItemFileThumbnailRest.getFileThumbnail();
    }

    private static ContentVersion createImageContentVersion(String title, String extension) {
        ContentVersion version = new ContentVersion(
            Title = title,
            PathOnClient = title,
            VersionData = EncodingUtil.base64Decode(MIN_PNG_BASE64),
            IsMajorVersion = true
        );
        insert version;
        version = [
            SELECT FileExtension, Id
            FROM ContentVersion
            WHERE Id = :version.Id
            LIMIT 1
        ];
        return version;
    }

    private static WorkOrderLineItem createWorkOrderLineItem() {
        Account account = new Account(Name = 'Thumbnail Rest Test Account');
        Schema.RecordTypeInfo prospectRt =
            Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Prospect');
        if (prospectRt != null) {
            account.RecordTypeId = prospectRt.getRecordTypeId();
            account.ShippingStreet = '100 Thumbnail Test Ln';
            account.ShippingCity = 'Mentor';
            account.ShippingPostalCode = '44060';
            account.ShippingCountryCode = 'US';
            account.ShippingStateCode = 'OH';
        }
        insert account;

        WorkOrder workOrder = new WorkOrder(AccountId = account.Id, Status = 'New');
        insert workOrder;

        WorkOrderLineItem lineItem = new WorkOrderLineItem(WorkOrderId = workOrder.Id, Status = 'New');
        insert lineItem;
        return lineItem;
    }
}