/**
 * @description Tests for the mobile Product Request create and submit service.
 */
@IsTest
private class CreateProductRequestServiceTest {
    private static final String SHIPMENT_TYPE = 'Overnight';

    /**
     * @description A user with no Service Resource cannot open the screen.
     */
    @IsTest
    static void testGetContextNoServiceResource() {
        User technician = createTechnician();

        // SETUP
        System.runAs(technician) {
            // GIVEN
            // The technician has no Service Resource.

            // WHEN
            CreateProductRequestService.ContextResult context = CreateProductRequestController.getContext(
                null,
                technician.Id
            );

            // THEN
            System.assertEquals(null, context.workOrderId, 'A standalone screen has no Work Order.');
            System.assertEquals(
                Label.CreateProductRequest_NoServiceResource,
                context.blockMessage,
                'The screen explains that no Service Resource was found.'
            );
        }
    }

    /**
     * @description Standalone context returns the technician location and hides customer ship-to.
     */
    @IsTest
    static void testGetContextStandalone() {
        User technician = createTechnician();
        System.runAs(technician) {
            // SETUP
            Fixture fixture = insertFixture(technician, false);

            // GIVEN
            System.assertEquals(0, fixture.shipToAccountCount, 'Standalone setup has no customer account.');

            // WHEN
            CreateProductRequestService.ContextResult context = CreateProductRequestController.getContext(
                null,
                technician.Id
            );
            CreateProductRequestService.AddressResult addresses = CreateProductRequestController.getAddresses(
                fixture.serviceResourceId,
                technician.Id,
                null
            );

            // THEN
            System.assertEquals(fixture.addressId, addresses.defaultAddressId, 'Reloaded addresses keep the default.');
            System.assertEquals(false, context.hasWorkOrder, 'Standalone context is not tied to a Work Order.');
            System.assertEquals(1, context.serviceResources.size(), 'The technician resource is returned.');
            System.assertEquals(fixture.addressId, context.defaultAddressId, 'The visitor address is the default.');
            System.assertEquals(1, context.addresses.size(), 'The location address is returned.');
            System.assertEquals(fixture.addressName, context.addresses[0].name, 'The address name is shown.');
            System.assert(
                context.addresses[0].name.contains('14 Service Road'),
                'The address street is shown with the name.'
            );
            System.assertEquals(0, context.shipToAccounts.size(), 'Customer ship-to is omitted.');
            System.assertEquals(0, context.requiredParts.size(), 'Required parts are omitted.');
        }
    }

    /**
     * @description A Work Order with no assigned Technician cannot continue.
     */
    @IsTest
    static void testGetContextWorkOrderWithoutAssignment() {
        User technician = createTechnician();
        System.runAs(technician) {
            // SETUP
            Fixture fixture = insertFixture(technician, true, false);

            // GIVEN
            System.assertNotEquals(null, fixture.workOrderId, 'The Work Order exists.');

            // WHEN
            CreateProductRequestService.ContextResult context = CreateProductRequestController.getContext(
                fixture.workOrderId,
                technician.Id
            );

            // THEN
            System.assertEquals(
                Label.CreateProductRequest_NoAssignedTechnician,
                context.blockMessage,
                'The screen explains that no Technician is assigned.'
            );
        }
    }

    /**
     * @description Inactive resources and non-Technicians assigned to the Work Order are omitted.
     */
    @IsTest
    static void testGetContextOmitsInactiveAndNonTechnician() {
        User technician = createTechnician();
        User otherUser = createTechnician();
        System.runAs(technician) {
            // SETUP
            Fixture fixture = insertFixture(technician, true, true);
            ServiceResource agent = new ServiceResource(
                Name = 'Agent Resource',
                RelatedRecordId = otherUser.Id,
                IsActive = true,
                ResourceType = 'A'
            );
            insert agent;
            insert new ServiceTerritoryMember(
                ServiceTerritoryId = fixture.serviceTerritoryId,
                ServiceResourceId = agent.Id,
                TerritoryType = 'P',
                EffectiveStartDate = DateTime.now().addDays(-2)
            );
            insert new AssignedResource(
                ServiceAppointmentId = fixture.serviceAppointmentId,
                ServiceResourceId = agent.Id
            );

            // GIVEN
            System.assertNotEquals(null, agent.Id, 'The non-Technician resource exists.');

            // WHEN
            CreateProductRequestService.ContextResult context = CreateProductRequestController.getContext(
                fixture.workOrderId,
                technician.Id
            );

            // THEN
            System.assertEquals(1, context.serviceResources.size(), 'Only the active Technician is listed.');
            System.assertEquals(
                fixture.serviceResourceId,
                context.serviceResources[0].recordId,
                'The listed resource is the assigned Technician.'
            );
        }
    }

