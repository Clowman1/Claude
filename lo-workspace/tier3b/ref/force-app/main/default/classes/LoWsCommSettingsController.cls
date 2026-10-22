/**
 * LO Workspace Communication Settings modal + the per-contact "automated texts" switch (c/loWsTextsSwitch).
 * See LoWsAutoTextService. Writes run in SYSTEM_MODE (LOs have no FLS on LoWs_ fields), so every switch call
 * first checks the LO can see the page's record, and only switches that record's own contacts.
 */
public with sharing class LoWsCommSettingsController {

    public class TextSwitch {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String label;
        @AuraEnabled public String name;
        @AuraEnabled public Boolean off;
        TextSwitch(Id recordId, String label, String name, Boolean off) {
            this.recordId = recordId;
            this.label = label;
            this.name = name;
            this.off = off == true;
        }
    }

    @AuraEnabled
    public static List<LoWsAutoTextService.Def> getSettings() {
        try {
            return LoWsAutoTextService.settingsFor(UserInfo.getUserId());
        } catch (Exception e) {
            throw aura(e);
        }
    }

    @AuraEnabled
    public static List<LoWsAutoTextService.Def> saveSetting(String key, Boolean enabled, String body) {
        try {
            LoWsAutoTextService.saveSetting(UserInfo.getUserId(), key, enabled, body);
            return LoWsAutoTextService.settingsFor(UserInfo.getUserId());
        } catch (Exception e) {
            throw aura(e);
        }
    }

    /** Lead / Account page: that contact. Loan page: its borrower and buyer's agent. */
    @AuraEnabled
    public static List<TextSwitch> getTextSwitches(Id recordId) {
        try {
            return switchesFor(recordId);
        } catch (Exception e) {
            throw aura(e);
        }
    }

    @AuraEnabled
    public static List<TextSwitch> setTextsOff(Id contextId, Id targetId, Boolean off) {
        try {
            Boolean allowed = false;
            for (TextSwitch s : switchesFor(contextId)) {
                allowed = allowed || s.recordId == targetId;
            }
            if (!allowed) {
                throw new DomainException('This contact is not on this record.');
            }
            LoWsAutoTextService.setTextsOff(targetId, off);
            return switchesFor(contextId);
        } catch (Exception e) {
            throw aura(e);
        }
    }

    static List<TextSwitch> switchesFor(Id recordId) {
        SObjectType t = recordId?.getSObjectType();
        if (t != Lead.SObjectType && t != Account.SObjectType && t != Transaction__c.SObjectType) {
            throw new DomainException('Texts can only be switched off for a lead, contact or loan.');
        }
        String objectName = String.valueOf(t);
        if (Database.query('SELECT Id FROM ' + objectName + ' WHERE Id = :recordId', AccessLevel.USER_MODE).isEmpty()) {
            throw new DomainException('You don\'t have access to this record.');
        }
        List<TextSwitch> result = new List<TextSwitch>();
        if (t == Lead.SObjectType) {
            Lead l = [SELECT Id, Name, LoWs_Texts_Off__c FROM Lead WHERE Id = :recordId WITH SYSTEM_MODE];
            result.add(new TextSwitch(l.Id, 'Borrower', l.Name, l.LoWs_Texts_Off__c));
        } else if (t == Account.SObjectType) {
            Account a = [SELECT Id, Name, LoWs_Texts_Off__c FROM Account WHERE Id = :recordId WITH SYSTEM_MODE];
            result.add(new TextSwitch(a.Id, null, a.Name, a.LoWs_Texts_Off__c));
        } else {
            Transaction__c loan = [
                SELECT Borrower_Name__c, Borrower_Name__r.Name, Borrower_Name__r.LoWs_Texts_Off__c,
                    Realtor_Buying_Agent__c, Realtor_Buying_Agent__r.Name, Realtor_Buying_Agent__r.LoWs_Texts_Off__c
                FROM Transaction__c WHERE Id = :recordId WITH SYSTEM_MODE
            ];
            if (loan.Borrower_Name__c != null) {
                result.add(new TextSwitch(loan.Borrower_Name__c, 'Borrower', loan.Borrower_Name__r.Name, loan.Borrower_Name__r.LoWs_Texts_Off__c));
            }
            if (loan.Realtor_Buying_Agent__c != null) {
                result.add(new TextSwitch(loan.Realtor_Buying_Agent__c, 'Buyer\'s agent', loan.Realtor_Buying_Agent__r.Name,
                    loan.Realtor_Buying_Agent__r.LoWs_Texts_Off__c));
            }
        }
        return result;
    }

    static AuraHandledException aura(Exception e) {
        String message = e instanceof DomainException ? e.getMessage() : 'Something went wrong. Please try again.';
        AuraHandledException wrapped = new AuraHandledException(message);
        wrapped.setMessage(message);
        return wrapped;
    }
}