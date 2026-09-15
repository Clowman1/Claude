trigger LeadConversionGuard on Lead (before update) {
    // Before update rather than after: the conversion has to be refused, not undone.
    LeadConversionGuardService.blockConversionWithOpenConditions(Trigger.new, Trigger.oldMap);
}