    /**
     * @description A Work Order context includes the customer address and required parts.
     */
    @IsTest
    static void testGetContextFromWorkOrder() {
        User technician = createTechnician();
        System.runAs(technician) {
            // SETUP
            Fixture fixture = insertFixture(technician, true);

            // GIVEN
            System.assertNotEquals(null, fixture.workOrderId, 'The Work Order exists before the screen loads.');

            // WHEN
            CreateProductRequestService.ContextResult context = CreateProductRequestController.getContext(
                fixture.workOrderId,
                technician.Id
            );

            // THEN
            System.assertEquals(
                fixture.serviceResourceId,
                context.selectedServiceResourceId,
                'The assigned Technician is selected.'
            );
            System.assertEquals(1, context.serviceResources.size(), 'Only the assigned Technician is listed.');
            System.assertEquals(true, context.hasWorkOrder, 'The Work Order card is available.');
            System.assertEquals('WO subject', context.subject, 'The Work Order subject is returned.');
            System.assertEquals(
                fixture.shipToAccountId,
                context.defaultShipToAccountId,
                'The Work Order ship-to is the default.'
            );
            System.assertEquals(1, context.requiredParts.size(), 'The required part is returned.');
            System.assertEquals(true, context.requiredParts[0].requiredOnWorkOrder, 'The row is marked required.');
            System.assertEquals(2, context.requiredParts[0].quantity, 'The required quantity is returned.');
            System.assertEquals(
                'Seal substitute',
                context.requiredParts[0].substitutePart,
                'The substitute part name is returned.'
            );
            System.assert(
                context.shipToAccounts[0].name.contains('Dock address'),
                'The customer address name is shown.'
            );
            System.assert(
                context.shipToAccounts[0].name.contains('14 Service Road'),
                'The customer street is shown with the name.'
            );
        }
    }

    /**
     * @description A Service Resource record opens a replenishment for that resource.
     */
    @IsTest
    static void testGetContextFromServiceResource() {
        User owner = createTechnician();
        User viewer = createTechnician();
        Fixture fixture;
        System.runAs(owner) {
            fixture = insertFixture(owner, false);
        }
        System.runAs(viewer) {
            // GIVEN
            System.assertNotEquals(null, fixture.serviceResourceId, 'The Service Resource exists.');

            // WHEN
            CreateProductRequestService.ContextResult context = CreateProductRequestController.getContext(
                fixture.serviceResourceId,
                viewer.Id
            );
            CreateProductRequestService.CreateRequest request = baseRequest(viewer.Id, fixture);
            request.workOrderId = fixture.serviceResourceId;
            request.shipToMode = CreateProductRequestService.SHIP_TO_MY_LOCATION;
            request.addressId = fixture.addressId;
            CreateProductRequestService.CreateResult result = CreateProductRequestService.createRequest(request);

            // THEN
            System.assertEquals(false, context.hasWorkOrder, 'The Service Resource screen is a replenishment.');
            System.assertEquals(
                fixture.serviceResourceId,
                context.selectedServiceResourceId,
                'The Service Resource on the record is selected.'
            );
            ProductRequest created = selectProductRequest(result.productRequestId);
            System.assertEquals(null, created.WorkOrderId, 'The replenishment is not linked to a Work Order.');
            System.assertEquals(
                fixture.serviceResourceId,
                created.ServiceResource__c,
                'The Product Request uses the Service Resource from the record.'
            );
        }
    }

