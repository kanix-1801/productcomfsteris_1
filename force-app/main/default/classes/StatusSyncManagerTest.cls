/**
 * @author Uptima
 * @date 2026-11-24
 * @description Tests for StatusSyncManager (GW-6502 / GW-6581).
 */
@IsTest
private class StatusSyncManagerTest {
    private static final String GC_AVAILABLE_ON_QUEUE = 'e08eaf1b-ee47-4fa9-a231-1200e284798f';
    private static final String GC_AVAILABLE = '6a3af858-942f-489d-9700-5f9bcdcdae9b';
    private static final String GC_BUSY = '31fe3bac-dea6-44b7-bed7-47f91660a1a0';
    private static final String GC_MEAL = '3fd96123-badb-4f69-bc03-1b1ccc6d8014';
    private static final Id SF_AVAILABLE = '0N5Ou0000000zWXKAY';
    private static final Id SF_AVAILABLE_OFF_QUEUE = '0N5Ou0000000zTJKAY';
    private static final Id SF_BUSY = '0N5Ou0000000zQ5KAI';

    @IsTest
    private static void testOnSalesforceStatusChangeAvailableMapsToOnQueue() {
        // Setup
        configureTestMaps();
        StatusSyncManager manager = new StatusSyncManager();
        String payload = buildIncomingPayload(
            'Available',
            String.valueOf(SF_AVAILABLE),
            'Available',
            'prior-gc-id',
            'AVAILABLE'
        );

        // Given / When
        Test.startTest();
        String responseJson = manager.onSalesforceStatusChange(payload);
        Test.stopTest();

        // Then
        Map<String, Object> response = parseResponse(responseJson);
        Assert.areEqual(
            GC_AVAILABLE_ON_QUEUE,
            (String) response.get('genesysTargetId'),
            'Available should map to Genesys Available On Queue'
        );
        Assert.areEqual(
            String.valueOf(SF_AVAILABLE),
            (String) response.get('salesforceTargetId'),
            'Salesforce target Id should be unchanged'
        );
    }

    @IsTest
    private static void testOnSalesforceStatusChangeAvailableOffQueueMapsToAvailable() {
        // Setup
        configureTestMaps();
        StatusSyncManager manager = new StatusSyncManager();
        String payload = buildIncomingPayload(
            'AvailableOffQueue',
            String.valueOf(SF_AVAILABLE_OFF_QUEUE),
            'Available Off Queue',
            'prior-gc-id',
            'ON_QUEUE'
        );

        // Given / When
        Test.startTest();
        String responseJson = manager.onSalesforceStatusChange(payload);
        Test.stopTest();

        // Then
        Map<String, Object> response = parseResponse(responseJson);
        Assert.areEqual(
            GC_AVAILABLE,
            (String) response.get('genesysTargetId'),
            'Available Off Queue should map to Genesys Available'
        );
    }

    @IsTest
    private static void testOnSalesforceStatusChangeResolvesByMasterLabel() {
        // Setup
        configureTestMaps();
        StatusSyncManager manager = new StatusSyncManager();
        String payload = buildIncomingPayload(
            null,
            String.valueOf(SF_BUSY),
            'Busy',
            'prior-gc-id',
            'AVAILABLE'
        );

        // Given / When
        Test.startTest();
        String responseJson = manager.onSalesforceStatusChange(payload);
        Test.stopTest();

        // Then
        Map<String, Object> response = parseResponse(responseJson);
        Assert.areEqual(
            GC_BUSY,
            (String) response.get('genesysTargetId'),
            'Busy MasterLabel should resolve to Omni DeveloperName then Genesys Busy'
        );
    }

