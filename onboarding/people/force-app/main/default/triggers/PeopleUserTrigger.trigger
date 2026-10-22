// People app: a new Salesforce user (or a changed email) may match a People employee's work email; PeopleUserSync links them.
trigger PeopleUserTrigger on User (after insert, after update) {
    for (User u : Trigger.new) {
        if (Trigger.isInsert || u.Email != Trigger.oldMap.get(u.Id).Email) {
            PeopleUserSync.start();
            return;
        }
    }
}
