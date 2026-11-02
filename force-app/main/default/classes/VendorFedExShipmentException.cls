/**
 * @description Business-context exception for Vendor FedEx shipment callouts and persistence.
 *              Callers log with Nebula Logger, then throw this type so Apex Jobs shows the
 *              FedEx/Boomi message instead of a platform exception.
 * @author Uptima Development Team
 * @date 2026-08-13
 * @group Exceptions
 */
public class VendorFedExShipmentException extends Exception {
}