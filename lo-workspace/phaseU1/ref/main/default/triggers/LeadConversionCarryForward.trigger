/**
 * Carries a Lead's conditions and documents onto its Transaction the moment the link is stamped.
 *
 * This deliberately does NOT rely on the record-triggered flow that used to do it. Convert_Lead
 * stamps Converted_Transaction_ID__c in an Update_Lead step that runs AFTER the conversion, so the
 * update lands on an already-converted Lead - and on the Hall - 1526410724 file that flow did not
 * fire, leaving all 24 documents on the Person Account and nothing on the Transaction. An Apex
 * trigger fires on that update whatever state the Lead is in.
 *
 * Wrapped end to end: carrying documents forward must never be the reason a conversion fails.
 * If it does fail, LeadConversionCarryForwardSweeper picks the file up within twelve hours.
 */
trigger LeadConversionCarryForward on Lead (after update) {
    Set<Id> newlyLinked = new Set<Id>();
    for (Lead updatedLead : Trigger.new) {
        Lead priorLead = Trigger.oldMap.get(updatedLead.Id);
        if (updatedLead.Converted_Transaction_ID__c == null) {
            continue;
        }
        // Newly stamped, or re-pointed at a different Transaction - both need the documents moved.
        if (priorLead == null
            || priorLead.Converted_Transaction_ID__c != updatedLead.Converted_Transaction_ID__c) {
            newlyLinked.add(updatedLead.Id);
        }
    }

    if (newlyLinked.isEmpty()) {
        return;
    }

    try {
        LeadDocumentCarryForwardService.carryForward(newlyLinked);
    } catch (Exception carryFailure) {
        System.debug(
            LoggingLevel.ERROR,
            'Carry-forward failed at conversion for ' + newlyLinked + ': ' + carryFailure.getMessage()
        );
    }

    // SSN, DOB, income, value, loan amount -> Person Account; subject property -> Transaction.
    try {
        LeadConversionFieldCarry.carry(newlyLinked);
    } catch (Exception fieldFailure) {
        System.debug(
            LoggingLevel.ERROR,
            'Field carry failed at conversion for ' + newlyLinked + ': ' + fieldFailure.getMessage()
        );
    }
}