    /**
     * @description A standalone save writes the technician address and leaves Work Order fields empty.
     */
    @IsTest
    static void testCreateStandalone() {
        User technician = createTechnician();
        System.runAs(technician) {
            // SETUP
            Fixture fixture = insertFixture(technician, false);
            CreateProductRequestService.CreateRequest request = baseRequest(technician.Id, fixture);
            request.shipToMode = CreateProductRequestService.SHIP_TO_MY_LOCATION;
            request.addressId = fixture.addressId;
            request.needByDate = '2026-11-09T13:00:00.000Z';
            request.lines = null;
            request.linesJson = JSON.serialize(requestLines(fixture.productId, 2));

            // GIVEN
            System.assertEquals(0, countProductRequests(), 'No Product Request exists before save.');

            // WHEN
            CreateProductRequestService.CreateResult result = CreateProductRequestService.createRequest(request);

            // THEN
            ProductRequest created = selectProductRequest(result.productRequestId);
            System.assertEquals(
                fixture.serviceResourceId,
                created.ServiceResource__c,
                'The Service Resource is mapped.'
            );
            System.assertEquals(
                fixture.locationId,
                created.DestinationLocationId,
                'The destination is the resource location.'
            );
            System.assertEquals(
                fixture.addressId,
                created.ShipToTechnicianAddress__c,
                'The selected address is mapped.'
            );
            System.assertEquals(null, created.ShipToAddressAccount__c, 'Customer ship-to stays empty.');
            System.assertEquals(null, created.WorkOrderId, 'A standalone request has no Work Order.');
            System.assertEquals(null, created.AccountId, 'A standalone request has no account.');
            System.assertEquals(null, created.CaseId, 'A standalone request has no case.');
            System.assertEquals('Draft', created.Status, 'The request is saved as Draft.');
            System.assertEquals(SHIPMENT_TYPE, created.ShipmentType, 'The shipment type is saved.');
            System.assertEquals(
                Date.newInstance(2026, 11, 9),
                created.NeedByDate.date(),
                'The delivery date is the selected date.'
            );
            System.assertEquals(8, created.NeedByDate.hour(), 'The need by time is 8 AM.');
            System.assertEquals(null, created.ShipToStreet, 'The standard ship-to address stays empty.');
            System.assertEquals(false, created.ShipSet__c, 'Ship Set defaults to false.');
            System.assertEquals(false, selectLines(created.Id)[0].ShipSet__c, 'The line Ship Set defaults to false.');
            System.assertEquals(1, selectLines(created.Id).size(), 'One line is created.');
            System.assertEquals(2, selectLines(created.Id)[0].QuantityRequested, 'The entered quantity is saved.');
            System.assertEquals(
                'Seal kit description',
                selectLines(created.Id)[0].Description,
                'The product description is copied to the line.'
            );
            System.assertEquals(
                'Each',
                selectLines(created.Id)[0].QuantityUnitOfMeasure,
                'The product unit is copied.'
            );
            System.assertNotEquals(null, result.productRequestNumber, 'The Product Request number is returned.');
        }
    }

    /**
     * @description A Product Request Ship Set checks every line, even a line left unchecked.
     */
    @IsTest
    static void testCreateShipSetChecksEveryLine() {
        User technician = createTechnician();
        System.runAs(technician) {
            // SETUP
            Fixture fixture = insertFixture(technician, false);
            CreateProductRequestService.CreateRequest request = baseRequest(technician.Id, fixture);
            request.shipToMode = CreateProductRequestService.SHIP_TO_MY_LOCATION;
            request.addressId = fixture.addressId;
            request.shipSet = true;
            CreateProductRequestService.LineRequest secondLine = new CreateProductRequestService.LineRequest();
            secondLine.productId = fixture.secondProductId;
            secondLine.quantity = 1;
            secondLine.shipSet = false;
            request.lines.add(secondLine);

            // GIVEN
            System.assertEquals(true, request.shipSet, 'The Product Request Ship Set is selected.');
            System.assertEquals(false, secondLine.shipSet, 'One line was left unchecked.');

            // WHEN
            CreateProductRequestService.CreateResult result = CreateProductRequestService.createRequest(request);

            // THEN
            ProductRequest created = selectProductRequest(result.productRequestId);
            System.assertEquals(true, created.ShipSet__c, 'The Product Request is saved as a ship set.');
            System.assertEquals(2, selectLines(created.Id).size(), 'Both parts are saved.');
            for (ProductRequestLineItem line : selectLines(created.Id)) {
                System.assertEquals(true, line.ShipSet__c, 'A header ship set checks every line.');
            }
        }
    }

    /**
     * @description A line Ship Set is saved when the Product Request Ship Set stays off.
     */
    @IsTest
    static void testCreateLineShipSet() {
        User technician = createTechnician();
        System.runAs(technician) {
            // SETUP
            Fixture fixture = insertFixture(technician, false);
            CreateProductRequestService.CreateRequest request = baseRequest(technician.Id, fixture);
            request.shipToMode = CreateProductRequestService.SHIP_TO_MY_LOCATION;
            request.addressId = fixture.addressId;
            request.shipSet = false;
            request.lines[0].shipSet = true;

            // GIVEN
            System.assertEquals(false, request.shipSet, 'The Product Request Ship Set is off.');

            // WHEN
            CreateProductRequestService.CreateResult result = CreateProductRequestService.createRequest(request);

            // THEN
            System.assertEquals(false, selectProductRequest(result.productRequestId).ShipSet__c, 'The header stays off.');
            System.assertEquals(true, selectLines(result.productRequestId)[0].ShipSet__c, 'The line Ship Set is saved.');
        }
    }

