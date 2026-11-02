/**
 * @description	 : User trigger responsible for initiating inactive Sales User assignment cleanup processing.
 * @author		 : Vinay
 * @date 		 : 2026-06-12
 */
trigger UserTrigger on User (after update) {
    new UserTriggerHandler().run(); 
}