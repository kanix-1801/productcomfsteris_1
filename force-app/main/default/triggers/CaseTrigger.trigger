/**
 * @description Trigger for Case object following KevinOHara80 framework.
 *              Single trigger per object pattern - delegates all logic to CaseTriggerHandler.
 *              Follows STERIS enterprise architecture standards.
 * @author STERIS
 * @date 2026-04-22
 */
trigger CaseTrigger on Case (before insert, before update, before delete, 
                               after insert, after update, after delete, after undelete) {
    new CaseTriggerHandler().run();
}