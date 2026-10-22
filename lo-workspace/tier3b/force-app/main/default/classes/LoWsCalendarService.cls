/**
 * LO Workspace calendar and follow-ups.
 * - getMyEvents: the running user's own Events (OwnerId = me), read in system mode. Feeds the Perfect Day
 *   "Upcoming appointments" card and the Calendar modal (loWsAppointments).
 * - createFollowUp: called by Log communication and Log an activity.
 *     general (tomorrow / 3-days / next-week / date) = an open Task due that day, reminder 8:00 AM user-local.
 *       It shows in Up Next on Perfect Day from that day until it is completed.
 *     exact = a 30-minute Event, reminder 15 minutes before. It shows on the calendar (and in Outlook under EAC).
 *   Never read Subject back: org automation rewrites Task.Subject on update.
 */
public with sharing class LoWsCalendarService {
    public static final String NONE = 'none';
    public static final String EXACT = 'exact';
    public static final String ON_DATE = 'date';
    /** Event.Prompt_Key__c on exact-time follow-up Events (Prompt_Key__c is an Activity field). */
    public static final String FOLLOW_UP_EVENT_KEY = 'follow-up';
    @TestVisible static final Integer MAX_RANGE_DAYS = 62;

    public class EventRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String subject;
        @AuraEnabled public Datetime startAt;
        @AuraEnabled public Datetime endAt;
        @AuraEnabled public Boolean allDay;
        @AuraEnabled public Date allDayDate;
        @AuraEnabled public String location;
        @AuraEnabled public Id relatedId;
        @AuraEnabled public String relatedName;
        @AuraEnabled public String relatedType;
    }

    /** My Events overlapping [startAt, endAt). Blank range = the next 7 days; capped at 62 days. */
    @AuraEnabled
    public static List<EventRow> getMyEvents(Datetime startAt, Datetime endAt) {
        Datetime fromAt = startAt == null ? System.now() : startAt;
        Datetime toAt = endAt == null || endAt <= fromAt ? fromAt.addDays(7) : endAt;
        if (toAt > fromAt.addDays(MAX_RANGE_DAYS)) {
            toAt = fromAt.addDays(MAX_RANGE_DAYS);
        }
        Id me = UserInfo.getUserId();
        List<EventRow> rows = new List<EventRow>();
        // ponytail: all-day events store midnight GMT, so one can be off by a day at the range edge.
        for (Event e : [
            SELECT Id, Subject, StartDateTime, EndDateTime, IsAllDayEvent, ActivityDate, Location,
                   WhoId, Who.Name, Who.Type, WhatId, What.Name, What.Type
            FROM Event
            WHERE OwnerId = :me AND StartDateTime < :toAt AND EndDateTime > :fromAt
            WITH SYSTEM_MODE
            ORDER BY StartDateTime ASC
            LIMIT 500
        ]) {
            EventRow row = new EventRow();
            row.id = e.Id;
            row.subject = String.isBlank(e.Subject) ? '(No subject)' : e.Subject;
            row.startAt = e.StartDateTime;
            row.endAt = e.EndDateTime;
            row.allDay = e.IsAllDayEvent;
            row.allDayDate = e.IsAllDayEvent ? e.ActivityDate : null;
            row.location = e.Location;
            // A lead beats the What; otherwise the What (loan, account), otherwise the Who (contact).
            Boolean useWho = e.WhoId != null && (e.Who.Type == 'Lead' || e.WhatId == null);
            row.relatedId = useWho ? e.WhoId : e.WhatId;
            row.relatedName = useWho ? e.Who.Name : (e.WhatId == null ? null : e.What.Name);
            row.relatedType = useWho ? e.Who.Type : (e.WhatId == null ? null : e.What.Type);
            rows.add(row);
        }
        return rows;
    }

    /**
     * Creates the follow-up for a log. followUp = none | tomorrow | 3-days | next-week | date:YYYY-MM-DD
     * | exact:<ISO datetime>. One string so the existing Aura signatures stay unchanged.
     * Returns the Task or Event Id, or null for no follow-up.
     */
    public static Id createFollowUp(Id recordId, String followUp) {
        if (String.isBlank(followUp) || followUp == NONE) {
            return null;
        }
        String option = followUp.substringBefore(':');
        String value = followUp.substringAfter(':');
        Date onDate;
        Datetime startAt;
        try {
            if (option == ON_DATE && String.isNotBlank(value)) {
                onDate = Date.valueOf(value);
            }
            if (option == EXACT && String.isNotBlank(value)) {
                startAt = (Datetime) JSON.deserialize('"' + value + '"', Datetime.class);
            }
        } catch (Exception badValue) {
            throw new DomainException('The follow-up date or time is not valid.');
        }
        return createFollowUp(recordId, option, onDate, startAt);
    }

    @TestVisible
    static Id createFollowUp(Id recordId, String option, Date onDate, Datetime startAt) {
        if (recordId == null) {
            throw new DomainException('Pick who the follow-up is with.');
        }
        ExternalLoActivityLogService.requireLoggable(recordId);
        String subject = ('Follow up: ' + recordName(recordId)).left(255);
        Boolean isLead = recordId.getSObjectType() == Lead.SObjectType;
        Id me = UserInfo.getUserId();

        if (option == EXACT) {
            if (startAt == null) {
                throw new DomainException('Pick the date and time for the follow-up.');
            }
            if (startAt < System.now()) {
                throw new DomainException('Pick a follow-up time in the future.');
            }
            Event followUp = new Event(
                OwnerId = me,
                Subject = subject,
                StartDateTime = startAt,
                DurationInMinutes = 30,
                // No reminder pop-up: Up Next / To Do already surface it (decided 2026-10-08).
                IsReminderSet = false,
                WhoId = isLead ? recordId : null,
                WhatId = isLead ? null : recordId,
                // Marks a follow-up, not an appointment: EventTriggerHandler doesn't stamp the lead's
                // Appointment fields and Perfect Day keeps the lead in "New leads to contact".
                Prompt_Key__c = FOLLOW_UP_EVENT_KEY
            );
            Database.insert(new List<Event>{ followUp }, AccessLevel.SYSTEM_MODE);
            return followUp.Id;
        }

        Date due = followUpDate(option, onDate);
        Task followUp = new Task(
            OwnerId = me,
            Subject = subject,
            Status = 'Not Started',
            Priority = 'Normal',
            ActivityDate = due,
            IsReminderSet = false,
            WhoId = isLead ? recordId : null,
            WhatId = isLead ? null : recordId
        );
        Database.insert(new List<Task>{ followUp }, AccessLevel.SYSTEM_MODE);
        return followUp.Id;
    }

    @TestVisible
    static Date followUpDate(String option, Date onDate) {
        Date today = Date.today();
        switch on option {
            when 'tomorrow' { return today.addDays(1); }
            when '3-days' { return today.addDays(3); }
            when 'next-week' { return today.addDays(7); }
            when 'date' {
                if (onDate == null) {
                    throw new DomainException('Pick the follow-up date.');
                }
                if (onDate < today) {
                    throw new DomainException('Pick today or a later date for the follow-up.');
                }
                return onDate;
            }
            when else {
                throw new DomainException('Choose when to follow up.');
            }
        }
    }

    private static String recordName(Id recordId) {
        String objectName = String.valueOf(recordId.getSObjectType());
        List<SObject> rows = Database.queryWithBinds(
            'SELECT Name FROM ' + objectName + ' WHERE Id = :recordId',
            new Map<String, Object>{ 'recordId' => recordId },
            AccessLevel.SYSTEM_MODE
        );
        return rows.isEmpty() ? 'contact' : String.valueOf(rows[0].get('Name'));
    }
}