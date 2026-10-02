public with sharing class RingSenseSilenceAlertScheduler implements Schedulable {
    public static final String JOB_NAME = 'RingSense Silence Alert';
    public static final String DEFAULT_CRON = '0 0 8 * * ?';

    public void execute(SchedulableContext sc) {
        RingSenseSilenceAlertService.run();
    }

    public static String schedule() {
        return schedule(DEFAULT_CRON);
    }

    public static String schedule(String cronExpression) {
        String jobName = JOB_NAME;
        if (Test.isRunningTest()) {
            jobName += ' - ' + Crypto.getRandomInteger();
        }
        return System.schedule(jobName, cronExpression, new RingSenseSilenceAlertScheduler());
    }
}