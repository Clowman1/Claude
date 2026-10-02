// LO Workspace Phase 6: landing-page leads and duplicate alerts (runs as Automated Process).
trigger LoWsIntakeEvent on LO_Workspace_Intake__e (after insert) {
    LoWsLeadIntakeService.handleEvents(Trigger.new);
}
