/**
 * @description GW-375 - Links a committed Mobile Device Picture to the parent work order.
 */
trigger MobileDevicePictureLinkTrigger on MobileDevicePictureLink__e (after insert) {
    MobileDevicePictureLinkHandler.linkFromEvents(Trigger.new);
}