/**
 * @author Abhishek Mishra
 * @date 04-06-2026
 * @description TAS assignment response DTO for Account and Lead processing.
 *
 *              Responsibilities:
 *              1. Store TAS response data returned for Account or Lead assignment.
 *              2. Deserialize TAS response JSON into Apex DTO objects.
 *              3. Provide territory data to integration services.
 */
public class TasAssignmentResponse {

    public String prospectId;
    //GC-3279 START
    public String leadId;
    //GC-3279 END
    public List<TasTerritoryItem> territoryData;

    /**
     * @description Parses TAS response JSON into a TasAssignmentResponse instance.
     * @param responseBody JSON response body returned by TAS.
     * @return Parsed TasAssignmentResponse when response body is populated; otherwise null.
     */
        public static TasAssignmentResponse parse(String responseBody) {
            if (String.isBlank(responseBody)) {
                return null;
            }
        
            String normalizedBody = responseBody.replace('"customerClassCode"', '"classCode"');
        
            return (TasAssignmentResponse) JSON.deserialize(
                normalizedBody,
                TasAssignmentResponse.class
            );
        }
}