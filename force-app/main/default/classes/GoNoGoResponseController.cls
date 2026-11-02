/**
 * @author PSL
 * @date 01-02-2026
 * @description Helper class for creating Tasks related to Orders, Order Lines, and Holds based on TaskSLAConfig metadata.
 *              Provides methods for task creation, owner resolution, SLA calculation, and formula evaluation.
 */
public class GoNoGoResponseController {
		
    public class Request {
       @InvocableVariable(required=true)
       public Id caseId;
   }

   public class Response {
       @InvocableVariable public Id caseId;
       @InvocableVariable public String status;
       @InvocableVariable public String message;
   }

   private static final String TEMPLATE_DEVELOPER_NAME = 'GoNoGoResponse';
   private static final String SUBJECT_GoNo = 'Response Required: Go/No-Go';

   @InvocableMethod(
       label='Send Go/No-Go Email'
       description='Sends Go/No-Go reminder email using conditional TO logic and latest email CC.'
   )
   public static List<Response> sendEmail(List<Request> requests) {

       List<Response> responses = new List<Response>();
       if (requests == null || requests.isEmpty()) return responses;

       /* -------------------- Collect Case Ids -------------------- */
       Set<Id> caseIds = new Set<Id>();
       for (Request r : requests) {
           if (r != null && r.caseId != null) {
               caseIds.add(r.caseId);
           }
       }

       if (caseIds.isEmpty()) return responses;

       /* -------------------- Query Cases -------------------- */
       Map<Id, Case> caseMap = new Map<Id, Case>([
           SELECT Id,
                  ContactId,
                  OverAll_GO_NOGODecision__c,
                  IPMDecision__c,
                  Sales_Decision__c
           FROM Case
           WHERE Id IN :caseIds
       ]);

       /* -------------------- Fetch Order Line Contacts -------------------- */
       Map<Id, Set<String>> salesEmailsByCase = new Map<Id, Set<String>>();
       Map<Id, Set<String>> ipmEmailsByCase   = new Map<Id, Set<String>>();

       for (Id cid : caseIds) {
           salesEmailsByCase.put(cid, new Set<String>());
           ipmEmailsByCase.put(cid, new Set<String>());
       }

       List<OrderLineContact__c> olcs = [
           SELECT SalesRep__r.Email,
                  OrderLine__r.OrderLineType__c,
                  OrderLine__r.CreateSubcase__c,
                  OrderLine__r.Order.parentCase__c
           FROM OrderLineContact__c
           WHERE OrderLine__r.Order.parentCase__c IN :caseIds
       ];

       for (OrderLineContact__c olc : olcs) {
           if (String.isBlank(olc.SalesRep__r.Email)) continue;

           Id caseId = olc.OrderLine__r.Order.parentCase__c;
           String email = olc.SalesRep__r.Email.toLowerCase().trim();

           if (olc.OrderLine__r.CreateSubcase__c == 'yes - Capital line') {
               salesEmailsByCase.get(caseId).add(email);
           }

           if (olc.OrderLine__r.OrderLineType__c == 'Service – Installation') {
               ipmEmailsByCase.get(caseId).add(email);
           }
       }

       /* -------------------- Latest Matching Email Per Case -------------------- */
       Map<Id, EmailMessage> latestEmailByCase = new Map<Id, EmailMessage>();

       List<EmailMessage> emails = [
           SELECT Id, ParentId, Subject, FromAddress, ToAddress, CcAddress,
                  MessageDate, CreatedDate
           FROM EmailMessage
           WHERE ParentId IN :caseIds
             AND Subject LIKE :('%' + SUBJECT_GoNo + '%') and incoming=false
           ORDER BY ParentId, MessageDate DESC NULLS LAST, CreatedDate DESC
           LIMIT 1
       ];

       for (EmailMessage em : emails) {
           if (!latestEmailByCase.containsKey(em.ParentId)) {
               latestEmailByCase.put(em.ParentId, em);
           }
       }

       /* -------------------- Org-Wide Email Setup -------------------- */
       Set<String> excludeEmails = new Set<String>();
       String fromAddress = System.Label.CBMDefaultFromEmailAddress;
       Id oweaId;

       if (!String.isBlank(fromAddress)) {
           List<OrgWideEmailAddress> owea = [
               SELECT Id, Address FROM OrgWideEmailAddress
               WHERE Address = :fromAddress LIMIT 1
           ];
           if (!owea.isEmpty()) {
               oweaId = owea[0].Id;
               excludeEmails.add(owea[0].Address.toLowerCase());
           } else {
               excludeEmails.add(fromAddress.toLowerCase());
           }
       }

       excludeEmails.add([SELECT Email FROM User WHERE Id = :UserInfo.getUserId()].Email.toLowerCase());

       EmailTemplate template = [
           SELECT Id FROM EmailTemplate
           WHERE DeveloperName = :TEMPLATE_DEVELOPER_NAME
             AND IsActive = true
           LIMIT 1
       ];

       /* -------------------- Prepare Emails -------------------- */
       List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
       List<Integer> requestIndexes = new List<Integer>();
       List<Id> sentCases = new List<Id>();

       for (Integer i = 0; i < requests.size(); i++) {

           Request req = requests[i];
           Response resp = new Response();
           resp.caseId = req.caseId;

           Case c = caseMap.get(req.caseId);
           EmailMessage lastEm = (c != null) ? latestEmailByCase.get(c.Id) : null;

           if (c == null || lastEm == null) {
               resp.status = 'Skipped';
               resp.message = 'Case or matching email not found.';
               responses.add(resp);
               continue;
           }

           Set<String> lastTo = parseEmails(lastEm.ToAddress);
           Set<String> lastCc = parseEmails(lastEm.CcAddress);

           lastTo.removeAll(excludeEmails);
           lastCc.removeAll(excludeEmails);

           Set<String> finalTo = new Set<String>();
           Set<String> finalCc = new Set<String>(lastCc);

           /* -------------------- Decision Logic -------------------- */
           if (
               c.OverAll_GO_NOGODecision__c == 'Pending' &&
               c.IPMDecision__c == null &&
               c.Sales_Decision__c == null
           ) {
               finalTo.addAll(lastTo);
           }
           else if (c.IPMDecision__c == 'Go' && c.Sales_Decision__c == null) {
               finalTo.addAll(salesEmailsByCase.get(c.Id));
               
           }
           else if (c.IPMDecision__c == null && c.Sales_Decision__c == 'Go') {
               finalTo.addAll(ipmEmailsByCase.get(c.Id));
               
           }

           if (finalTo.isEmpty()) {
               resp.status = 'Skipped';
               resp.message = 'No valid TO recipients after rule evaluation.';
               responses.add(resp);
               continue;
           }

           Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
           mail.setTemplateId(template.Id);
           mail.setTargetObjectId(c.ContactId != null ? c.ContactId : UserInfo.getUserId());
           mail.setTreatTargetObjectAsRecipient(false);
           mail.setWhatId(c.Id);
           mail.setSaveAsActivity(true);
           mail.setToAddresses(new List<String>(finalTo));
           //if (!finalCc.isEmpty()) mail.setCcAddresses(new List<String>(finalCc));
           if (oweaId != null) mail.setOrgWideEmailAddressId(oweaId);
           if (!String.isBlank(fromAddress)) mail.setReplyTo(fromAddress);

           mails.add(mail);
           requestIndexes.add(i);
       }

       /* -------------------- Send Emails -------------------- */
       if (!mails.isEmpty()) {
           Messaging.SendEmailResult[] results = Messaging.sendEmail(mails);

           for (Integer i = 0; i < results.size(); i++) {
               Response resp = new Response();
               Request req = requests[requestIndexes[i]];
               resp.caseId = req.caseId;

               if (results[i].isSuccess()) {
                   resp.status = 'Sent';
                   resp.message = 'Email sent successfully.';
                   sentCases.add(req.caseId);
               } else {
                   resp.status = 'Failed';
                   resp.message = results[i].getErrors()[0].getMessage();
               }
               responses.add(resp);
           }
       }

       /* -------------------- Update Reminder Sent Date -------------------- */
       if (!sentCases.isEmpty()) {
           Datetime nowTs = System.now();
           List<Case> updates = new List<Case>();
           for (Id cid : new Set<Id>(sentCases)) {
               updates.add(new Case(Id = cid, ReminderSentDate__c = nowTs));
           }
           try { update updates; } catch (Exception e) {}
       }

       return responses;
   }

  
   /**
    * @description Parses a delimited string of email addresses into a normalized, unique set.
    * @param raw Comma/semicolon delimited email string (may be null/blank).
    * @return Set<String> unique lowercase trimmed email addresses containing '@'.
    */
   private static Set<String> parseEmails(String raw) {
       Set<String> out = new Set<String>();
       if (String.isBlank(raw)) return out;
       for (String token : raw.split('[,;]')) {
           String e = (token == null) ? null : token.trim().toLowerCase();
           if (!String.isBlank(e) && e.contains('@')) {
               out.add(e);
           }
       }
       return out;
   }



}