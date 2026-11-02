/**
 * @author Akash Dahinde
 * @date 01-07-2026
 * @description TAS Customer Account request DTO aligned to Boomi contract.
 *              Uses Account.OracleAddressId__c (Text External Id) — Address object is not used.
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
 *                "sourceSystem": "GlobalSF",
 *                "oracleAddressId": 676777,
 *                "province": "Alberta"
 *              }
 */
public class TasCustomerAccountRequest {

   /* public String state;
    public String postalCode;
    public String country;
    public String city;
    public String orgId;
    public String classCode;
    public String prospectId;
    public String sourceSystem;
    public String oracleAddressId;
    public String province;*/
    public String mydate;
    public String state;
    public String postalCode;
    public String country;
    public String city;
    public String orgId;
    public String classCode;
    public String prospectId;
    public String sourceSystem;

    private static final String SOURCE_SYSTEM = 'GlobalSF';

    /**
     * @description Builds a TAS Customer Account request payload from an Account record.
     * @param acc Account record used to populate the outbound TAS request.
     * @return TAS Customer Account request payload.
     */
    public static TasCustomerAccountRequest fromAccount(Account acc) {
        TasCustomerAccountRequest req = new TasCustomerAccountRequest();
        /*
        if (isCanada(req.country)) {
            req.province = acc.ShippingState;
        }*/
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
     * @description Serializes the request using Boomi field names.
     * @return Map ready for JSON serialization.
     */
    public Map<String, Object> toJsonMap() {
        Map<String, Object> payload = new Map<String, Object>{
            'date' => mydate ,
            'state' => state,
            'postalCode' => postalCode,
            'country' => country,
            'city' => city,
            'orgId'=>orgId,
            'classCode'=>classCode ,
            'prospectId' => prospectId,
            'sourceSystem' => sourceSystem//,
            //'oracleAddressId' => serializeOracleAddressId(oracleAddressId)
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

       /* if (isCanada(country) && String.isNotBlank(province)) {
            payload.put('province', province);
        }*/

        return payload;
    }

    private static Object serializeOracleAddressId(String value) {
        if (String.isBlank(value)) {
            return null;
        }

        try {
            return String.valueOf(value.trim());
        } catch (Exception ex) {
            return value.trim();
        }
    }

    private static Boolean isCanada(String country) {
        if (String.isBlank(country)) {
            return false;
        }

        String normalized = country.trim().toUpperCase();
        return normalized == 'CANADA'
            || normalized == 'CA'
            || normalized == 'CAN';
    }
}