    /**
     * @description The JSON posted by the mobile screen keeps the date and the entered quantity.
     */
    @IsTest
    static void testCreateFromJson() {
        User technician = createTechnician();
        System.runAs(technician) {
            // SETUP
            Fixture fixture = insertFixture(technician, false);
            CreateProductRequestService.CreateRequest request = baseRequest(technician.Id, fixture);
            request.shipToMode = CreateProductRequestService.SHIP_TO_MY_LOCATION;
            request.addressId = fixture.addressId;
            request.needByDate = '2026-11-09';
            request.lines = requestLines(fixture.productId, 3);
            request.linesJson = JSON.serialize(request.lines);

            // GIVEN
            String requestJson = JSON.serialize(request);
            System.assertEquals(3, request.lines[0].quantity, 'The JSON payload quantity is 3.');

            // WHEN
            CreateProductRequestService.CreateResult result =
                CreateProductRequestController.createProductRequestFromJson(requestJson);

            // THEN
            ProductRequest created = selectProductRequest(result.productRequestId);
            System.assertEquals(
                Date.newInstance(2026, 11, 9),
                created.NeedByDate.date(),
                'The delivery date is the selected date.'
            );
            System.assertEquals(3, selectLines(created.Id)[0].QuantityRequested, 'The entered quantity is saved.');
        }
    }

    /**
     * @description Save without a Need By Date is rejected.
     */
    @IsTest
    static void testCreateRejectsBlankNeedByDate() {
        User technician = createTechnician();
        System.runAs(technician) {
            // SETUP
            Fixture fixture = insertFixture(technician, false);
            CreateProductRequestService.CreateRequest request = baseRequest(technician.Id, fixture);
            request.shipToMode = CreateProductRequestService.SHIP_TO_MY_LOCATION;
            request.addressId = fixture.addressId;
            request.needByDate = null;

            // GIVEN
            System.assertEquals(null, request.needByDate, 'Need By Date is blank.');

            // WHEN
            AuraHandledException thrownError;
            try {
                CreateProductRequestController.createProductRequest(request);
            } catch (AuraHandledException e) {
                thrownError = e;
            }

            // THEN
            System.assertNotEquals(null, thrownError, 'Save is rejected.');
            System.assertEquals(
                Label.CreateProductRequest_DeliveryDateRequired,
                thrownError.getMessage(),
                'A Need By Date is required.'
            );
            System.assertEquals(0, countProductRequests(), 'No Product Request is left behind.');
        }
    }

    /**
     * @description A Work Order save writes the customer account and the Work Order references.
     */
    @IsTest
    static void testCreateFromWorkOrder() {
        User technician = createTechnician();
        System.runAs(technician) {
            // SETUP
            Fixture fixture = insertFixture(technician, true);
            CreateProductRequestService.CreateRequest request = baseRequest(technician.Id, fixture);
            request.workOrderId = fixture.workOrderId;
            request.shipToMode = CreateProductRequestService.SHIP_TO_CUSTOMER;
            request.shipToAccountId = fixture.shipToAccountId;

            // GIVEN
            System.assertEquals(0, countProductRequests(), 'No Product Request exists before save.');

            // WHEN
            CreateProductRequestService.CreateResult result =
                CreateProductRequestController.createProductRequest(request);

            // THEN
            ProductRequest created = selectProductRequest(result.productRequestId);
            System.assertEquals(fixture.workOrderId, created.WorkOrderId, 'The Work Order is mapped.');
            System.assertEquals(fixture.accountId, created.AccountId, 'The Work Order account is mapped.');
            System.assertEquals(
                fixture.shipToAccountId,
                created.ShipToAddressAccount__c,
                'The customer account is mapped.'
            );
            System.assertEquals(null, created.ShipToTechnicianAddress__c, 'The technician address stays empty.');
            ProductRequestLineItem line = selectLines(created.Id)[0];
            System.assertEquals(fixture.workOrderId, line.WorkOrderId, 'The line keeps the Work Order.');
            System.assertEquals(fixture.accountId, line.AccountId, 'The line keeps the account.');
            System.assertEquals(created.Id, line.ParentId, 'The line parent is the new Product Request.');
        }
    }

    /**
     * @description Yes on the second screen sets Submission to ERP to Submit Create.
     */
    @IsTest
    static void testSubmitToErp() {
        User technician = createTechnician();
        System.runAs(technician) {
            // SETUP
            Fixture fixture = insertFixture(technician, false);
            CreateProductRequestService.CreateRequest request = baseRequest(technician.Id, fixture);
            request.shipToMode = CreateProductRequestService.SHIP_TO_MY_LOCATION;
            request.addressId = fixture.addressId;
            CreateProductRequestService.CreateResult created = CreateProductRequestService.createRequest(request);

            // GIVEN
            System.assertEquals(
                null,
                selectProductRequest(created.productRequestId).SubmissionToERP__c,
                'The request is not submitted before the technician confirms.'
            );

            // WHEN
            CreateProductRequestController.submitProductRequest(created.productRequestId);

            // THEN
            System.assertEquals(
                'Submit Create',
                selectProductRequest(created.productRequestId).SubmissionToERP__c,
                'The Product Request is marked for Oracle.'
            );
        }
    }

