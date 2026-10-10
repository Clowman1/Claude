/**
 * U8 (2026-10): set true only around the system's own recycled-lead writes (the recycle insert and the
 * reactivation update). Lead triggers that notify, reassign or re-attribute return early while it is set.
 * Flows can't see it; they check Recycled_From_Transaction__c / Recycle_Reactivated_At__c instead.
 */
public with sharing class LeadRecycleContext {
    public static Boolean silent = false;
}