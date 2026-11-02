/**
 * GC-3420 - Exception raised by the serialized TAE work-item pipeline.
 * @author Suraj Thapliyal
 * @date 2026/09/29
 *
 * @group Temporary Access Exception
 *
 * @description
 * GC-3420 - Checked failure for the work-item grant, revoke, and cleanup jobs.
 * Callers throw this when a TAE is missing, a batch scope is invalid, or a phase cannot continue.
 */
public class TAEWorkItemException extends Exception {
    /**
     * @description Builds an exception whose message can include record ids.
     * @param message Text stored on the exception.
     * @return New TAEWorkItemException.
     */
    public static TAEWorkItemException create(String message) {
        TAEWorkItemException created = new TAEWorkItemException(message);
        return created;
    }
}