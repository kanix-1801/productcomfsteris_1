/**
 * @author Persistent Developer
 * @date 2026/26/10
 * For story : 1387.
* @description
* This class is used for adding toAddress and ccAddress for the email. 
 */
public with sharing class CaseTeamMemberSelector {
	/**
     * @description      
     * Method is used for getting case team member email related to the calling case.
     *
     * @param caseRecord.
     * @return List of case member email.
     */
    public static List<CaseTeamMember> getCaseTeamMember (case c) {
        List<CaseTeamMember> teamMembers = [select member.Email from CaseTeamMember WHERE ParentId = :c.Id WITH USER_MODE];
        if(!teamMembers.isEmpty())
            return teamMembers;
        return NULL;
    }
}