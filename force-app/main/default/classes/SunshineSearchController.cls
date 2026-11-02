/**
 * @author PWC Developer
 * @date 2026/10/16
 *
 * @group CSC Visit
 *
 * @description
 * GC-3564 - Flow action that searches the physician directory.
 */
public with sharing class SunshineSearchController {

    public static final String SCENARIO = 'CSC Visit Sunshine Search';
    public static final String LOGGER_TAG = 'GC-3564';

    /**
     * @description Search inputs from the Sunshine screen flow.
     */
    public class SearchRequest {
        @InvocableVariable(label='First Name')
        public String firstName;

        @InvocableVariable(label='Last Name')
        public String lastName;

        @InvocableVariable(label='City')
        public String city;

        @InvocableVariable(label='NPI')
        public String npi;
    }

    /**
     * @description One search response. Physician fields are set only when one physician matches.
     */
    public class SearchResponse {
        @InvocableVariable(label='Match Count')
        public Integer matchCount;

        @InvocableVariable(label='Result Message')
        public String resultMessage;

        @InvocableVariable(label='NPI')
        public String npi;

        @InvocableVariable(label='First Name')
        public String firstName;

        @InvocableVariable(label='Last Name')
        public String lastName;

        @InvocableVariable(label='City')
        public String city;

        @InvocableVariable(label='State')
        public String physicianState;

        @InvocableVariable(label='Credential')
        public String credential;

        @InvocableVariable(label='Taxonomy Code')
        public String taxonomyCode;

        @InvocableVariable(label='Taxonomy Description')
        public String taxonomyDescription;
    }

    /**
     * @description Searches the local physician directory.
     * @param requests One request per flow interview.
     * @return Search results in the same order.
     */
    @InvocableMethod(
        label='Search Sunshine Physicians'
        description='GC-3564. Returns physicians from the local directory. A later sprint replaces the directory with the NPI integration.'
    )
    public static List<SearchResponse> search(List<SearchRequest> requests) {
        try {
            List<SearchResponse> responses = new List<SearchResponse>();
            for (SearchRequest request : requests == null ? new List<SearchRequest>() : requests) {
                responses.add(toResponse(request));
            }
            return responses;
        } catch (Exception exceptionValue) {
            Logger.setScenario(SCENARIO);
            Logger.error('Unable to search physicians. ' + exceptionValue.getMessage()).addTag(LOGGER_TAG);
            throw exceptionValue;
        } finally {
            Logger.saveLog();
        }
    }

    private static SearchResponse toResponse(SearchRequest request) {
        SunshineService.SearchResult result = SunshineService.search(
            request == null ? null : request.firstName,
            request == null ? null : request.lastName,
            request == null ? null : request.city,
            request == null ? null : request.npi
        );
        SearchResponse response = new SearchResponse();
        response.matchCount = result.matchCount;
        response.resultMessage = result.resultMessage;
        response.npi = result.npi;
        response.firstName = result.firstName;
        response.lastName = result.lastName;
        response.city = result.city;
        response.physicianState = result.physicianState;
        response.credential = result.credential;
        response.taxonomyCode = result.taxonomyCode;
        response.taxonomyDescription = result.taxonomyDescription;
        return response;
    }
}