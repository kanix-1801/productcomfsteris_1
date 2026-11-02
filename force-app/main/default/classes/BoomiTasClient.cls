/**
 * @author Abhishek Mishra
 * @date 04-06-2026
 * @description TAS client for Prospect Account request callouts.
 *
 *              Responsibilities:
 *              1. Accept TAS Prospect Account request payloads.
 *              2. Return TAS-compatible HTTP responses for downstream processing.
 *              3. Encapsulate mock and future real Boomi integration behavior.
 *
 *              This client centralizes TAS endpoint interaction for Prospect Account processing.
 */
public with sharing class BoomiTasClient {

    /**
     * @description Sends a Prospect Account request to TAS through Boomi and returns the HTTP response.
     * @param requestBody TAS Prospect Account request payload.
     * @return HTTP response containing TAS territory data.
     */
    public static HttpResponse sendProspectAccountRequest(TasProspectAccountRequest requestBody) {
        
        // ==================================================
        // DEMO MOCK RESPONSE
        // Comment this block later and uncomment real callout
        // ==================================================

        HttpResponse mockResponse = new HttpResponse();
        mockResponse.setStatusCode(200);
        mockResponse.setHeader('Content-Type', 'application/json');

        mockResponse.setBody(
            '{' +
                '"prospectId":"001Ou00000o1V9wIAE",' +
                '"territoryData":[' +
                    '{' +
                        '"classCode":"HC",' +
                        '"tasSalesCategory":"GI REPROC",' +
                        '"tasSalesCategoryDescription":"GI Reproc Sales",' +
                        '"territoryId":"71071",' +
                        '"territoryNumber":"G66301",' +
                        '"territoryDescription":"CLEVELAND, OH",' +
                        '"salesRepId":"100704356",' +
                        '"salesRepEmployeeNumber":"703447",' +
                        '"salesRepName":"Ryan Corabi",' +
                        '"regionName":"G66300 Great Lakes",' +
                        '"regionManagerEmployeeNumber":"704844",' +
                        '"regionManagerName":"Daniel Ranville",' +
                        '"zoneName":"GI Reprocessing US",' +
                        '"zoneManagerEmployeeNumber":"703120",' +
                        '"zoneManagerName":"Joe Barnes",' +
                        '"gbuName":"GI Reprocessing US",' +
                        '"buName":"Reprocessing"' +
                    '},' +
                    '{' +
                        '"classCode":"HC",' +
                        '"tasSalesCategory":"SURG SPT",' +
                        '"tasSalesCategoryDescription":"Procedural Capital Sales",' +
                        '"territoryId":"74735",' +
                        '"territoryNumber":"A11217",' +
                        '"territoryDescription":"CLEVELAND/COLUMBUS, OH",' +
                        '"salesRepId":"101142350",' +
                        '"salesRepEmployeeNumber":"8644",' +
                        '"salesRepName":"Dan Daubner",' +
                        '"regionName":"A11200 Mid Atlantic",' +
                        '"regionManagerEmployeeNumber":"52433",' +
                        '"regionManagerName":"Allison Meyer",' +
                        '"zoneName":"Procedural Capital East US",' +
                        '"zoneManagerEmployeeNumber":"50388",' +
                        '"zoneManagerName":"Kyle Stem",' +
                        '"gbuName":"Procedural Capital US",' +
                        '"buName":"Procedural"' +
                    '}' +
                ']' +
            '}'
        );

        return mockResponse;

        // ==================================================
        // REAL INTEGRATION - use later
        // ==================================================

        /*
        HttpRequest req = new HttpRequest();

        req.setEndpoint('callout:Boomi_TAS_Named_Credential/prospectAccount');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(120000);
        req.setBody(JSON.serialize(requestBody));

        Http http = new Http();
        return http.send(req);
        */
    }
}