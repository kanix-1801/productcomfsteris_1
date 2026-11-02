/**
 * @author PWC Developer
 * @date 2026/10/16
 *
 * @group CSC Visit
 *
 * @description
 * GC-3564 - Flow action that saves the CSC Visit PDF on the Visit.
 */
public with sharing class SunshinePdfController {

    public static final String SCENARIO = 'CSC Visit PDF';
    public static final String LOGGER_TAG = 'GC-3564';

    /**
     * @description Visit whose PDF should be generated.
     */
    public class GenerateRequest {
        @InvocableVariable(label='CSC Visit Id' required=true)
        public Id visitId;
    }

    /**
     * @description File saved on the Visit.
     */
    public class GenerateResponse {
        @InvocableVariable(label='Content Document Id')
        public Id contentDocumentId;

        @InvocableVariable(label='File Title')
        public String fileTitle;
    }

    /**
     * @description Generates the Visit PDF and stores it in Files.
     * @param requests One request per flow interview.
     * @return The saved file.
     */
    @InvocableMethod(
        label='Generate CSC Visit PDF'
        description='GC-3564. Creates the Visit PDF, including STERIS attendees and Sunshine expenses, and saves it on the Visit.'
    )
    public static List<GenerateResponse> generate(List<GenerateRequest> requests) {
        try {
            List<GenerateResponse> responses = new List<GenerateResponse>();
            for (GenerateRequest request : requests == null ? new List<GenerateRequest>() : requests) {
                SunshineService.PdfFile file = SunshineService.generatePdfFile(request == null ? null : request.visitId);
                GenerateResponse response = new GenerateResponse();
                response.contentDocumentId = file.contentDocumentId;
                response.fileTitle = file.fileTitle;
                responses.add(response);
            }
            return responses;
        } catch (Exception exceptionValue) {
            Logger.setScenario(SCENARIO);
            Logger.error('Unable to generate the CSC Visit PDF. ' + exceptionValue.getMessage()).addTag(LOGGER_TAG);
            throw exceptionValue;
        } finally {
            Logger.saveLog();
        }
    }
}