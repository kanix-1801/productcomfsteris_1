/**
 * @description GC-2934 Assigns a Lead owner when Submit is clicked.
 *
 *              Responsibilities:
 *              1. Leave a Lead with HubSpot Lead unchecked and Auto Assign Lead unselected on its current owner.
 *              2. Call TAS only when the Lead has Products and every Product has a family code and a class code.
 *                 Assign one active rep when TAS returns one rep.
 *              3. Use the country queue when TAS is skipped or does not return one rep.
 *              4. Use the ultimate queue when the country has no queue.
 * @author      Vinay
 * @date        2026-10-09
 */
public with sharing class LeadRoutingService {

    @TestVisible
    private static Id testTasOwnerId;
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
        'spain' => 'ES',
        'be' => 'BE',
        'belgium' => 'BE',
        'nl' => 'NL',
        'netherlands' => 'NL',
        'lu' => 'LU',
        'luxembourg' => 'LU',
        'my' => 'MY',
        'malaysia' => 'MY',
        'hk' => 'HK',
        'hong kong' => 'HK'
    };

    /**
     * @description Routes the Lead and returns the toast message.
     * @param leadId Lead opened on the record page.
     * @return Message naming the queue or rep that now owns the Lead.
     */
    public static String submit(Id leadId) {
        Lead leadRecord = [
            SELECT Id, Country, CountryCode, State, PostalCode, City, Org_ID__c, Class_Code__c, OwnerId,
                HubSpot_Lead__c, Auto_Assign_Lead__c, LeadSource
            FROM Lead
            WHERE Id = :leadId
        ];
        // GC-3662 An Auto Assign Lead goes to TAS, then the regional queue.
        Boolean autoAssign = LeadAutoAssignService.isEligible(leadRecord);
        if (!leadRecord.HubSpot_Lead__c && !autoAssign) {
            return null;
        }

        Id tasOwnerId = hasCompleteProducts(leadRecord.Id) ? resolveTasOwner(leadRecord) : null;
        if (tasOwnerId != null) {
            update new Lead(Id = leadRecord.Id, OwnerId = tasOwnerId);
            User ownerUser = [SELECT Name FROM User WHERE Id = :tasOwnerId];
            return String.format(System.Label.LeadSubmitAssignedRepMessage, new List<String>{ ownerUser.Name });
        }

        String countryCode = normalizeCountry(countryValue(leadRecord));
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

    private static Boolean sameValue(String leftValue, String rightValue) {
        return normalizeText(leftValue) == normalizeText(rightValue);
    }

    private static String normalizeText(String value) {
        return value == null ? '' : value.trim().toLowerCase();
    }

    // TAS needs a family code and a class code for every Product. A Lead with no Product, or with a Product missing a code, skips TAS.
    private static Boolean hasCompleteProducts(Id leadId) {
        if (!Schema.sObjectType.LeadProduct__c.isAccessible()) {
            return false;
        }
        List<LeadProduct__c> products = [
            SELECT Product_Family_Code__c, Product_Class_Code__c
            FROM LeadProduct__c
            WHERE Lead__c = :leadId
            WITH USER_MODE
        ];
        for (LeadProduct__c product : products) {
            if (String.isBlank(product.Product_Family_Code__c) || String.isBlank(product.Product_Class_Code__c)) {
                return false;
            }
        }
        return !products.isEmpty();
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

        String employeeNumber = singleRepEmployeeNumber(calloutResult.parsedResponse.territoryData);
        if (employeeNumber == null) {
            return null;
        }

        List<User> owners = [
            SELECT Id
            FROM User
            WHERE IsActive = true
            AND EmployeeNumber__c = :employeeNumber
        ];
        if (owners.size() != 1) {
            return null;
        }
        return owners[0].Id;
    }

    /**
     * Returns the employee number when every TAS row names the same rep.
     * Several rows for one rep count as one assignment. A blank rep, or different reps, return null.
     * @param territories Rows returned by TAS.
     * @return Employee number of the one rep, or null.
     */
    @TestVisible
    private static String singleRepEmployeeNumber(List<TasTerritoryItem> territories) {
        Set<String> employeeNumbers = new Set<String>();
        for (TasTerritoryItem territory : territories == null ? new List<TasTerritoryItem>() : territories) {
            if (territory == null || String.isBlank(territory.salesRepEmployeeNumber)) {
                return null;
            }
            employeeNumbers.add(territory.salesRepEmployeeNumber.trim());
        }
        return employeeNumbers.size() == 1 ? new List<String>(employeeNumbers)[0] : null;
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
     * @description Maps a Lead country to the code stored on the country queue row.
     * @param country Country on the Lead address.
     * @return Country code, or the trimmed uppercase value when it is not in the known list.
     */
    private static String countryValue(Lead leadRecord) {
        return String.isNotBlank(leadRecord.CountryCode) ? leadRecord.CountryCode : leadRecord.Country;
    }

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