    /**
     * @description Save without a part is rejected.
     */
    @IsTest
    static void testCreateRejectsEmptyParts() {
        User technician = createTechnician();
        System.runAs(technician) {
            // SETUP
            Fixture fixture = insertFixture(technician, false);
            CreateProductRequestService.CreateRequest request = baseRequest(technician.Id, fixture);
            request.shipToMode = CreateProductRequestService.SHIP_TO_MY_LOCATION;
            request.addressId = fixture.addressId;
            request.lines = new List<CreateProductRequestService.LineRequest>();

            // GIVEN
            System.assertEquals(0, request.lines.size(), 'The request has no parts.');

            // WHEN
            AuraHandledException thrownError;
            try {
                CreateProductRequestController.createProductRequest(request);
            } catch (AuraHandledException e) {
                thrownError = e;
            }

            // THEN
            System.assertNotEquals(null, thrownError, 'Save is rejected.');
            System.assertEquals(
                Label.CreateProductRequest_PartsRequired,
                thrownError.getMessage(),
                'The parts message is returned.'
            );
            System.assertEquals(0, countProductRequests(), 'No Product Request is left behind.');
        }
    }

    /**
     * @description Part search matches name or code and skips products that are not active parts.
     */
    @IsTest
    static void testSearchParts() {
        User technician = createTechnician();
        System.runAs(technician) {
            // SETUP
            Product2 substitute = insertProduct('Seal substitute', 'PC-SUB', 'Part', true);
            Product2 part = insertProduct('Seal kit', 'PC-4471', 'Part', true);
            part.SubstitutePart__c = substitute.Id;
            update part;
            insertProduct('Finished unit', 'PC-4471-FG', 'Finished Good', true);
            insertProduct('Inactive seal', 'PC-4471-OLD', 'Part', false);

            // GIVEN
            System.assertEquals(4, countProducts(), 'Four products exist before the search.');

            // WHEN
            List<CreateProductRequestService.PartRow> matches = CreateProductRequestController.searchParts('PC-4471');

            // THEN
            System.assertEquals(1, matches.size(), 'Only the active Part matches.');
            System.assertEquals('Seal kit', matches[0].name, 'The product name is returned.');
            System.assertEquals('PC-4471', matches[0].productCode, 'The product code is returned.');
            System.assertEquals(
                'Seal substitute',
                matches[0].substitutePart,
                'The substitute part name is returned.'
            );
        }
    }

    /**
     * @description One save can insert 200 line items.
     */
    @IsTest
    static void testCreateBulkLines() {
        User technician = createTechnician();
        System.runAs(technician) {
            // SETUP
            Fixture fixture = insertFixture(technician, false);
            List<Product2> extraProducts = new List<Product2>();
            for (Integer index = 0; index < 200; index++) {
                extraProducts.add(newProduct('Bulk ' + index, 'BULK-' + index, 'Part', true));
            }
            insert extraProducts;
            CreateProductRequestService.CreateRequest request = baseRequest(technician.Id, fixture);
            request.shipToMode = CreateProductRequestService.SHIP_TO_MY_LOCATION;
            request.addressId = fixture.addressId;
            request.lines = new List<CreateProductRequestService.LineRequest>();
            for (Product2 product : extraProducts) {
                CreateProductRequestService.LineRequest line = new CreateProductRequestService.LineRequest();
                line.productId = product.Id;
                line.quantity = 1;
                request.lines.add(line);
            }

            // GIVEN
            System.assertEquals(200, request.lines.size(), 'The save contains 200 parts.');

            // WHEN
            CreateProductRequestService.CreateResult result = CreateProductRequestService.createRequest(request);

            // THEN
            System.assertEquals(200, selectLines(result.productRequestId).size(), 'All 200 lines are created.');
        }
    }

    /**
     * @description An address reload for a resource the user does not own is rejected.
     */
    @IsTest
    static void testGetAddressesRejectsUnknownResource() {
        User technician = createTechnician();
        System.runAs(technician) {
            // GIVEN
            Boolean thrown = false;

            // WHEN
            try {
                CreateProductRequestController.getAddresses(technician.Id, technician.Id, null);
            } catch (AuraHandledException e) {
                thrown = true;
                System.assertEquals(
                    Label.CreateProductRequest_ServiceResourceInvalid,
                    e.getMessage(),
                    'An unknown Service Resource is rejected.'
                );
            }

            // THEN
            System.assertEquals(true, thrown, 'The address load is rejected.');
        }
    }