    @IsTest
    private static void testOnSalesforceStatusChangeUnhandledLeavesGenesysDefault() {
        // Setup
        configureTestMaps();
        StatusSyncManager manager = new StatusSyncManager();
        String payload = buildIncomingPayload(
            'AvailableforVoice',
            '0N5Ou0000000zJdKAI',
            'Available for Voice',
            'unchanged-gc-id',
            'AVAILABLE'
        );

        // Given / When
        Test.startTest();
        String responseJson = manager.onSalesforceStatusChange(payload);
        Test.stopTest();

        // Then
        Map<String, Object> response = parseResponse(responseJson);
        Assert.areEqual(
            'unchanged-gc-id',
            (String) response.get('genesysTargetId'),
            'Unhandled Omni status should leave Genesys target unchanged'
        );
    }

    @IsTest
    private static void testOnGenesysCloudStatusChangeAvailableOnQueueMapsToAvailable() {
        // Setup
        configureTestMaps();
        StatusSyncManager manager = new StatusSyncManager();
        String payload = buildIncomingPayload(
            'Busy',
            String.valueOf(SF_BUSY),
            'Busy',
            GC_AVAILABLE_ON_QUEUE,
            'ON_QUEUE'
        );

        // Given / When
        Test.startTest();
        String responseJson = manager.onGenesysCloudStatusChange(payload);
        Test.stopTest();

        // Then
        Map<String, Object> response = parseResponse(responseJson);
        Assert.areEqual(
            String.valueOf(SF_AVAILABLE),
            (String) response.get('salesforceTargetId'),
            'Available On Queue should map to Omni Available'
        );
    }

    @IsTest
    private static void testOnGenesysCloudStatusChangeAvailableMapsToAvailableOffQueue() {
        // Setup
        configureTestMaps();
        StatusSyncManager manager = new StatusSyncManager();
        String payload = buildIncomingPayload(
            'Available',
            String.valueOf(SF_AVAILABLE),
            'Available',
            GC_AVAILABLE,
            'AVAILABLE'
        );

        // Given / When
        Test.startTest();
        String responseJson = manager.onGenesysCloudStatusChange(payload);
        Test.stopTest();

        // Then
        Map<String, Object> response = parseResponse(responseJson);
        Assert.areEqual(
            String.valueOf(SF_AVAILABLE_OFF_QUEUE),
            (String) response.get('salesforceTargetId'),
            'Genesys Available should map to Omni Available Off Queue'
        );
    }

    @IsTest
    private static void testOnGenesysCloudStatusChangeBusyMapsToBusy() {
        // Setup
        configureTestMaps();
        StatusSyncManager manager = new StatusSyncManager();
        String payload = buildIncomingPayload(
            'Available',
            String.valueOf(SF_AVAILABLE),
            'Available',
            GC_BUSY,
            'BUSY'
        );

        // Given / When
        Test.startTest();
        String responseJson = manager.onGenesysCloudStatusChange(payload);
        Test.stopTest();

        // Then
        Map<String, Object> response = parseResponse(responseJson);
        Assert.areEqual(
            String.valueOf(SF_BUSY),
            (String) response.get('salesforceTargetId'),
            'Genesys Busy should map to Omni Busy'
        );
    }

    @IsTest
    private static void testOnGenesysCloudStatusChangeMealLeavesSalesforceDefault() {
        // Setup
        configureTestMaps();
        StatusSyncManager manager = new StatusSyncManager();
        String payload = buildIncomingPayload(
            'Available',
            String.valueOf(SF_AVAILABLE),
            'Available',
            GC_MEAL,
            'AWAY'
        );

        // Given / When
        Test.startTest();
        String responseJson = manager.onGenesysCloudStatusChange(payload);
        Test.stopTest();

        // Then
        Map<String, Object> response = parseResponse(responseJson);
        Assert.areEqual(
            String.valueOf(SF_AVAILABLE),
            (String) response.get('salesforceTargetId'),
            'Meal should leave Omni target unchanged when Omni Meal status is absent'
        );
    }

