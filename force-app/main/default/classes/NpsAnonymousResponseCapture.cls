/**
 * @author PWC Developer
 * @date 2026/11/19
 *
 * @group Survey Management
 *
 * @description
 * GC-3506 AC8. Flow action that stores an email collected on an anonymous NPS survey.
 * Matching the email to a Contact is a separate response-linkage story.
 */
public with sharing class NpsAnonymousResponseCapture {

    public class CaptureRequest {
        @InvocableVariable(label='Invitation Id' description='SurveyInvitation Id for the response.')
        public String invitationId;
        @InvocableVariable(label='Question Id' description='SurveyQuestion Id. Used when Question Name is blank.')
        public String questionId;
        @InvocableVariable(label='Question Name' description='Survey question name. Email questions are stored.')
        public String questionName;
        @InvocableVariable(label='Response Value' description='Answer typed by the respondent.')
        public String responseValue;
    }

    @InvocableMethod(
        label='Capture NPS Anonymous Respondent Email'
        description='Stores an email typed on the configured anonymous survey question. Does not match a Contact.'
    )
    public static void capture(List<CaptureRequest> requests) {
        NpsSurveyDistributionService.captureRespondentEmails(requests);
    }
}