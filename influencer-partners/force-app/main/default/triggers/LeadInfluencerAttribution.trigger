trigger LeadInfluencerAttribution on Lead (before insert, after insert) {
    if (Trigger.isBefore) LeadInfluencerAttribution.beforeInsert(Trigger.new);
    else LeadInfluencerAttribution.afterInsert(Trigger.new);
}
