/**
 * @description GW-375 - Tests that a parent picture link does not copy the file.
 * @see MobileDevicePictureLinkHandler
 */
@IsTest
private class MobileDevicePictureLinkHandlerTest {
    /**
     * @description GW-375 - The event handler adds one link and leaves the file alone.
     */
    @IsTest
    static void linkFromEvents_insertsParentLinkWithoutCopyingFile() {
        String token = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        Account primary = new Account(
            Name = 'Picture Primary ' + token,
            SourceSystemID__c = 'ORACLE-PIC-PRI-' + token
        );
        Account parent = new Account(
            Name = 'Picture Parent ' + token,
            SourceSystemID__c = 'ORACLE-PIC-PAR-' + token
        );
        insert new List<Account>{ primary, parent };
        ContentVersion version = new ContentVersion(
            Title = 'Mobile Device Picture',
            PathOnClient = 'MobileDevicePicture.jpg',
            VersionData = Blob.valueOf('parent-link'),
            Description = 'MobileDevicePicture',
            FirstPublishLocationId = primary.Id
        );
        insert version;
        version = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
        ];
        MobileDevicePictureLink__e linkEvent = new MobileDevicePictureLink__e(
            ContentDocumentId__c = version.ContentDocumentId,
            LinkedEntityId__c = parent.Id
        );
        MobileDevicePictureLink__e duplicateEvent = new MobileDevicePictureLink__e(
            ContentDocumentId__c = version.ContentDocumentId,
            LinkedEntityId__c = parent.Id
        );

        Test.startTest();
        MobileDevicePictureLinkHandler.publishParentLink(null, null);
        MobileDevicePictureLinkHandler.linkFromEvents(null);
        MobileDevicePictureLinkHandler.linkFromEvents(new List<MobileDevicePictureLink__e>());
        MobileDevicePictureLinkHandler.linkFromEvents(new List<MobileDevicePictureLink__e>{
            new MobileDevicePictureLink__e(
                ContentDocumentId__c = 'not-an-id',
                LinkedEntityId__c = parent.Id
            ),
            new MobileDevicePictureLink__e()
        });
        MobileDevicePictureLinkHandler.linkFromEvents(
            new List<MobileDevicePictureLink__e>{ linkEvent, duplicateEvent }
        );
        Test.stopTest();

