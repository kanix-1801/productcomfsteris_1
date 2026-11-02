/**
 * @author PSL
 * @date 01-02-2026
 * @description Helper for EmailMessage post-send processing. Evaluates outbound SDN emails on Case
 *              and flags related Order Items as MailSent__c when appropriate. Encapsulates logic
 *              reused by EmailMessage triggers/handlers.
 */
public Without sharing class EmailMessageHelper {
		/**
             * @description Helper engine to evaluate EmailMessage sent and perform relative actions on related objects after email sent.
             * @EmailMessage
             * @author PSL
             * @date 01-02-2026
             * @notes
             * - Loads active mail sent on case.
             * - supports email Message
        */

    public static void orderLineFlagSet(List<EmailMessage> em){
        try{
            List<OrderItem> oli = new List<OrderItem>();
             Set<Id> caseIds = new Set<Id>(); // CBM-236
            if(em!=null){
                for(EmailMessage emailM: em){
                    Boolean isOutbound = (emailM.Incoming == false);
                    Boolean hasCaseParent = (emailM.ParentId != null);
                    Boolean subjectMatches = (emailM.Subject != null && emailM.Subject.contains('STERIS Ship Date Notification'));
                    Boolean isCase = false;
                    if(hasCaseParent){
                        isCase = String.valueOf(emailM.ParentId).startsWith('500');
                    }	
                    
                    if(isOutbound && hasCaseParent && subjectMatches && isCase){
                        oli.addAll(EmailControllerHelper.equipmentShippingDetails(emailM.parentID));
                        oli.addAll(EmailControllerHelper.tradeInEquipmentDetails(emailM.parentID));
                        caseIds.add(emailM.ParentId); // CBM-236
                    }
                }
                
              // if (oli.isEmpty()) return;
                if (oli.isEmpty() && caseIds.isEmpty()) return; // CBM-236
                            
                Map<Id, OrderItem> uniq = new Map<Id, OrderItem>();
                for (OrderItem oi : oli) {
                    if (oi.Id != null && oi.MailSent__c == false) { 
                        oi.MailSent__c = true;
                        uniq.put(oi.Id, oi);
                    }
                }
                
                if (!uniq.isEmpty()) {
                    Database.update(uniq.values(), true);
                }
                // CBM-236
                if(!caseIds.isEmpty()){
                    Map<Id, Id> caseToContactMap = new Map<Id, Id>();
                    
                    for(CaseContactRole ccr : [
                        SELECT CasesId, ContactId
                        FROM CaseContactRole
                        WHERE Role = 'Receiving Contact'
                        AND CasesId IN :caseIds
                    ]){
                        if(!caseToContactMap.containsKey(ccr.CasesId)){
                            caseToContactMap.put(ccr.CasesId, ccr.ContactId);
                        }
                    }
                    
                    List<Case> casesToUpdate = new List<Case>();
                    for(Id caseId : caseToContactMap.keySet()){
                        casesToUpdate.add(new Case(
                            Id = caseId,
                            ContactId = caseToContactMap.get(caseId)
                        ));
                    }
                    
                    if(!casesToUpdate.isEmpty()){
                        update casesToUpdate;
                    }
            }
            }
        } catch(Exception ex){
            ErrorLogger.logException(ex, 'EmailMessageHelper', 'orderLineFlagSet');
            throw ex;
        }
    }
    
    
    /**
             * @description Helper engine to evaluate EmailMessage sent and perform relative actions on related objects after email sent.
             * @EmailMessage
             * @author PSL
             * @date 2026-01-16
             * @notes
             * - Loads active mail sent on case.
             * - supports email Message
        */   
            public static void setCaseGoNoGoDecision(List<EmailMessage> emList) {
                if (emList == null || emList.isEmpty()) return;
            
                try {
                    Set<String> ipmGo     = parseLabel(System.Label.IPMGoPermissionKeyword);
                    Set<String> ipmNoGo   = parseLabel(System.Label.IPMNoGoPermissionKeyword);
                    Set<String> salesGo   = parseLabel(System.Label.SalesGoPermissionKeyword);
                    Set<String> salesNoGo = parseLabel(System.Label.SalesNoGoPermissionKeyword);

                    Set<String> breakTokens = parseLabel(System.Label.EmailBreakPoint);

            
                    Map<Id, Case> caseUpdates = new Map<Id, Case>();
            
                    for (EmailMessage em : emList) {
                        if (em == null) continue;
            
                        if (em.Incoming != true) continue;
                        if (em.ParentId == null || String.valueOf(em.ParentId).left(3) != '500') continue;
            
                        String raw = em.TextBody;
                        if (String.isBlank(raw)) raw = em.HtmlBody;
                        if (String.isBlank(raw))  continue;
            
                        String body = normalizeBody(raw);

                        //Breaker 
                        
                        if (!breakTokens.isEmpty()) {
                            Integer stopAt = firstIndexOfAny(body, breakTokens);
                            if (stopAt != -1) {
                                body = body.substring(0, stopAt);
                            }
                        }
            
                        String ipmDecision   = pickDecisionByFirst(body, ipmGo,   ipmNoGo);
                        String salesDecision = pickDecisionByFirst(body, salesGo, salesNoGo);
            
                        if (ipmDecision != null || salesDecision != null) {
                            Case toUpd = caseUpdates.get(em.ParentId);
                            if (toUpd == null) {
                                toUpd = new Case(Id = em.ParentId);
                                caseUpdates.put(em.ParentId, toUpd);
                            }
                            if (ipmDecision   != null) toUpd.IPMdecision__c    = ipmDecision;
                            if (salesDecision != null) toUpd.Sales_Decision__c = salesDecision;
                        }
                    }
            
                    if (!caseUpdates.isEmpty()) {
                        update caseUpdates.values();
                        /*//CBM-819
                        list<order> ordListForTaskCreation= [select id, orderNumber__C,parentCase__r.OverAll_GO_NOGODecision__c from order where parentCase__C IN: caseUpdates.keySet()];
                        
                        list<string> orderNumbers= new list<string>();
                        for (Order o : ordListForTaskCreation) {
                            if (o.OrderNumber__c != null && o.parentCase__r.OverAll_GO_NOGODecision__c== 'NO-GO') {
                                
                                orderNumbers.add(o.OrderNumber__c);
                            }
                        }
                        
                        if(!orderNumbers.isEmpty()){
                            CreateTaskHandler.createTasksForOrder(orderNumbers);
                            CreateTaskHandler.calculateTaskSLA(orderNumbers);
                        }*/                       

                    }
            
                } catch (Exception ex) {
                    ErrorLogger.logException(ex, 'EmailMessageHelper', 'setCaseGoNoGodescion');
                    throw ex;
                }
            }
            
           
            private class NoWsPack {
                public String noWs;
                public List<Integer> mapToOriginal;
            }
            private static NoWsPack toNoWsWithMap(String content) {
                NoWsPack pack = new NoWsPack();
                pack.noWs = '';
                pack.mapToOriginal = new List<Integer>();
            
                for (Integer i = 0; i < content.length(); i++) {
                    String ch = content.substring(i, i + 1);
                    if (ch != ' ') {
                        pack.noWs += ch;
                        pack.mapToOriginal.add(i);
                    }
                }
                return pack;
            }
            
            /**
             * Return the earliest (smallest) index of any phrase in `phrases` within `content`.
             * We search in the normalized content and also in a "no-whitespace" variant to
             * handle HTML-split tokens like `sales:<b>go</b>` that normalize to `sales: go`.
             * If matched in noWs, we map back to the original index using the map.
             * Returns -1 if none found.
             */
            private static Integer firstIndexOfAny(String content, Set<String> phrases) {
                if (String.isBlank(content) || phrases == null || phrases.isEmpty()) return -1;
            
                Integer best = -1;
            
                
                for (String phrase : phrases) {
                    if (String.isBlank(phrase)) continue;
                    Integer idx = content.indexOf(phrase);
                    if (idx != -1) {
                        if (best == -1 || idx < best) best = idx;
                    }
                }
            
                
                NoWsPack pack = toNoWsWithMap(content);
                for (String phrase : phrases) {
                    if (String.isBlank(phrase)) continue;
                    String phraseNoWs = phrase.replaceAll('\\s+', '');
                    Integer idx2 = pack.noWs.indexOf(phraseNoWs);
                    if (idx2 != -1) {
                        
                        Integer mappedStart = pack.mapToOriginal[idx2];
                        if (best == -1 || mappedStart < best) best = mappedStart;
                    }
                }
                return best;
            }
            
            /**
             * Decide between NO-GO and GO by whichever appears *earliest* in the body.
             * Returns 'NO-GO', 'GO', or null (if neither appears).
             * Tie (same starting index) defaults to 'NO-GO' as conservative.
             */
            private static String pickDecisionByFirst(String content, Set<String> phrasesGo, Set<String> phrasesNoGo) {
                Integer firstGo   = firstIndexOfAny(content, phrasesGo);
                Integer firstNoGo = firstIndexOfAny(content, phrasesNoGo);
            
                if (firstGo == -1 && firstNoGo == -1) return null;
                if (firstGo == -1) return 'NO-GO';
                if (firstNoGo == -1) return 'GO';
            
                if (firstGo < firstNoGo)  return 'GO';
                if (firstNoGo < firstGo)  return 'NO-GO';
                return 'NO-GO'; // tie-breaker
            }

    
        
        private static Set<String> parseLabel(String labelValue) {
            Set<String> out = new Set<String>();
            if (String.isBlank(labelValue)) return out;
            for (String token : labelValue.split('[,;|]')) {
                String t = token != null ? token.trim().toLowerCase() : null;
                if (!String.isBlank(t)) out.add(t);
            }
            return out;
        }
    
        
        private static String normalizeBody(String s) {
            String p = s;
            if (p.contains('<') && p.contains('>')) {
                p = p.replaceAll('<[^>]*>', ' ');
            }
            p = p.toLowerCase();
            p = p.replace('&nbsp;', ' ');
            p = p.replaceAll('[\\s\\u00A0]+', ' ').trim();
            return p;
        }
    
       
    
    
    /**
             * @description Helper engine to evaluate EmailMessage sent and perform relative actions on related objects after email sent.
             * @EmailMessage
             * @author PSL
             * @date 2026-01-19
             * @notes
             * - Loads active mail sent on case.
             * - supports email Message
        */
    
    
public static void goNoGoReminderDates(List<EmailMessage> emails){
    try {
        if (emails == null || emails.isEmpty()) return;

        final String SUBJECT_MARKER = 'response required: go/no-go:';

        Map<Id, Datetime> caseIdToSendDate = new Map<Id, Datetime>();

        for (EmailMessage em : emails) {
            if (em == null) continue;

            
            if (String.isBlank(em.Subject)) continue;
            String subjLc = em.Subject.toLowerCase();
            if (!subjLc.contains(SUBJECT_MARKER)) continue;

            if (em.ParentId == null || !String.valueOf(em.ParentId).startsWith('500')) continue;

            Datetime sentDt = (em.MessageDate != null) ? em.MessageDate : System.now();

            Datetime existing = caseIdToSendDate.get(em.ParentId);
            if ((existing == null || sentDt > existing)&& em.incoming==false) {
                caseIdToSendDate.put(em.ParentId, sentDt);
            }
        }

        if (caseIdToSendDate.isEmpty()) {
            return;
        }

        List<Case> existingCases = [
            SELECT Id, GoNoGoSentDate__c, ReminderSentDate__c
            FROM Case
            WHERE Id IN :caseIdToSendDate.keySet()
        ];

        List<Case> toUpdate = new List<Case>();
        for (Case c : existingCases) {
            Datetime dt = caseIdToSendDate.get(c.Id);
            Date goNoGoDate = dt.date();

            Boolean changed = false;
            Case upd = new Case(Id = c.Id);

            if (c.GoNoGoSentDate__c == null) {
                upd.GoNoGoSentDate__c = goNoGoDate;
                changed = true;
            }

            if (c.ReminderSentDate__c == null || c.ReminderSentDate__c < dt) {
                upd.ReminderSentDate__c = dt;
                changed = true;
            }

            if (changed) toUpdate.add(upd);
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }

    } catch (Exception ex) {
        ErrorLogger.logException(ex, 'EmailMessageHelper', 'goNoGoReminderDates');
        throw ex;
    }
}


    /**
     * @description Clears the RelationId field from EmailMessageRelation records associated with the supplied Email Messages.
     * This method is executed asynchronously to avoid impacting the current transaction and is primarily used when existing Email Message relations need to be removed.
     *
     */
    @future
    public static void nullifyRelationId(Set<Id> emailMessageIds) {
        try {
            if (emailMessageIds.isEmpty()) {
                return;
            }

            // Retrieve related Email Message Relations.
            List<EmailMessageRelation> relationsToUpdate = [
                SELECT Id, RelationId
                FROM EmailMessageRelation
                WHERE EmailMessageId IN :emailMessageIds
            ];

            if (relationsToUpdate.isEmpty()) {
                return;
            }

            // Clear existing Relation references.
            for (EmailMessageRelation relation : relationsToUpdate) {
                relation.RelationId = null;
            }

            update relationsToUpdate;

        } catch (Exception ex) {
            ErrorLogger.logException(ex, 'EmailMessageHelper', 'nullifyRelationId');
            throw ex;
        }
    }

}