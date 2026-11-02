/**
 * @author PWC Developer
 * @date 2026/10/16
 *
 * @group CSC Visit
 *
 * @description
 * GC-3564 - Visualforce controller for the CSC Visit PDF.
 */
public with sharing class CSCVisitPdfController {

    public SunshineService.PdfModel pdf { get; private set; }

    /**
     * @description Loads the Visit opened from the PDF page.
     * @param controller Standard controller for the CSC Visit.
     */
    public CSCVisitPdfController(ApexPages.StandardController controller) {
        pdf = SunshineService.buildPdf(controller == null ? null : controller.getId());
    }
}