        System.assertEquals(1, [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :version.ContentDocumentId
                AND LinkedEntityId = :parent.Id
        ]);
        System.assertEquals(1, [
            SELECT COUNT()
            FROM ContentVersion
            WHERE ContentDocumentId = :version.ContentDocumentId
        ]);
    }

    /**
     * @description GW-375 - Publishing the event creates the parent link after the file commits.
     */
    @IsTest
    static void publishParentLink_createsParentLink() {
        String token = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        Account primary = new Account(
            Name = 'Publish Primary ' + token,
            SourceSystemID__c = 'ORACLE-PIC-PUB-P-' + token
        );
        Account parent = new Account(
            Name = 'Publish Parent ' + token,
            SourceSystemID__c = 'ORACLE-PIC-PUB-S-' + token
        );
        insert new List<Account>{ primary, parent };
        ContentVersion version = new ContentVersion(
            Title = 'Mobile Device Picture',
            PathOnClient = 'MobileDevicePicture.jpg',
            VersionData = Blob.valueOf('queued-link'),
            Description = 'MobileDevicePicture',
            FirstPublishLocationId = primary.Id
        );
        insert version;
        version = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
        ];

        Test.startTest();
        MobileDevicePictureLinkHandler.publishParentLink(version.ContentDocumentId, parent.Id);
        Test.stopTest();

        System.assertEquals(1, [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :version.ContentDocumentId
                AND LinkedEntityId = :parent.Id
        ]);
        System.assertEquals(1, [
            SELECT COUNT()
            FROM ContentVersion
            WHERE ContentDocumentId = :version.ContentDocumentId
        ]);
    }

    /**
     * @description GW-375 - A user who does not own the parent still gets the picture linked there.
     */
    @IsTest
    static void saveMobileDevicePicture_linksParentWhenUserDoesNotOwnIt() {
        User limitedUser = newLimitedUser();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert limitedUser;
            List<PermissionSet> workOrderAccess = [
                SELECT Id FROM PermissionSet WHERE Name = 'ManageWorkOrders' LIMIT 1
            ];
            if (!workOrderAccess.isEmpty()) {
                insert new PermissionSetAssignment(
                    AssigneeId = limitedUser.Id,
                    PermissionSetId = workOrderAccess[0].Id
                );
            }
        }
        String token = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        Account account = new Account(
            Name = 'Unowned Site Visit ' + token,
            SourceSystemID__c = 'ORACLE-PIC-UNO-' + token
        );
        insert account;
        WorkOrder siteVisit = new WorkOrder(
            AccountId = account.Id,
            OwnerId = UserInfo.getUserId(),
            Subject = 'Unowned Site Visit ' + token
        );
        insert siteVisit;
        WorkOrder child = new WorkOrder(
            AccountId = account.Id,
            ParentWorkOrderId = siteVisit.Id,
            OwnerId = limitedUser.Id,
            Subject = 'Owned Child ' + token
        );
        insert child;

        Id documentId;
        Test.startTest();
        System.runAs(limitedUser) {
            documentId = WoDebriefIMSchildWOController.saveMobileDevicePicture(
                child.Id,
                siteVisit.Id,
                EncodingUtil.base64Encode(Blob.valueOf('unowned-parent')),
                'MobileDevicePicture.jpg',
                null
            ).contentDocumentId;
        }
        Test.stopTest();

        System.assertNotEquals(UserInfo.getUserId(), limitedUser.Id);
        System.assertEquals(1, [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :documentId
                AND LinkedEntityId = :siteVisit.Id
        ], 'The picture is linked to a site visit the user does not own');
        System.assertEquals(1, [
            SELECT COUNT()
            FROM ContentVersion
            WHERE ContentDocumentId = :documentId
        ]);
    }

    /**
     * @description A picture the mobile app links to a line itself updates the line count
     *              and is linked to the site visit work order.
     */
    @IsTest
    static void completeMobileAppPictureLinks_countsPictureAndLinksSiteVisit() {
        String token = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        Account account = new Account(
            Name = 'Offline Picture ' + token,
            SourceSystemID__c = 'ORACLE-PIC-OFF-' + token
        );
        insert account;
        WorkOrder siteVisit = new WorkOrder(AccountId = account.Id, Subject = 'Offline Site Visit ' + token);
        insert siteVisit;
        WorkOrder child = new WorkOrder(
            AccountId = account.Id,
            ParentWorkOrderId = siteVisit.Id,
            Subject = 'Offline Child ' + token
        );
        insert child;
        WorkOrderLineItem line = new WorkOrderLineItem(
            WorkOrderId = child.Id,
            RecordTypeId = Schema.SObjectType.WorkOrderLineItem
                .getRecordTypeInfosByDeveloperName()
                .get('ProductServiced')
                .getRecordTypeId(),
            LineType__c = 'Instrument'
        );
        insert line;
        ContentVersion picture = new ContentVersion(
            Title = 'Mobile Device Picture',
            PathOnClient = 'MobileDevicePicture.jpg',
            VersionData = Blob.valueOf('offline-picture'),
            Description = 'MobileDevicePicture'
        );
        ContentVersion otherFile = new ContentVersion(
            Title = 'Other File',
            PathOnClient = 'Other.jpg',
            VersionData = Blob.valueOf('other-file')
        );
        insert new List<ContentVersion>{ picture, otherFile };
        Map<Id, Id> documentByVersion = new Map<Id, Id>();
        for (ContentVersion version : [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id IN :new Set<Id>{ picture.Id, otherFile.Id }
        ]) {
            documentByVersion.put(version.Id, version.ContentDocumentId);
        }
        Id pictureDocumentId = documentByVersion.get(picture.Id);
        Id otherDocumentId = documentByVersion.get(otherFile.Id);

        Test.startTest();
        insert new List<ContentDocumentLink>{
            new ContentDocumentLink(ContentDocumentId = pictureDocumentId, LinkedEntityId = line.Id, ShareType = 'V'),
            new ContentDocumentLink(ContentDocumentId = otherDocumentId, LinkedEntityId = line.Id, ShareType = 'V')
        };
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT MobileDevicePictureCount__c FROM WorkOrderLineItem WHERE Id = :line.Id]
                .MobileDevicePictureCount__c,
            'Only the Mobile Device Picture is counted'
        );
        System.assertEquals(1, [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :pictureDocumentId
                AND LinkedEntityId = :siteVisit.Id
        ], 'The picture is linked to the site visit work order');
        System.assertEquals(0, [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :otherDocumentId
                AND LinkedEntityId = :siteVisit.Id
        ], 'Other files are not linked to the site visit work order');
    }

    /**
     * @description GW-375 - Details the mobile app sends in the description are moved into their fields.
     */
    @IsTest
    static void completeMobileAppPictureLinks_movesDetailsIntoFields() {
        String token = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        Account account = new Account(
            Name = 'Picture Details ' + token,
            SourceSystemID__c = 'ORACLE-PIC-DET-' + token
        );
        insert account;
        WorkOrder child = new WorkOrder(AccountId = account.Id, Subject = 'Picture Details ' + token);
        insert child;
        ContentVersion picture = new ContentVersion(
            Title = WoDebriefIMSchildWOController.MOBILE_DEVICE_PICTURE_TITLE,
            PathOnClient = 'MobileDevicePicture.jpg',
            VersionData = Blob.valueOf('offline-picture'),
            Description = WoDebriefIMSchildWOController.MOBILE_DEVICE_PICTURE_MARKER
                + WoDebriefIMSchildWOController.PICTURE_DETAILS_SEPARATOR
                + '{"category":"Care and Handling","beforeAfter":"Before","comment":"Bent tip"}'
        );
        insert picture;
        Id documentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :picture.Id].ContentDocumentId;

        Test.startTest();
        insert new ContentDocumentLink(ContentDocumentId = documentId, LinkedEntityId = child.Id, ShareType = 'V');
        Test.stopTest();

        ContentVersion saved = [
            SELECT Description, PictureCategory__c, BeforeAfter__c, MobileDevicePictureComment__c
            FROM ContentVersion
            WHERE Id = :picture.Id
        ];
        System.assertEquals('Care and Handling', saved.PictureCategory__c);
        System.assertEquals('Before', saved.BeforeAfter__c);
        System.assertEquals('Bent tip', saved.MobileDevicePictureComment__c);
        System.assertEquals(
            WoDebriefIMSchildWOController.MOBILE_DEVICE_PICTURE_MARKER,
            saved.Description,
            'Only the marker stays in the description'
        );
    }

    /**
     * @description GW-375 - Standard user used to save a picture without owning the parent record.
     * @return User
     */
    private static User newLimitedUser() {
        Profile standardProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];
        String uniqueName = 'pic.limited.' + System.currentTimeMillis() + '@example.com';
        return new User(
            Alias = 'piclim',
            Email = uniqueName,
            EmailEncodingKey = 'UTF-8',
            LastName = 'PictureLimited',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = uniqueName
        );
    }
}