    /**
     * @description Existing selector methods stay covered when this change is deployed with them.
     */
    @IsTest
    static void testExistingSelectorMethods() {
        User technician = createTechnician();
        System.runAs(technician) {
            // SETUP
            Fixture fixture = insertFixture(technician, true);
            Set<Id> productIds = new Set<Id>{ fixture.productId };
            Set<String> productCodes = new Set<String>{ 'PC-4471' };
            Set<Id> workOrderIds = new Set<Id>{ fixture.workOrderId };

            // GIVEN
            System.assertNotEquals(null, fixture.workOrderId, 'The fixture includes a Work Order.');

            // WHEN
            Product2Selector.selectPsamByIds(null);
            Product2Selector.selectPsamByIds(productIds);
            Product2Selector.selectActiveBySearchKey('Seal');
            Product2Selector.selectActiveByIds(null);
            Product2Selector.selectActiveByIds(productIds);
            Product2Selector.selectPricingSourceByProductCodes(null);
            Product2Selector.selectPricingSourceByProductCodes(productCodes);
            Product2Selector.selectIdsByProductCodes(null);
            Product2Selector.selectIdsByProductCodes(productCodes);
            Product2Selector.selectSellingModelOptionsByProductIds(null);
            Product2Selector.selectSellingModelOptionsByProductIds(productIds);
            Product2Selector.selectOneTimeSellingModelId();
            new Product2Selector();
            WorkOrderSelector.selectByIdsForAllowedUnit(null);
            runSecuredQuery(workOrderIds, technician.Id);
            WorkOrderSelector.selectByIdsForRateList(null);
            WorkOrderSelector.selectForProductRequest(null);
            ServiceResourcesSelector.selectActiveWithRepairCenterByUserId(null);
            ServiceResourcesSelector.selectActiveByRelatedRecordIds(null);
            ServiceResourcesSelector.selectActiveByRelatedRecordIds(new Set<Id>{ technician.Id });
            ServiceResourcesSelector.selectActiveTechniciansByIds(null);
            ServiceResourcesSelector.selectActiveTechniciansByIds(new Set<Id>{ fixture.serviceResourceId });
            AssignedResourcesSelector.selectByWorkOrderId(null);
            AssignedResourcesSelector.selectByWorkOrderId(fixture.workOrderId);
            new ServiceResourcesSelector();
            new AssignedResourcesSelector();
            CreateProductRequestException error = CreateProductRequestException.withMessage('blocked');

            // THEN
            System.assertEquals('blocked', error.getMessage(), 'The exception carries the user message.');
        }
    }

    private static void runSecuredQuery(Set<Id> workOrderIds, Id userId) {
        try {
            WorkOrderSelector.selectByIdsForAllowedUnit(workOrderIds);
        } catch (QueryException e) {
            System.assertNotEquals(null, e.getMessage(), 'Allowed unit query enforces field access.');
        }
        try {
            WorkOrderSelector.selectByIdsForRateList(workOrderIds);
        } catch (QueryException e) {
            System.assertNotEquals(null, e.getMessage(), 'Rate list query enforces field access.');
        }
        try {
            WorkOrderSelector.selectWorkOrdersWithOperatingHours(workOrderIds);
        } catch (QueryException e) {
            System.assertNotEquals(null, e.getMessage(), 'Operating hours query enforces field access.');
        }
        WorkOrderSelector.selectOperatingHoursHolidays(new Set<Id>());
        try {
            ServiceResourcesSelector.selectActiveWithRepairCenterByUserId(userId);
        } catch (QueryException e) {
            System.assertNotEquals(null, e.getMessage(), 'Repair center query enforces field access.');
        }
    }

    private static List<CreateProductRequestService.LineRequest> requestLines(Id productId, Decimal quantity) {
        CreateProductRequestService.LineRequest line = new CreateProductRequestService.LineRequest();
        line.productId = productId;
        line.quantity = quantity;
        return new List<CreateProductRequestService.LineRequest>{ line };
    }

    private static CreateProductRequestService.CreateRequest baseRequest(Id userId, Fixture fixture) {
        CreateProductRequestService.CreateRequest request = new CreateProductRequestService.CreateRequest();
        request.userId = userId;
        request.serviceResourceId = fixture.serviceResourceId;
        request.needByDate = '2026-11-05T13:00:00.000Z';
        request.shipmentType = SHIPMENT_TYPE;
        request.lines = new List<CreateProductRequestService.LineRequest>();
        CreateProductRequestService.LineRequest line = new CreateProductRequestService.LineRequest();
        line.productId = fixture.productId;
        line.quantity = 2;
        request.lines.add(line);
        return request;
    }

