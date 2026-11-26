/**
 * @author PWC Developer
 * @date 2026-11-25
 * @group Life Sciences
 * @description GCL-74 - Wraps failures in the Life Sciences inactive user cleanup with business context,
 *              so the Apex Jobs page and the Nebula log show which step failed.
 */
public with sharing class LSInactiveUserCleanupException extends Exception {
}