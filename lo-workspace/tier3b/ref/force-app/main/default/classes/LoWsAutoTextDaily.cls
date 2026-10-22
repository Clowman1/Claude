/**
 * comms-settings: daily 10am run of the scheduled External LO texts (N5 reminders, B2 birthday, B3 anniversary).
 * Schedule once: System.schedule('LO Workspace Auto Texts - Daily 10am', '0 0 10 * * ?', new LoWsAutoTextDaily());
 */
public without sharing class LoWsAutoTextDaily implements Schedulable {
    public void execute(SchedulableContext context) {
        LoWsAutoTextService.runDaily(Date.today());
    }
}