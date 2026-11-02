/**
 * @author Akash Dahinde
 * @date 07-01-2026
 * @description TAS Customer Account response DTO.
 */
	public class TasCustomerAccountResponse {

    public String prospectId;
    public List<TasAccountResponseItem> territoryData;

    /**
     * @description Parses TAS response JSON into a TasCustomerAccountResponse instance.
     * @param responseBody JSON response body returned by TAS.
     * @return Parsed TasCustomerAccountResponse when response body is populated; otherwise null.
     */
    public static TasCustomerAccountResponse parse(String responseBody) {
        if (String.isBlank(responseBody)) {
            return null;
        }

        return (TasCustomerAccountResponse) JSON.deserialize(
            responseBody,
            TasCustomerAccountResponse.class
        );
    }
}