    private static Fixture insertFixture(User technician, Boolean withWorkOrder) {
        return insertFixture(technician, withWorkOrder, withWorkOrder);
    }

    private static Fixture insertFixture(User technician, Boolean withWorkOrder, Boolean assignResource) {
        Schema.Location resourceLocation = new Schema.Location(
            Name = 'Van 14',
            LocationType = 'Technician Vehicle',
            IsInventoryLocation = true,
            IsMobile = true
        );
        insert resourceLocation;

        Schema.Address technicianAddress = new Schema.Address(
            ParentId = resourceLocation.Id,
            LocationType = 'Technician Vehicle',
            AddressType = 'Shipping',
            Street = '14 Service Road',
            City = 'Mentor',
            StateCode = 'OH',
            PostalCode = '44060',
            CountryCode = 'US'
        );
        insert technicianAddress;
        Schema.Address storedAddress = (Schema.Address) SoqlQueryBuilder.fromObject('Address')
            .selectFields(new List<String>{ 'Name', 'AddressShipTo__c' })
            .whereEquals('Id', technicianAddress.Id)
            .first();
        resourceLocation.VisitorAddressId = technicianAddress.Id;
        update resourceLocation;

        ServiceResource technicianResource = new ServiceResource(
            Name = 'J. Rivera',
            RelatedRecordId = technician.Id,
            IsActive = true,
            ResourceType = 'T',
            LocationId = resourceLocation.Id
        );
        insert technicianResource;

        Product2 substitute = insertProduct('Seal substitute', 'PC-SUB', 'Part', true);
        Product2 part = insertProduct('Seal kit', 'PC-4471', 'Part', true);
        part.SubstitutePart__c = substitute.Id;
        update part;
        Fixture fixture = new Fixture();
        fixture.locationId = resourceLocation.Id;
        fixture.addressId = technicianAddress.Id;
        fixture.addressName = String.isBlank(storedAddress.AddressShipTo__c)
            ? storedAddress.Name
            : storedAddress.AddressShipTo__c;
        fixture.serviceResourceId = technicianResource.Id;
        fixture.productId = part.Id;
        fixture.secondProductId = substitute.Id;

        if (withWorkOrder) {
            Account customer = new Account(Name = 'Sterilizer Customer');
            insert customer;
            Account shipTo = new Account(
                Name = 'Dock address',
                ParentId = customer.Id,
                Type = 'Address',
                ShiptoAddressStatus__c = 'Active',
                BillingStreet = '14 Service Road',
                BillingCity = 'Mentor'
            );
            insert shipTo;
            WorkOrder workOrder = new WorkOrder(
                Subject = 'WO subject',
                AccountId = customer.Id,
                ShipToAddressAccount__c = shipTo.Id
            );
            insert workOrder;
            insert new ProductRequired(
                ParentRecordId = workOrder.Id,
                Product2Id = part.Id,
                QuantityRequired = 2,
                QuantityUnitOfMeasure = 'Each'
            );
            fixture.workOrderId = workOrder.Id;
            fixture.accountId = customer.Id;
            fixture.shipToAccountId = shipTo.Id;
            fixture.shipToAccountCount = 1;
            if (assignResource) {
                OperatingHours hours = new OperatingHours(
                    Name = 'CPR Hours ' + technicianResource.Id,
                    TimeZone = 'America/New_York'
                );
                insert hours;
                ServiceTerritory territory = new ServiceTerritory(
                    Name = 'CPR Territory ' + technicianResource.Id,
                    IsActive = true,
                    OperatingHoursId = hours.Id
                );
                insert territory;
                insert new ServiceTerritoryMember(
                    ServiceTerritoryId = territory.Id,
                    ServiceResourceId = technicianResource.Id,
                    TerritoryType = 'P',
                    EffectiveStartDate = DateTime.now().addDays(-2)
                );
                fixture.serviceTerritoryId = territory.Id;
                DateTime scheduledStart = DateTime.now().addHours(1);
                ServiceAppointment appointment = new ServiceAppointment(
                    ParentRecordId = workOrder.Id,
                    ServiceTerritoryId = territory.Id,
                    EarliestStartTime = DateTime.now(),
                    DueDate = DateTime.now().addDays(1),
                    SchedStartTime = scheduledStart,
                    SchedEndTime = scheduledStart.addHours(1)
                );
                insert appointment;
                insert new AssignedResource(
                    ServiceAppointmentId = appointment.Id,
                    ServiceResourceId = technicianResource.Id
                );
                fixture.serviceAppointmentId = appointment.Id;
            }
        }
        return fixture;
    }

    private static Product2 insertProduct(String name, String productCode, String productType, Boolean isActive) {
        Product2 product = newProduct(name, productCode, productType, isActive);
        insert product;
        return product;
    }

