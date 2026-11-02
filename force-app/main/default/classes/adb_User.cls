/**
 * @description Domain Builder for the User SObject.
 *              Provides a fluent API for creating test User records.
 *              Defaults are cloned from the running user so the inserted User
 *              is valid in any org without hard-coded profile or locale values.
 */
@IsTest
public class adb_User extends adb_DomainBuilder {

    /**
     * @description Constructs a User builder with defaults cloned from the running user.
     */
    public adb_User() {
        super(User.SObjectType);

        // Clone locale/encoding settings from the running user so the record is org-agnostic
        User runningUser = [
            SELECT ProfileId, TimeZoneSidKey, LocaleSidKey, EmailEncodingKey, LanguageLocaleKey
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];

        String uniqueKey = String.valueOf(DateTime.now().getTime());

        set(User.Alias,             'tstuser');
        set(User.Email,             'testuser' + uniqueKey + '@example.com.invalid');
        set(User.EmailEncodingKey,  runningUser.EmailEncodingKey);
        set(User.LastName,          'TestUser');
        set(User.LanguageLocaleKey, runningUser.LanguageLocaleKey);
        set(User.LocaleSidKey,      runningUser.LocaleSidKey);
        set(User.ProfileId,         runningUser.ProfileId);
        set(User.TimeZoneSidKey,    runningUser.TimeZoneSidKey);
        set(User.Username,          'testuser.' + uniqueKey + '@example.com.invalid');
    }

    /**
     * @description Sets the Alias.
     * @param value The alias value (max 8 characters).
     * @return This builder instance.
     */
    public adb_User alias(String value) {
        return (adb_User) set(User.Alias, value);
    }

    /**
     * @description Sets the Email address.
     * @param value The email value.
     * @return This builder instance.
     */
    public adb_User email(String value) {
        return (adb_User) set(User.Email, value);
    }

    /**
     * @description Sets the First Name.
     * @param value The first name value.
     * @return This builder instance.
     */
    public adb_User firstName(String value) {
        return (adb_User) set(User.FirstName, value);
    }

    /**
     * @description Sets the Last Name.
     * @param value The last name value.
     * @return This builder instance.
     */
    public adb_User lastName(String value) {
        return (adb_User) set(User.LastName, value);
    }

    /**
     * @description Sets the Username (must be globally unique and in email format).
     * @param value The username value.
     * @return This builder instance.
     */
    public adb_User username(String value) {
        return (adb_User) set(User.Username, value);
    }

    /**
     * @description Sets the Profile by Id.
     * @param profileId The Profile Id.
     * @return This builder instance.
     */
    public adb_User profileId(Id profileId) {
        return (adb_User) set(User.ProfileId, profileId);
    }
}