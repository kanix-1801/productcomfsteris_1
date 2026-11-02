/**
 * @description GW-1206: Retrieves the Return Order RO Form and Shipping Label,
 *              merges them into a single PDF, and opens it for printing.
 *              Displays an error when either required document is missing.
 */
import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { loadScript } from 'lightning/platformResourceLoader';

import PDF_LIB from '@salesforce/resourceUrl/pdfLib';

import getPrintDocuments from '@salesforce/apex/ReturnOrderPrintController.getPrintDocuments';

export default class PrintRO extends LightningElement {

    _recordId;

    hasCheckedDocuments = false;
    pdfLibLoaded = false;

    message;

    @api
    set recordId(value) {

        this._recordId = value;

        console.log(
            'recordId received:',
            value
        );

        // Initialize once the Return Order record Id is available.
        if (
            value &&
            !this.hasCheckedDocuments
        ) {

            this.hasCheckedDocuments = true;

            this.initialize();
        }
    }

    get recordId() {
        return this._recordId;
    }

    /**
     * Loads pdf-lib and retrieves the Return Order documents.
     */
    async initialize() {

        try {

            await this.loadPdfLib();

            await this.checkDocuments();

        } catch (error) {

            console.error(
                'Error initializing Print All:',
                error
            );

            this.message =
                error?.body?.message ||
                error?.message ||
                'Unable to initialize the Print All action.';
        }
    }

    /**
     * Loads the pdf-lib Static Resource.
     */
    async loadPdfLib() {

        if (this.pdfLibLoaded) {
            return;
        }

        await loadScript(
            this,
            PDF_LIB
        );

        // pdf-lib exposes PDFDocument through window.PDFLib.
        if (
            !window.PDFLib ||
            !window.PDFLib.PDFDocument
        ) {

            throw new Error(
                'pdf-lib loaded, but PDFLib could not be found.'
            );
        }

        this.pdfLibLoaded = true;

        console.log(
            'pdf-lib loaded successfully.'
        );
    }

    /**
     * Retrieves the latest RO Form and Shipping Label from Apex.
     */
    async checkDocuments() {

        try {

            console.log(
                'Checking documents for Return Order:',
                this.recordId
            );

            const result =
                await getPrintDocuments({
                    returnOrderId: this.recordId
                });

            console.log(
                'Print Documents:',
                result
            );

            // Stop if one or both required documents are missing.
            if (
                result.missingDocuments &&
                result.missingDocuments.length > 0
            ) {

                this.showMissingFilesMessage(
                    result.missingDocuments
                );

                return;
            }

            // Make sure both PDF files were returned by Apex.
            if (
                !result.roFormBase64 ||
                !result.shippingLabelBase64
            ) {

                throw new Error(
                    'One or more required PDF documents could not be retrieved.'
                );
            }

            console.log(
                'RO Form Base64 length:',
                result.roFormBase64.length
            );

            console.log(
                'Shipping Label Base64 length:',
                result.shippingLabelBase64.length
            );

            await this.openPdf(
                result.roFormBase64,
                result.shippingLabelBase64
            );

        } catch (error) {

            console.error(
                'Error checking documents:',
                error
            );

            this.message =
                error?.body?.message ||
                error?.message ||
                'An unexpected error occurred while preparing the documents.';
        }
    }

    /**
     * Displays a message when required documents are missing.
     */
    showMissingFilesMessage(missingFiles) {

        if (
            missingFiles.includes('RO Form') &&
            missingFiles.includes('Shipping Label')
        ) {

            this.message =
                'The RO Form and Shipping Label could not be found for this Return Order. Please generate the required documents before trying again.';

        } else if (
            missingFiles.includes('RO Form')
        ) {

            this.message =
                'The RO Form could not be found for this Return Order. Please generate the RO Form before trying again.';

        } else {

            this.message =
                'The Shipping Label could not be found for this Return Order. Please generate the Shipping Label before trying again.';
        }
    }

    /**
     * Merges the RO Form and Shipping Label into one PDF
     * and opens the result in a new browser tab.
     */
    async openPdf(
        roFormBase64,
        shippingLabelBase64
    ) {

        // Open the tab immediately to avoid the browser blocking the popup.
        const newTab =
            window.open(
                'about:blank',
                '_blank'
            );

        try {

            if (!newTab) {

                throw new Error(
                    'The browser blocked the new tab. Please allow pop-ups for Salesforce and try again.'
                );
            }

            console.log(
                'Converting RO Form to PDF bytes...'
            );

            const roFormBytes =
                this.base64ToUint8Array(
                    roFormBase64
                );

            console.log(
                'Converting Shipping Label to PDF bytes...'
            );

            const shippingLabelBytes =
                this.base64ToUint8Array(
                    shippingLabelBase64
                );

            const PDFDocument =
                window.PDFLib.PDFDocument;

            console.log(
                'Creating merged PDF...'
            );

            const mergedPdf =
                await PDFDocument.create();

            // Load both source PDFs.
            const roFormPdf =
                await PDFDocument.load(
                    roFormBytes
                );

            const shippingLabelPdf =
                await PDFDocument.load(
                    shippingLabelBytes
                );

            // Add RO Form pages first.
            const roFormPages =
                await mergedPdf.copyPages(
                    roFormPdf,
                    roFormPdf.getPageIndices()
                );

            roFormPages.forEach(
                page => {
                    mergedPdf.addPage(page);
                }
            );

            // Add Shipping Label pages after the RO Form.
            const shippingLabelPages =
                await mergedPdf.copyPages(
                    shippingLabelPdf,
                    shippingLabelPdf.getPageIndices()
                );

            shippingLabelPages.forEach(
                page => {
                    mergedPdf.addPage(page);
                }
            );

            console.log(
                'Saving merged PDF...'
            );

            // Generate the final merged PDF.
            const mergedPdfBytes =
                await mergedPdf.save();

            // Create a temporary browser PDF. This is not saved to Salesforce.
            const pdfBlob =
                new Blob(
                    [mergedPdfBytes],
                    {
                        type: 'application/pdf'
                    }
                );

            // Create a temporary URL for the merged PDF.
            const pdfUrl =
                URL.createObjectURL(
                    pdfBlob
                );

            console.log(
                'Opening merged PDF...'
            );

            // Display the merged PDF in the already-open browser tab.
            newTab.location.href =
                pdfUrl;

            // Close the Salesforce Quick Action.
            this.dispatchEvent(
                new CloseActionScreenEvent()
            );

        } catch (error) {

            console.error(
                'Unable to merge/open PDFs:',
                error
            );

            console.error(
                'Error name:',
                error?.name
            );

            console.error(
                'Error message:',
                error?.message
            );

            console.error(
                'Error stack:',
                error?.stack
            );

            // Close the blank tab if PDF processing fails.
            if (newTab) {
                newTab.close();
            }

            this.message =
                error?.message ||
                'Unable to prepare the Return Order documents.';
        }
    }

    /**
     * Converts Base64 PDF data into Uint8Array bytes for pdf-lib.
     */
    base64ToUint8Array(
        base64String
    ) {

        const byteCharacters =
            window.atob(
                base64String
            );

        const byteNumbers =
            new Array(
                byteCharacters.length
            );

        for (
            let i = 0;
            i < byteCharacters.length;
            i++
        ) {

            byteNumbers[i] =
                byteCharacters.charCodeAt(i);
        }

        return new Uint8Array(
            byteNumbers
        );
    }

    /**
     * Closes the Salesforce Quick Action.
     */
    handleClose() {

        this.dispatchEvent(
            new CloseActionScreenEvent()
        );
    }
}