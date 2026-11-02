/**
 * @description GC-2934 Assigns a Lead owner when Submit is clicked.
 *
 *              Responsibilities:
 *              1. Assign one queue when every Product matches the same matrix row.
 *              2. Call TAS when the Products do not agree, and assign one active rep.
 *              3. Use the country queue when TAS does not return one rep.
 *              4. Use the ultimate queue when the country has no queue.
 * @author      Vinay
 * @date        2026-10-09
 */
public with sharing class LeadRoutingService {

    @TestVisible
    private static Id testTasOwnerId;
    @TestVisible
    private static List<Lead_Routing_Matrix__mdt> testMatrixRows;
    @TestVisible
    private static List<Lead_Country_Queue__mdt> testCountryRows;

    private static final Map<String, String> COUNTRY_CODES = new Map<String, String>{
        'us' => 'US',
        'usa' => 'US',
        'united states' => 'US',
        'united states of america' => 'US',
        'ca' => 'CA',
        'canada' => 'CA',
        'uk' => 'UK',
        'gb' => 'UK',
        'united kingdom' => 'UK',
        'great britain' => 'UK',
        'gm' => 'GM',
        'de' => 'GM',
        'germany' => 'GM',
        'aus' => 'AUS',
        'au' => 'AUS',
        'australia' => 'AUS',
        'br' => 'BR',
        'brazil' => 'BR',
        'mx' => 'MX',
        'mexico' => 'MX',
        'sg' => 'SG',
        'singapore' => 'SG',
        'nz' => 'NZ',
        'new zealand' => 'NZ',
        'it' => 'IT',
        'italy' => 'IT',
        'pt' => 'PT',
        'portugal' => 'PT',
        'fr' => 'FR',
        'france' => 'FR',
        'es' => 'ES',
        'spain' => 'ES'
    };

    /**
     * @description Routes the Lead and returns the toast message.
     * @param leadId Lead opened on the record page.
     * @return Message naming the queue or rep that now owns the Lead.
     */
    public static String submit(Id leadId) {
        Lead leadRecord = [
            SELECT Id, Country, State, PostalCode, City, Org_ID__c, Class_Code__c, Sales_Category__c, OwnerId
            FROM Lead
            WHERE Id = :leadId
        ];
        List<LeadProduct__c> products = [
            SELECT Product__r.Name, ParentCategory__c, ProductCategory__c, BusinessUnit__c
            FROM LeadProduct__c
            WHERE Lead__c = :leadId
        ];

        String matrixQueue = resolveMatrixQueue(leadRecord, products);
        if (String.isNotBlank(matrixQueue)) {
            return assignQueue(leadRecord.Id, matrixQueue, System.Label.LeadSubmitAssignedQueueMessage);
        }

        Id tasOwnerId = resolveTasOwner(leadRecord);
        if (tasOwnerId != null) {
            update new Lead(Id = leadRecord.Id, OwnerId = tasOwnerId);
            User ownerUser = [SELECT Name FROM User WHERE Id = :tasOwnerId];
            return String.format(System.Label.LeadSubmitAssignedRepMessage, new List<String>{ ownerUser.Name });
        }

        String countryCode = normalizeCountry(leadRecord.Country);
        String countryQueue = resolveCountryQueue(countryCode);
        if (String.isNotBlank(countryQueue)) {
            return assignQueue(leadRecord.Id, countryQueue, System.Label.LeadSubmitAssignedQueueMessage);
        }

        return assignQueue(
            leadRecord.Id,
            System.Label.LeadUltimateQueueDeveloperName,
            System.Label.LeadSubmitAssignedUltimateMessage
        );
    }

    /**
     * @description Returns one queue developer name when every Product matches that same queue.
     * @param leadRecord Lead being submitted.
     * @param products Products on the Lead.
     * @return Queue developer name, or blank when the matrix does not agree.
     */
    private static String resolveMatrixQueue(Lead leadRecord, List<LeadProduct__c> products) {
        String countryCode = normalizeCountry(leadRecord.Country);
        if (String.isBlank(countryCode) || products.isEmpty()) {
            return null;
        }

        List<Lead_Routing_Matrix__mdt> rows = matrixRows(countryCode);

        String sharedQueue;
        for (LeadProduct__c productRecord : products) {
            Set<String> queues = new Set<String>();
            for (Lead_Routing_Matrix__mdt row : rows) {
                if (matchesProduct(row, productRecord)) {
                    queues.add(row.QueueDeveloperName__c);
                }
            }
            if (queues.size() != 1) {
                return null;
            }
            String productQueue = new List<String>(queues)[0];
            if (sharedQueue == null) {
                sharedQueue = productQueue;
            } else if (sharedQueue != productQueue) {
                return null;
            }
        }
        return sharedQueue;
    }

    private static List<Lead_Routing_Matrix__mdt> matrixRows(String countryCode) {
        if (Test.isRunningTest()) {
            List<Lead_Routing_Matrix__mdt> matchedRows = new List<Lead_Routing_Matrix__mdt>();
            if (testMatrixRows != null) {
                for (Lead_Routing_Matrix__mdt row : testMatrixRows) {
                    if (sameValue(row.Country__c, countryCode)) {
                        matchedRows.add(row);
                    }
                }
            }
            return matchedRows;
        }
        return [
            SELECT ProductName__c, ParentCategory__c, ProductCategory__c, BusinessUnit__c,
                Country__c, QueueDeveloperName__c
            FROM Lead_Routing_Matrix__mdt
            WHERE Country__c = :countryCode
        ];
    }

    private static Boolean matchesProduct(Lead_Routing_Matrix__mdt row, LeadProduct__c productRecord) {
        String productName = productRecord.Product__r == null ? null : productRecord.Product__r.Name;
        return sameValue(row.ProductName__c, productName)
            && sameValue(row.ParentCategory__c, productRecord.ParentCategory__c)
            && sameValue(row.ProductCategory__c, productRecord.ProductCategory__c)
            && sameValue(row.BusinessUnit__c, productRecord.BusinessUnit__c);
    }

    private static Boolean sameValue(String leftValue, String rightValue) {
        return normalizeText(leftValue) == normalizeText(rightValue);
    }

    private static String normalizeText(String value) {
        return value == null ? '' : value.trim().toLowerCase();
    }

    /**
     * @description Calls TAS and returns one active user. Several reps, no rep, or a callout error returns null.
     * @param leadRecord Lead sent to TAS.
     * @return User Id, or null.
     */
    private static Id resolveTasOwner(Lead leadRecord) {
        if (Test.isRunningTest()) {
            return testTasOwnerId;
        }

        TasAssignmentGateway.CalloutResult calloutResult = TasAssignmentGateway.sendAssignmentRequest(
            TasAssignmentRequest.fromLead(leadRecord)
        );
        if (calloutResult == null || !calloutResult.calloutSuccess || calloutResult.parsedResponse == null) {
            return null;
        }

        List<TasTerritoryItem> territories = calloutResult.parsedResponse.territoryData;
        if (territories == null || territories.size() != 1 || territories[0] == null) {
            return null;
        }
        if (String.isBlank(territories[0].salesRepEmployeeNumber)) {
            return null;
        }

        List<User> owners = [
            SELECT Id
            FROM User
            WHERE IsActive = true
            AND EmployeeNumber__c = :territories[0].salesRepEmployeeNumber.trim()
        ];
        if (owners.size() != 1) {
            return null;
        }
        return owners[0].Id;
    }

    private static String resolveCountryQueue(String countryCode) {
        if (String.isBlank(countryCode)) {
            return null;
        }
        List<Lead_Country_Queue__mdt> rows;
        if (Test.isRunningTest()) {
            rows = testCountryRows == null
                ? new List<Lead_Country_Queue__mdt>()
                : testCountryRows;
        } else {
            rows = [
                SELECT QueueDeveloperName__c, Country__c
                FROM Lead_Country_Queue__mdt
                WHERE Country__c = :countryCode
                LIMIT 1
            ];
        }
        for (Lead_Country_Queue__mdt row : rows) {
            if (sameValue(row.Country__c, countryCode)) {
                return row.QueueDeveloperName__c;
            }
        }
        return null;
    }

    private static String assignQueue(Id leadId, String developerName, String messageTemplate) {
        List<Group> queues = [
            SELECT Id, Name
            FROM Group
            WHERE Type = 'Queue'
            AND DeveloperName = :developerName
            LIMIT 1
        ];
        if (queues.isEmpty()) {
            throw new LeadRoutingException(
                String.format(System.Label.LeadSubmitQueueMissingMessage, new List<String>{ developerName })
            );
        }
        update new Lead(Id = leadId, OwnerId = queues[0].Id);
        return String.format(messageTemplate, new List<String>{ queues[0].Name });
    }

    /**
     * @description Maps a Lead country to the code stored on the matrix.
     * @param country Country on the Lead address.
     * @return Country code, or the trimmed uppercase value when it is not in the known list.
     */
    @TestVisible
    private static String normalizeCountry(String country) {
        if (String.isBlank(country)) {
            return null;
        }
        String key = country.trim().toLowerCase();
        if (COUNTRY_CODES.containsKey(key)) {
            return COUNTRY_CODES.get(key);
        }
        return country.trim().toUpperCase();
    }

    /**
     * @description Raised when the chosen queue does not exist.
     */
    public class LeadRoutingException extends Exception {
    }
}