/**
 * @description Tests for IMS debrief truck appointment assignment.
 * @see WoDebriefIMSController
 */
@IsTest
private class WoDebriefIMSControllerTest {
    /**
     * @description Rejects a call that is missing either appointment.
     */
    @IsTest
    static void createTruckAppointmentDependency_missingAppointment_throws() {
        Boolean threw = false;
        try {
            WoDebriefIMSController.createTruckAppointmentDependency(null, null);
        } catch (AuraHandledException ex) {
            threw = true;
        }
        System.assertEquals(true, threw, 'A missing appointment should be rejected.');
    }

    /**
     * @description Inserts a Same Start dependency between two service appointments.
     */
    @IsTest
    static void createTruckAppointmentDependency_insertsSameStart() {
        Account account = new Account(Name = 'Truck Dependency Account');
        insert account;
        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            Subject = 'Truck Dependency WO'
        );
        insert workOrder;

        Datetime startTime = Datetime.now().addDays(1);
        Datetime endTime = startTime.addHours(2);
        ServiceAppointment technicianAppointment = new ServiceAppointment(
            ParentRecordId = workOrder.Id,
            Subject = 'Technician',
            EarliestStartTime = startTime,
            DueDate = endTime,
            SchedStartTime = startTime,
            SchedEndTime = endTime,
            Duration = 2,
            DurationType = 'Hours'
        );
        ServiceAppointment truckAppointment = technicianAppointment.clone(false, true, false, false);
        truckAppointment.Subject = 'Truck';
        truckAppointment.TruckAppointment__c = true;
        insert new List<ServiceAppointment>{ technicianAppointment, truckAppointment };

        Test.startTest();
        Id dependencyId = WoDebriefIMSController.createTruckAppointmentDependency(
            technicianAppointment.Id,
            truckAppointment.Id
        );
        Test.stopTest();

