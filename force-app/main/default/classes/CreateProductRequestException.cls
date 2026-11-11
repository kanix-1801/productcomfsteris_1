/**
 * @description User-facing failure while creating or submitting a mobile Product Request.
 */
public with sharing class CreateProductRequestException extends Exception {
    /**
     * @description Builds the exception shown on the mobile screen.
     * @param message User-facing message.
     * @return The exception.
     * @example
     * throw CreateProductRequestException.withMessage(Label.CreateProductRequest_Unexpected);
     */
    public static CreateProductRequestException withMessage(String message) {
        return new CreateProductRequestException(message);
    }
}