    @IsTest
    private static void testOnSalesforceStatusChangeUnresolvedOmniStatus() {
        // Setup
        configureTestMaps();
        StatusSyncManager manager = new StatusSyncManager();
        String payload = buildIncomingPayload(null, String.valueOf(SF_AVAILABLE), null, 'prior-gc-id', 'AVAILABLE');

        // Given / When
        Test.startTest();
        String responseJson = manager.onSalesforceStatusChange(payload);
        Test.stopTest();

        // Then
        Map<String, Object> response = parseResponse(responseJson);
        Assert.areEqual(
            'prior-gc-id',
            (String) response.get('genesysTargetId'),
            'Unresolved Omni status should leave Genesys target unchanged'
        );
    }

    @IsTest
    private static void testOnGenesysCloudStatusChangeUnhandledGenesysId() {
        // Setup
        configureTestMaps();
        StatusSyncManager manager = new StatusSyncManager();
        String payload = buildIncomingPayload(
            'Available',
            String.valueOf(SF_AVAILABLE),
            'Available',
            'unknown-genesys-id',
            'AVAILABLE'
        );

        // Given / When
        Test.startTest();
        String responseJson = manager.onGenesysCloudStatusChange(payload);
        Test.stopTest();

        // Then
        Map<String, Object> response = parseResponse(responseJson);
        Assert.areEqual(
            String.valueOf(SF_AVAILABLE),
            (String) response.get('salesforceTargetId'),
            'Unhandled Genesys id should leave Omni target unchanged'
        );
    }

