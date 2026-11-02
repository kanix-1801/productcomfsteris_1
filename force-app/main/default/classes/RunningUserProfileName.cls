/**
 * @description Returns the running user's profile name for Field Service mobile flows,
 *              which cannot reference $Profile or $User.
 */
public with sharing class RunningUserProfileName {
    public class ProfileNameResult {
        @InvocableVariable(label='Profile Name' required=true)
        public String profileName;
    }

    @InvocableMethod(
        label='Get Running User Profile Name'
        description='Returns the profile name of the running user.'
    )
    public static List<ProfileNameResult> getRunningUserProfileName() {
        ProfileNameResult result = new ProfileNameResult();
        result.profileName = [
            SELECT Name
            FROM Profile
            WHERE Id = :UserInfo.getProfileId()
            LIMIT 1
        ].Name;
        return new List<ProfileNameResult>{ result };
    }
}