    private static Product2 newProduct(String name, String productCode, String productType, Boolean isActive) {
        return new Product2(
            Name = name,
            ProductCode = productCode,
            IsActive = isActive,
            ProductType__c = productType,
            QuantityUnitOfMeasure = 'Each',
            Description = name + ' description'
        );
    }

    private static Integer technicianSequence = 0;

    private static User createTechnician() {
        technicianSequence++;
        Profile adminProfile = (Profile) SoqlQueryBuilder.fromObject('Profile')
            .selectField('Id')
            .whereEquals('Name', 'System Administrator')
            .first();
        String uniqueKey = String.valueOf(DateTime.now().getTime()) + technicianSequence;
        String uniqueName = 'cpr' + uniqueKey + '@example.com';
        User technician = new User(
            Alias = 'cprtech',
            Email = uniqueName,
            EmailEncodingKey = 'UTF-8',
            LastName = 'ProductRequest',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = adminProfile.Id,
            TimeZoneSidKey = 'America/New_York',
            Username = uniqueName
        );
        insert technician;
        PermissionSet permissionSet = (PermissionSet) SoqlQueryBuilder.fromObject('PermissionSet')
            .selectField('Id')
            .whereEquals('Name', 'ManageProductRequests')
            .first();
        PermissionSet fieldAccess = new PermissionSet(
            Name = 'CprFields' + uniqueKey,
            Label = 'CPR Fields ' + uniqueKey
        );
        insert fieldAccess;
        insert fieldRead(fieldAccess.Id, 'Address', 'Address.AddressShipTo__c');
        insert fieldRead(fieldAccess.Id, 'ServiceResource', 'ServiceResource.TechnicianType__c');
        insert fieldRead(fieldAccess.Id, 'WorkOrder', 'WorkOrder.ShipToAddressAccount__c');
        insert fieldRead(fieldAccess.Id, 'Account', 'Account.ShiptoAddressStatus__c');
        insert fieldRead(fieldAccess.Id, 'Product2', 'Product2.SubstitutePart__c');
        insert fieldRead(fieldAccess.Id, 'ProductRequest', 'ProductRequest.ShipSet__c');
        insert fieldRead(fieldAccess.Id, 'ProductRequestLineItem', 'ProductRequestLineItem.ShipSet__c');
        insert new List<PermissionSetAssignment>{
            new PermissionSetAssignment(AssigneeId = technician.Id, PermissionSetId = permissionSet.Id),
            new PermissionSetAssignment(AssigneeId = technician.Id, PermissionSetId = fieldAccess.Id)
        };
        return technician;
    }

    private static FieldPermissions fieldRead(Id permissionSetId, String objectName, String fieldName) {
        return new FieldPermissions(
            ParentId = permissionSetId,
            SobjectType = objectName,
            Field = fieldName,
            PermissionsRead = true,
            PermissionsEdit = false
        );
    }

    private static ProductRequest selectProductRequest(Id productRequestId) {
        return (ProductRequest) SoqlQueryBuilder.fromObject('ProductRequest')
            .selectFields(new List<String>{
                'Id',
                'ProductRequestNumber',
                'Status',
                'ShipmentType',
                'ServiceResource__c',
                'DestinationLocationId',
                'ShipToTechnicianAddress__c',
                'ShipToAddressAccount__c',
                'WorkOrderId',
                'AccountId',
                'CaseId',
                'NeedByDate',
                'ShipToStreet',
                'ShipSet__c',
                'SubmissionToERP__c'
            })
            .whereEquals('Id', productRequestId)
            .first();
    }

    private static List<ProductRequestLineItem> selectLines(Id productRequestId) {
        return (List<ProductRequestLineItem>) SoqlQueryBuilder.fromObject('ProductRequestLineItem')
            .selectFields(new List<String>{
                'Id',
                'ParentId',
                'Product2Id',
                'QuantityRequested',
                'QuantityUnitOfMeasure',
                'Description',
                'NeedByDate',
                'ShipSet__c',
                'WorkOrderId',
                'AccountId',
                'Status'
            })
            .whereEquals('ParentId', productRequestId)
            .execute();
    }

    private static Integer countProductRequests() {
        return SoqlQueryBuilder.fromObject('ProductRequest').count();
    }

    private static Integer countProducts() {
        return SoqlQueryBuilder.fromObject('Product2').count();
    }

    private class Fixture {
        public Id locationId;
        public Id addressId;
        public String addressName;
        public Id serviceResourceId;
        public Id serviceAppointmentId;
        public Id serviceTerritoryId;
        public Id productId;
        public Id secondProductId;
        public Id workOrderId;
        public Id accountId;
        public Id shipToAccountId;
        public Integer shipToAccountCount = 0;
    }
}