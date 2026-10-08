trigger LeadBdAttribution on Lead (before insert, before update) {
    LeadBdAttribution.apply(Trigger.new, Trigger.oldMap);
}