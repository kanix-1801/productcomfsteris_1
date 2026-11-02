/**
 * @description Business-context exception for Summit skill integration batch processing and related utilities.
 *              Callers catch platform exceptions, log with Nebula Logger, then throw this type to surface integration context.
 */
public class SummitSkillIntegrationException extends Exception {}