    @IsTest
    private static void testOnSalesforceStatusChangeInvalidPayloadThrows() {
        // Setup
        configureTestMaps();
        StatusSyncManager manager = new StatusSyncManager();
        Boolean threw = false;

        // Given / When
        Test.startTest();
        try {
            manager.onSalesforceStatusChange('{bad-json');
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        // Then
        Assert.isTrue(threw, 'Invalid payload should throw');
    }

    @IsTest
    private static void testOnGenesysCloudStatusChangeInvalidPayloadThrows() {
        // Setup
        configureTestMaps();
        StatusSyncManager manager = new StatusSyncManager();
        Boolean threw = false;

        // Given / When
        Test.startTest();
        try {
            manager.onGenesysCloudStatusChange('{bad-json');
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        // Then
        Assert.isTrue(threw, 'Invalid payload should throw');
    }

    @IsTest
    private static void testLoadMapsUsesCmdtJsonAndQueriesPresenceStatuses() {
        // Setup
        StatusSyncManager.resetMaps();
        StatusSyncManager.genesysStatusMapOverride = null;
        StatusSyncManager.genesysStatusMapJsonOverride =
            '{"Available":"' + GC_AVAILABLE_ON_QUEUE + '","Busy":"' + GC_BUSY + '"}';
        StatusSyncManager.presenceStatusesOverride = null;
        StatusSyncManager manager = new StatusSyncManager();
        String payload = buildIncomingPayload(
            'Available',
            String.valueOf(SF_AVAILABLE),
            'Available',
            'prior-gc-id',
            'AVAILABLE'
        );

        // Given / When
        Test.startTest();
        String first = manager.onSalesforceStatusChange(payload);
        String second = manager.onSalesforceStatusChange(payload);
        Test.stopTest();

        // Then
        Map<String, Object> response = parseResponse(first);
        Assert.areEqual(
            GC_AVAILABLE_ON_QUEUE,
            (String) response.get('genesysTargetId'),
            'CMDT JSON override should map Available'
        );
        Assert.areEqual(first, second, 'Cached maps should return consistent responses');
    }

    @IsTest
    private static void testLoadGenesysStatusMapBlankAndInvalidJson() {
        // Setup
        StatusSyncManager.resetMaps();
        StatusSyncManager.genesysStatusMapOverride = null;
        StatusSyncManager.genesysStatusMapJsonOverride = '';
        StatusSyncManager.presenceStatusesOverride = new List<ServicePresenceStatus>();
        StatusSyncManager manager = new StatusSyncManager();

        // Given / When
        Test.startTest();
        String blankMapResponse = manager.onSalesforceStatusChange(
            buildIncomingPayload('Available', String.valueOf(SF_AVAILABLE), 'Available', 'prior-gc-id', 'AVAILABLE')
        );

        StatusSyncManager.resetMaps();
        StatusSyncManager.genesysStatusMapOverride = null;
        StatusSyncManager.genesysStatusMapJsonOverride = '{not-json';
        StatusSyncManager.presenceStatusesOverride = new List<ServicePresenceStatus>();
        String invalidJsonResponse = manager.onSalesforceStatusChange(
            buildIncomingPayload('Available', String.valueOf(SF_AVAILABLE), 'Available', 'prior-gc-id', 'AVAILABLE')
        );
        Test.stopTest();

        // Then
        Assert.areEqual(
            'prior-gc-id',
            (String) parseResponse(blankMapResponse).get('genesysTargetId'),
            'Blank GenesysStatusMap should leave Genesys target unchanged'
        );
        Assert.areEqual(
            'prior-gc-id',
            (String) parseResponse(invalidJsonResponse).get('genesysTargetId'),
            'Invalid GenesysStatusMap JSON should leave Genesys target unchanged'
        );
    }

    private static void configureTestMaps() {
        StatusSyncManager.resetMaps();
        StatusSyncManager.genesysStatusMapJsonOverride = null;
        StatusSyncManager.genesysStatusMapOverride = new Map<String, String>{
            'Available' => GC_AVAILABLE_ON_QUEUE,
            'AvailableOffQueue' => GC_AVAILABLE,
            'Busy' => GC_BUSY,
            'Meal' => GC_MEAL
        };
        StatusSyncManager.presenceStatusesOverride = (List<ServicePresenceStatus>) JSON.deserialize(
            JSON.serialize(
                new List<Map<String, String>>{
                    new Map<String, String>{
                        'Id' => String.valueOf(SF_AVAILABLE),
                        'DeveloperName' => 'Available',
                        'MasterLabel' => 'Available'
                    },
                    new Map<String, String>{
                        'Id' => String.valueOf(SF_AVAILABLE_OFF_QUEUE),
                        'DeveloperName' => 'AvailableOffQueue',
                        'MasterLabel' => 'Available Off Queue'
                    },
                    new Map<String, String>{
                        'Id' => String.valueOf(SF_BUSY),
                        'DeveloperName' => 'Busy',
                        'MasterLabel' => 'Busy'
                    }
                }
            ),
            List<ServicePresenceStatus>.class
        );
    }

    private static String buildIncomingPayload(
        String sfApiName,
        String sfStatusId,
        String sfStatusName,
        String genesysId,
        String genesysSystemPresence
    ) {
        Map<String, Object> salesforceTarget = new Map<String, Object>{
            'statusApiName' => sfApiName,
            'statusId' => sfStatusId,
            'statusName' => sfStatusName
        };
        Map<String, Object> genesysTarget = new Map<String, Object>{
            'id' => genesysId,
            'systemPresence' => genesysSystemPresence
        };
        Map<String, Object> payload = new Map<String, Object>{
            'salesforceStatus' => new Map<String, Object>{
                'currentStatus' => salesforceTarget,
                'targetStatus' => salesforceTarget
            },
            'genesysCloudStatus' => new Map<String, Object>{
                'currentStatus' => genesysTarget,
                'targetStatus' => genesysTarget
            }
        };
        return JSON.serialize(payload);
    }

    private static Map<String, Object> parseResponse(String responseJson) {
        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(responseJson);
        Map<String, Object> genesys = (Map<String, Object>) root.get('genesysCloudStatus');
        Map<String, Object> genesysTarget = (Map<String, Object>) genesys.get('targetStatus');
        Map<String, Object> salesforce = (Map<String, Object>) root.get('salesforceStatus');
        Map<String, Object> salesforceTarget = (Map<String, Object>) salesforce.get('targetStatus');
        return new Map<String, Object>{
            'genesysTargetId' => genesysTarget.get('id'),
            'salesforceTargetId' => salesforceTarget.get('statusId')
        };
    }
}