        FSL__Time_Dependency__c dependency = [
            SELECT FSL__Service_Appointment_1__c, FSL__Service_Appointment_2__c, FSL__Dependency__c, FSL__Same_Resource__c
            FROM FSL__Time_Dependency__c
            WHERE Id = :dependencyId
        ];
        System.assertEquals(technicianAppointment.Id, dependency.FSL__Service_Appointment_1__c);
        System.assertEquals(truckAppointment.Id, dependency.FSL__Service_Appointment_2__c);
        System.assertEquals('Same Start', dependency.FSL__Dependency__c);
        System.assertEquals(false, dependency.FSL__Same_Resource__c);
    }

    /**
     * @description Rejects a call that is missing the truck and both appointments.
     */
    @IsTest
    static void assignSelectedTruck_missingIds_throws() {
        Boolean threw = false;
        try {
            WoDebriefIMSController.assignSelectedTruck(null, null, null);
        } catch (AuraHandledException ex) {
            threw = true;
        }
        System.assertEquals(true, threw, 'A missing truck and appointment should be rejected.');
    }

    /**
     * @description Rejects a technician appointment that has no scheduled start and end.
     */
    @IsTest
    static void assignSelectedTruck_missingSchedule_throws() {
        Account account = new Account(Name = 'Truck Unscheduled Account');
        insert account;
        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            Subject = 'Truck Unscheduled WO'
        );
        insert workOrder;
        Datetime startTime = Datetime.now().addDays(1);
        ServiceAppointment technician = new ServiceAppointment(
            ParentRecordId = workOrder.Id,
            Subject = 'Unscheduled',
            EarliestStartTime = startTime,
            DueDate = startTime.addHours(2)
        );
        insert technician;

        Boolean threw = false;
        Test.startTest();
        try {
            WoDebriefIMSController.assignSelectedTruck(
                technician.Id,
                null,
                ServiceResource.SObjectType.getDescribe().getKeyPrefix() + '000000000001'
            );
        } catch (AuraHandledException ex) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw, 'An unscheduled appointment should be rejected.');
    }

    /**
     * @description Creates a truck appointment, assigns the truck, and stamps the technician appointment.
     */
    @IsTest
    static void assignSelectedTruck_createsTruckAppointment() {
        TruckFixture fixture = insertFixture();

        Test.startTest();
        Id truckAppointmentId = WoDebriefIMSController.assignSelectedTruck(
            fixture.technicianAppointmentId,
            null,
            fixture.serviceResourceId
        );
        Test.stopTest();

        ServiceAppointment truck = [
            SELECT ParentRecordId, TruckAppointment__c, SchedStartTime, SchedEndTime, ServiceTerritoryId
            FROM ServiceAppointment
            WHERE Id = :truckAppointmentId
        ];
        System.assertEquals(fixture.workOrderId, truck.ParentRecordId);
        System.assertEquals(true, truck.TruckAppointment__c);
        assertSameMinute(fixture.startTime, truck.SchedStartTime);
        assertSameMinute(fixture.endTime, truck.SchedEndTime);
        System.assertEquals(fixture.territoryId, truck.ServiceTerritoryId);

        List<AssignedResource> assigned = [
            SELECT ServiceResourceId
            FROM AssignedResource
            WHERE ServiceAppointmentId = :truckAppointmentId
        ];
        System.assertEquals(1, assigned.size(), 'The truck appointment should have one assigned resource.');
        System.assertEquals(fixture.serviceResourceId, assigned[0].ServiceResourceId);

        ServiceAppointment technician = [
            SELECT Truck__c
            FROM ServiceAppointment
            WHERE Id = :fixture.technicianAppointmentId
        ];
        System.assertEquals(fixture.serviceResourceId, technician.Truck__c);

        List<FSL__Time_Dependency__c> dependencies = [
            SELECT Id
            FROM FSL__Time_Dependency__c
            WHERE FSL__Service_Appointment_1__c = :fixture.technicianAppointmentId
            AND FSL__Service_Appointment_2__c = :truckAppointmentId
            AND FSL__Dependency__c = 'Same Start'
        ];
        System.assertEquals(1, dependencies.size(), 'The truck should start with the technician.');
    }

    /**
     * @description Assigns the truck on an existing truck appointment instead of creating another.
     */
    @IsTest
    static void assignSelectedTruck_reassignsExistingTruckAppointment() {
        TruckFixture fixture = insertFixture();
        ServiceAppointment existing = new ServiceAppointment(
            ParentRecordId = fixture.workOrderId,
            Subject = 'Truck',
            TruckAppointment__c = true,
            EarliestStartTime = fixture.startTime,
            DueDate = fixture.endTime,
            SchedStartTime = fixture.startTime,
            SchedEndTime = fixture.endTime,
            Duration = 2,
            DurationType = 'Hours',
            ServiceTerritoryId = fixture.territoryId
        );
        insert existing;

        Test.startTest();
        Id truckAppointmentId = WoDebriefIMSController.assignSelectedTruck(
            fixture.technicianAppointmentId,
            existing.Id,
            fixture.serviceResourceId
        );
        WoDebriefIMSController.assignSelectedTruck(
            fixture.technicianAppointmentId,
            existing.Id,
            fixture.serviceResourceId
        );
        Test.stopTest();

        System.assertEquals(existing.Id, truckAppointmentId);
        Integer truckCount = [
            SELECT COUNT()
            FROM ServiceAppointment
            WHERE ParentRecordId = :fixture.workOrderId
            AND TruckAppointment__c = TRUE
        ];
        System.assertEquals(1, truckCount, 'Reassign should not create a second truck appointment.');
        Integer assignedCount = [
            SELECT COUNT()
            FROM AssignedResource
            WHERE ServiceAppointmentId = :existing.Id
        ];
        System.assertEquals(1, assignedCount, 'Calling again with the same truck should keep one assigned resource.');
    }

    /**
     * @description Copies the technician schedule onto a truck appointment that has no schedule.
     */
    @IsTest
    static void assignSelectedTruck_copiesScheduleOntoUnscheduledTruck() {
        TruckFixture fixture = insertFixture();
        ServiceAppointment existing = new ServiceAppointment(
            ParentRecordId = fixture.workOrderId,
            Subject = 'Truck',
            TruckAppointment__c = true,
            EarliestStartTime = fixture.startTime,
            DueDate = fixture.endTime,
            ServiceTerritoryId = fixture.territoryId
        );
        insert existing;

        Test.startTest();
        Id truckAppointmentId = WoDebriefIMSController.assignSelectedTruck(
            fixture.technicianAppointmentId,
            existing.Id,
            fixture.serviceResourceId
        );
        Test.stopTest();

        System.assertEquals(existing.Id, truckAppointmentId);
        ServiceAppointment truck = [
            SELECT SchedStartTime, SchedEndTime
            FROM ServiceAppointment
            WHERE Id = :existing.Id
        ];
        assertSameMinute(fixture.startTime, truck.SchedStartTime);
        assertSameMinute(fixture.endTime, truck.SchedEndTime);
    }

    /**
     * @description Compares date-times to the minute. Scheduling clears seconds.
     */
    private static void assertSameMinute(Datetime expected, Datetime actual) {
        System.assertNotEquals(null, actual, 'A scheduled time should be saved.');
        System.assertEquals(expected.year(), actual.year());
        System.assertEquals(expected.month(), actual.month());
        System.assertEquals(expected.day(), actual.day());
        System.assertEquals(expected.hour(), actual.hour());
        System.assertEquals(expected.minute(), actual.minute());
    }

    /**
     * @description Inserts a scheduled technician appointment and an active truck resource in its territory.
     * @return Ids used by the assignment tests
     */
    private static TruckFixture insertFixture() {
        String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        Account account = new Account(Name = 'Truck Assign Account ' + suffix);
        insert account;
        OperatingHours hours = new OperatingHours(
            Name = 'Truck Hours ' + suffix,
            TimeZone = 'America/New_York'
        );
        insert hours;
        ServiceTerritory territory = new ServiceTerritory(
            Name = 'Truck Territory ' + suffix,
            OperatingHoursId = hours.Id,
            IsActive = true
        );
        insert territory;
        ServiceResource resource = new ServiceResource(
            Name = 'Truck Resource ' + suffix,
            IsActive = true,
            RelatedRecordId = UserInfo.getUserId(),
            TechnicianType__c = 'Truck',
            ExternalID__c = 'TRUCK-' + suffix
        );
        insert resource;
        insert new ServiceTerritoryMember(
            ServiceTerritoryId = territory.Id,
            ServiceResourceId = resource.Id,
            TerritoryType = 'P',
            EffectiveStartDate = Datetime.now().addDays(-5)
        );
        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            Subject = 'Truck Assign WO',
            ServiceTerritoryId = territory.Id
        );
        insert workOrder;
        Datetime startTime = Datetime.now().addDays(2);
        Datetime endTime = startTime.addHours(2);
        ServiceAppointment technician = new ServiceAppointment(
            ParentRecordId = workOrder.Id,
            Subject = 'Technician',
            EarliestStartTime = startTime,
            DueDate = endTime,
            SchedStartTime = startTime,
            SchedEndTime = endTime,
            Duration = 2,
            DurationType = 'Hours',
            ServiceTerritoryId = territory.Id
        );
        insert technician;

        TruckFixture fixture = new TruckFixture();
        fixture.workOrderId = workOrder.Id;
        fixture.territoryId = territory.Id;
        fixture.technicianAppointmentId = technician.Id;
        fixture.serviceResourceId = resource.Id;
        fixture.startTime = startTime;
        fixture.endTime = endTime;
        return fixture;
    }

    /**
     * @description GW-1353 - An open child work order blocks site visit completion.
     */
    @IsTest
    static void checkSiteVisitReview_openChild_blocks() {
        Account account = new Account(Name = 'Site Complete Open');
        insert account;
        WorkOrder siteVisit = new WorkOrder(AccountId = account.Id, Subject = 'Site Complete Open', Status = 'New');
        insert siteVisit;
        WorkOrder child = new WorkOrder(
            AccountId = account.Id,
            ParentWorkOrderId = siteVisit.Id,
            Subject = 'Open Child',
            Status = 'In Progress'
        );
        insert child;

        Test.startTest();
        WoDebriefIMSController.SiteVisitReviewResult result =
            WoDebriefIMSController.checkSiteVisitReview(siteVisit.Id);
        Test.stopTest();

        System.assertEquals(false, result.canFinish);
        System.assertEquals(1, result.openWorkOrders.size());
        System.assertEquals('In Progress', [SELECT Status FROM WorkOrder WHERE Id = :child.Id].Status);
        WorkOrder savedSiteVisit = [SELECT Status, ChildWorkOrderReviewDone__c FROM WorkOrder WHERE Id = :siteVisit.Id];
        System.assertEquals('New', savedSiteVisit.Status);
        System.assertEquals(false, savedSiteVisit.ChildWorkOrderReviewDone__c);
    }

    /**
     * @description GW-1353 - A child line still marked Send to Repair Center blocks completion.
     */
    @IsTest
    static void checkSiteVisitReview_pendingReturnLine_blocks() {
        Account account = new Account(Name = 'Site Complete Return');
        insert account;
        WorkOrder siteVisit = new WorkOrder(AccountId = account.Id, Subject = 'Site Complete Return', Status = 'New');
        insert siteVisit;
        WorkOrder child = new WorkOrder(
            AccountId = account.Id,
            ParentWorkOrderId = siteVisit.Id,
            Subject = 'Completed Child',
            Status = 'Completed'
        );
        insert child;
        insert new WorkOrderLineItem(
            WorkOrderId = child.Id,
            SendToRepairCenter__c = true,
            Description = 'Forceps'
        );

        Test.startTest();
        WoDebriefIMSController.SiteVisitReviewResult result =
            WoDebriefIMSController.checkSiteVisitReview(siteVisit.Id);
        Test.stopTest();

        System.assertEquals(false, result.canFinish);
        System.assertEquals(0, result.openWorkOrders.size());
        System.assertEquals(1, result.returnOrderLines.size());
        System.assert(result.returnOrderLines[0].contains('Forceps'));
        System.assertEquals('Completed', [SELECT Status FROM WorkOrder WHERE Id = :child.Id].Status);
    }

    /**
     * @description GW-1353 - Finished children with no pending return lines pass and check the review flag. No status changes.
     */
    @IsTest
    static void checkSiteVisitReview_ready_keepsStatuses() {
        Account account = new Account(Name = 'Site Complete Ready');
        insert account;
        WorkOrder siteVisit = new WorkOrder(AccountId = account.Id, Subject = 'Site Complete Ready', Status = 'In Progress');
        insert siteVisit;
        WorkOrder completedChild = new WorkOrder(
            AccountId = account.Id,
            ParentWorkOrderId = siteVisit.Id,
            Subject = 'Completed Child',
            Status = 'Completed'
        );
        WorkOrder closedChild = new WorkOrder(
            AccountId = account.Id,
            ParentWorkOrderId = siteVisit.Id,
            Subject = 'Closed Child',
            Status = 'Closed'
        );
        WorkOrder canceledChild = new WorkOrder(
            AccountId = account.Id,
            ParentWorkOrderId = siteVisit.Id,
            Subject = 'Canceled Child',
            Status = 'Canceled'
        );
        insert new List<WorkOrder>{ completedChild, closedChild, canceledChild };
        insert new WorkOrderLineItem(
            WorkOrderId = completedChild.Id,
            SendToRepairCenter__c = false,
            Description = 'Already returned'
        );

        Test.startTest();
        WoDebriefIMSController.SiteVisitReviewResult result =
            WoDebriefIMSController.checkSiteVisitReview(siteVisit.Id);
        Test.stopTest();

        Map<Id, WorkOrder> saved = new Map<Id, WorkOrder>([
            SELECT Status, ChildWorkOrderReviewDone__c FROM WorkOrder
            WHERE Id IN :new Set<Id>{ siteVisit.Id, completedChild.Id, closedChild.Id, canceledChild.Id }
        ]);
        System.assertEquals(true, result.canFinish);
        System.assertEquals('In Progress', saved.get(siteVisit.Id).Status);
        System.assertEquals(true, saved.get(siteVisit.Id).ChildWorkOrderReviewDone__c);
        System.assertEquals('Completed', saved.get(completedChild.Id).Status);
        System.assertEquals('Closed', saved.get(closedChild.Id).Status);
        System.assertEquals('Canceled', saved.get(canceledChild.Id).Status);
    }

    /**
     * @description GW-1353 - A missing work order is rejected.
     */
    @IsTest
    static void checkSiteVisitReview_missingId_throws() {
        Boolean threw = false;
        try {
            WoDebriefIMSController.checkSiteVisitReview(null);
        } catch (AuraHandledException ex) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    /**
     * @description Ids for a technician appointment and the truck selected for it.
     */
    private class TruckFixture {
        Id workOrderId;
        Id territoryId;
        Id technicianAppointmentId;
        Id serviceResourceId;
        Datetime startTime;
        Datetime endTime;
    }
}