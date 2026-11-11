/**
 * @author Akash Dahinde
 * @date 12-06-2026
 * GC-3092 / GC-3279
 * @description TAS request DTO aligned to Boomi contract.
 *
 *              Outbound JSON example:
 *              {
 *                "date": "2026-12-31",
 *                "state": "OH",
 *                "postalCode": "44113",
 *                "country": "USA",
 *                "city": "Cleveland",
 *                "orgId": "82",
 *                "classCode": "HC",
 *                "prospectId": "001...",
 *                "leadId": null,
 *                "sourceSystem": "GlobalSF"
 *              }
 */
public class TasAssignmentRequest {

   /* public String state;
    public String postalCode;
    public String country;
    public String city;
    public String orgId;
    public String classCode;
    public String prospectId;
    public String sourceSystem;
 */
    public String mydate;
    public String state;
    public String postalCode;
    public String country;
    public String city;
    public String orgId;
    public String classCode;
    public String prospectId;
    //GC-3279 START
    public String leadId;
    //GC-3279 END
    public String sourceSystem;
    private static final String SOURCE_SYSTEM = 'GlobalSF';

    /**
     * @description Builds a TAS Prospect Account request payload from an Account record.
     * @param acc Account record used to populate the outbound TAS request.
     * @return TAS Prospect Account request payload.
     */
    public static TasAssignmentRequest fromAccount(Account acc) {
        
        TasAssignmentRequest req = new TasAssignmentRequest();

        /*req.state = acc.BillingState;
        req.postalCode = acc.BillingPostalCode;
        req.country = acc.BillingCountry;
        req.city = acc.BillingCity;
        req.orgId = acc.OrgIDs__c;//part of  GC-3107
        req.classCode = acc.CustomerClassCode__c;
        req.prospectId = acc.Id;
        req.sourceSystem = SOURCE_SYSTEM;*/
        req.mydate = String.valueOf(system.today());
        req.state = acc.BillingState;
        req.postalCode = acc.BillingPostalCode;
        req.country = acc.BillingCountry;
        req.city = acc.BillingCity;
        req.orgId = acc.OrgIDs__c;
        req.classCode = acc.CustomerClassCode__c;
        req.prospectId = acc.Id;
        req.sourceSystem = SOURCE_SYSTEM;

        return req;
    }

    /**
     * @description Builds a TAS Lead request payload from a Lead record.
     * @param leadRecord Lead record used to populate the outbound TAS request.
     * @return TAS Lead request payload.
     * User Story - GC-3279
     */
    public static TasAssignmentRequest fromLead(Lead leadRecord) {
        TasAssignmentRequest req = new TasAssignmentRequest();
        req.mydate = String.valueOf(system.today());
        req.state = leadRecord.State;
        req.postalCode = leadRecord.PostalCode;
        req.country = leadRecord.Country;
        req.city = leadRecord.City;
        req.orgId = leadRecord.Org_ID__c;
        req.classCode = leadRecord.Class_Code__c;
        req.prospectId = null;
        req.leadId = leadRecord.Id;
        req.sourceSystem = SOURCE_SYSTEM;
        return req;
    }

    /**
     * @description Serializes the request using Boomi field names.
     *              Uses "date" instead of a reserved Apex identifier.
     * @return Map ready for JSON serialization.
     */
    public Map<String, Object> toJsonMap() {
           Map<String, Object> payload =  new Map<String, Object>{
           /* 'date' => Date.today().format(),
            'state' => state,
            'postalCode' => postalCode,
            'country' => country,
            'city' => city,
            'orgId' => orgId,
            'classCode' => classCode,
            'prospectId' => prospectId,
            'sourceSystem' => sourceSystem*/
              'date' => mydate ,
            'state' => state,
            'postalCode' => postalCode,
            'country' => country,
            'city' => city,
            'orgId'=>orgId,
            'classCode'=>classCode ,
            'prospectId' => prospectId,
            //GC-3279 START
            'leadId' => leadId,
            //GC-3279 END
            'sourceSystem' => sourceSystem//,
        };
            if (String.isNotBlank(country)) {
           
            if(country.equalsIgnoreCase('United States')){
                payload.put('country','US');
            }
        }
        if (String.isNotBlank(classCode)) {
            if(classCode.equalsIgnoreCase('Healthcare')){
            payload.put('classCode', 'HC');
            }
        }
        return payload;
    }
}