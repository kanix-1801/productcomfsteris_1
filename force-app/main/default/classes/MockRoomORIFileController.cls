/**
 * @author PWC Developer
 * @date 2026/10/09
 *
 * @group Mock Room / ORI Request
 *
 * @description
 * GC-3483 - Flow action that attaches intake files to a Mock Room / ORI request.
 */
public with sharing class MockRoomORIFileController {

    public static final String SCENARIO = 'Mock Room / ORI Files';
    public static final String LOGGER_TAG = 'MockRoomORIFile';

    /**
     * @description One request and the files uploaded for it.
     */
    public class FileLinkRequest {
        @InvocableVariable(label='Request Id' required=true)
        public Id requestId;

        @InvocableVariable(label='Document Ids')
        public String documentIds;
    }

    /**
     * @description Attaches the uploaded files to the request.
     * @param requests Requests created by the intake flow.
     */
    @InvocableMethod(label='Link Mock Room ORI Files' description='GC-3483. Attaches files uploaded on the intake screen to the new request.')
    public static void linkFiles(List<FileLinkRequest> requests) {
        try {
            MockRoomORIFileService.linkFiles(requests);
        } catch (Exception exceptionValue) {
            Logger.setScenario(SCENARIO);
            Logger.error('Unable to attach Mock Room / ORI files. ' + exceptionValue.getMessage())
                .addTag(LOGGER_TAG);
            throw new AuraHandledException('Unable to attach the files to the request.');
        } finally {
            Logger.saveLog();
        }
    }
}