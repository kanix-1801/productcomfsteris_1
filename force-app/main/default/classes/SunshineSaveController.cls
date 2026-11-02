/**
 * @author PWC Developer
 * @date 2026/10/16
 *
 * @group CSC Visit
 *
 * @description
 * GC-3564 - Flow action that saves a Sunshine physician and expense row.
 */
public with sharing class SunshineSaveController {

    public static final String SCENARIO = 'CSC Visit Sunshine Save';
    public static final String LOGGER_TAG = 'GC-3564';

    /**
     * @description Physician and expense values from the Sunshine screen flow.
     */
    public class SaveRequest {
        @InvocableVariable(label='CSC Visit Id' required=true)
        public Id visitId;

        @InvocableVariable(label='Sunshine Id')
        public String sunshineId;

        @InvocableVariable(label='NPI')
        public String npi;

        @InvocableVariable(label='Airfare')
        public Decimal airfare;

        @InvocableVariable(label='Hotel')
        public Decimal hotel;

        @InvocableVariable(label='Visit Nights')
        public Decimal visitNights;

        @InvocableVariable(label='Meals')
        public Decimal meals;

        @InvocableVariable(label='Transportation')
        public Decimal transportation;

        @InvocableVariable(label='Type')
        public String sunshineType;

        @InvocableVariable(label='Product Associated')
        public String productAssociated;
    }

    /**
     * @description Confirmation returned to the screen flow.
     */
    public class SaveResponse {
        @InvocableVariable(label='Sunshine Id')
        public Id sunshineId;

        @InvocableVariable(label='Message')
        public String message;
    }

    /**
     * @description Creates or updates a Sunshine row. Expense fields stay editable after the Visit date.
     * @param requests One request per flow interview.
     * @return Saved record Ids.
     */
    @InvocableMethod(
        label='Save Sunshine Physician'
        description='GC-3564. Saves the physician from the directory and the reportable expense amounts.'
    )
    public static List<SaveResponse> save(List<SaveRequest> requests) {
        try {
            List<SaveResponse> responses = new List<SaveResponse>();
            for (SaveRequest request : requests == null ? new List<SaveRequest>() : requests) {
                Id sunshineId = SunshineService.save(toServiceRequest(request));
                SaveResponse response = new SaveResponse();
                response.sunshineId = sunshineId;
                response.message = 'Sunshine physician and expenses were saved.';
                responses.add(response);
            }
            return responses;
        } catch (Exception exceptionValue) {
            Logger.setScenario(SCENARIO);
            Logger.error('Unable to save Sunshine expenses. ' + exceptionValue.getMessage()).addTag(LOGGER_TAG);
            throw exceptionValue;
        } finally {
            Logger.saveLog();
        }
    }

    private static SunshineService.SaveRequest toServiceRequest(SaveRequest request) {
        SunshineService.SaveRequest serviceRequest = new SunshineService.SaveRequest();
        if (request == null) {
            return serviceRequest;
        }
        serviceRequest.visitId = request.visitId;
        serviceRequest.sunshineId = String.isBlank(request.sunshineId) ? null : (Id) request.sunshineId;
        serviceRequest.npi = request.npi;
        serviceRequest.airfare = request.airfare;
        serviceRequest.hotel = request.hotel;
        serviceRequest.visitNights = request.visitNights;
        serviceRequest.meals = request.meals;
        serviceRequest.transportation = request.transportation;
        serviceRequest.sunshineType = request.sunshineType;
        serviceRequest.productAssociated = request.productAssociated;
        return serviceRequest;
    }
}