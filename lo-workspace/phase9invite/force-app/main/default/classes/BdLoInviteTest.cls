/**
 * LO Workspace "In Person Invite" (BdCommandCenterController, scope 'lo'), run as a real outside LO:
 * External Loan Officer Profile + role, no Marketing User, External_LO_Access + the Zoom permsets
 * from the External_Loan_Officer group.
 *
 * Proves: the picker holds only my tags and partner-type accounts I own; the server refuses any
 * other invitee; I host the event I create (Campaign owner + calendar Event owner); I see only my
 * own events; another host's event and invitees are refused; the BD-only path stays closed.
 *
 * SeeAllData: a new campaign's default member statuses are invisible otherwise and the event
 * engine collides with them (same as BdCommandCenterControllerTest / RealtorEventRsvpServiceTest).
 */
@IsTest(SeeAllData=true)
private class BdLoInviteTest {

    static User newExternalLo(Boolean withPerms) { return newExternalLo(withPerms, 'Outside'); }

    static User newExternalLo(Boolean withPerms, String lastName) {
        String suffix = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        User u = new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'External Loan Officer Profile'].Id,
            UserRoleId = [SELECT Id FROM UserRole WHERE DeveloperName = 'External_Loan_Officer'].Id,
            Username = 'p9inv' + suffix + '@reach-p9.test', Email = 'p9inv@reach-p9.test',
            FirstName = 'Olive', LastName = lastName, Alias = 'p9inv',
            TimeZoneSidKey = 'America/New_York', LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
            if (!withPerms) return u;
            List<PermissionSetAssignment> psas = new List<PermissionSetAssignment>();
            for (PermissionSet ps : [
                SELECT Id FROM PermissionSet WHERE Name IN (
                    'External_LO_Access', 'Zoom_Meeting_Sync_Access', 'Zoom_Meeting_Assistant_Access', 'Zoom_OAuth_Connection_Access'
                )
            ]) {
                psas.add(new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id));
            }
            insert psas;
        }
        return u;
    }

    static Account person(String first, String last, Id ownerId, Boolean realtor) {
        return new Account(
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId(),
            FirstName = first, LastName = last, PersonEmail = last.toLowerCase() + '.p9inv@example.com',
            Is_Realtor__c = realtor, OwnerId = ownerId
        );
    }

    static BdCommandCenterController.InviteRequest req(List<Id> partnerIds, String scope) {
        BdCommandCenterController.InviteRequest r = new BdCommandCenterController.InviteRequest();
        r.kind = 'Coffee';
        r.eventDate = Date.today().addDays(4);
        r.eventTime = '08:30';
        r.location = 'Kahwa';
        r.partnerIds = partnerIds;
        r.scope = scope;
        return r;
    }

    static Boolean refused(String op, Object arg) {
        try {
            switch on op {
                when 'invite' { BdCommandCenterController.createInvite((BdCommandCenterController.InviteRequest) arg); }
                when 'event' { BdCommandCenterController.getEvent((Id) arg); }
                when 'resend' { BdCommandCenterController.resendInvite((Id) arg); }
                when 'home' { BdCommandCenterController.getLoInviteHome(); }
            }
        } catch (AuraHandledException e) {
            return true;
        }
        return false;
    }

    @IsTest
    static void outsideLoInvitesOnlyOwnPartnersAndSeesOnlyOwnEvents() {
        User lo = newExternalLo(true);
        Account tagged = person('Tara', 'Taggedp9', UserInfo.getUserId(), true);
        Account stranger = person('Sam', 'Strangerp9', UserInfo.getUserId(), true);
        Account owned = person('Owen', 'Ownedp9', lo.Id, true);
        Account borrower = person('Bo', 'Borrowerp9', lo.Id, false);
        insert new List<Account>{ tagged, stranger, owned, borrower };

        // Someone else's event with the stranger invited.
        Campaign other = new Campaign(Name = 'Coffee: someone else p9', Type = 'Event', IsActive = true, StartDate = Date.today().addDays(2));
        insert other;
        Id strangerContact = [SELECT PersonContactId FROM Account WHERE Id = :stranger.Id].PersonContactId;
        CampaignMember otherMember = new CampaignMember(CampaignId = other.Id, ContactId = strangerContact);
        insert otherMember;

        System.runAs(lo) {
            LoWsPartnerTagService.tagAccounts(new Set<Id>{ tagged.Id });

            BdCommandCenterController.LoInviteHome h = BdCommandCenterController.getLoInviteHome();
            Set<Id> pickable = new Set<Id>();
            for (BdCommandCenterController.Partner p : h.partners) pickable.add(p.id);
            System.assert(pickable.contains(tagged.Id), 'tagged partner is invitable');
            System.assert(pickable.contains(owned.Id), 'own partner-type account is invitable');
            System.assert(!pickable.contains(stranger.Id), 'untagged partner is never offered');
            System.assert(!pickable.contains(borrower.Id), 'own borrower is not a partner');
            System.assertEquals(0, h.upcoming.size());

            System.assert(refused('invite', req(new List<Id>{ tagged.Id, stranger.Id }, 'lo')), 'any foreign invitee refuses the whole invite');
            System.assert(refused('invite', req(new List<Id>{ tagged.Id }, null)), 'the BD book path stays BD-only');
            System.assert(refused('event', other.Id), 'another host\'s event is refused');
            System.assert(refused('resend', otherMember.Id), 'another host\'s invitee is refused');
            System.assertNotEquals(null, BdCommandCenterController.searchCoHosts('zz'));

            Test.startTest();
            Id campaignId = BdCommandCenterController.createInvite(req(new List<Id>{ tagged.Id, owned.Id }, 'lo'));
            Test.stopTest();

            Campaign c = [SELECT OwnerId, Type, Name FROM Campaign WHERE Id = :campaignId];
            System.assertEquals(lo.Id, c.OwnerId, 'the LO hosts their own event');
            System.assertEquals('Event', c.Type);
            System.assertEquals(lo.Id, [SELECT OwnerId FROM Event WHERE WhatId = :campaignId].OwnerId);

            h = BdCommandCenterController.getLoInviteHome();
            System.assertEquals(1, h.upcoming.size(), 'only my own event is listed');
            System.assertEquals(campaignId, h.upcoming[0].campaignId);
            System.assertEquals(2, BdCommandCenterController.getEvent(campaignId).invitees.size());
        }
    }

    @IsTest
    static void usersWithoutLoWorkspaceAreRefused() {
        System.runAs(newExternalLo(false)) {
            System.assert(refused('home', null), 'no External_LO / LO_Workspace_Demo, no invites');
        }
    }

    // LO scope: co-hosts are internal Reach staff only (active Standard users outside the External LO role).
    @IsTest
    static void outsideLoCoHostsAreInternalStaffOnly() {
        User lo = newExternalLo(true);
        User otherLo = newExternalLo(false, 'Cohostp9');
        User me = [SELECT ProfileId FROM User WHERE Id = :UserInfo.getUserId()];
        User staff = new User(
            ProfileId = me.ProfileId, LastName = 'Cohostp9', FirstName = 'Staff', Alias = 'p9stf',
            Username = 'p9staff' + String.valueOf(Crypto.getRandomInteger()).replace('-', '') + '@reach-p9.test',
            Email = 'p9staff@reach-p9.test', TimeZoneSidKey = 'America/New_York', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) { insert staff; }
        Account partner = person('Cora', 'Cohostpartnerp9', lo.Id, true);
        insert partner;

        System.runAs(lo) {
            Set<Id> found = new Set<Id>();
            for (RealtorEventWorkspaceController.CoHostOption o : BdCommandCenterController.searchCoHosts('Cohostp9')) found.add(o.userId);
            System.assert(found.contains(staff.Id), 'internal staff are offered');
            System.assert(!found.contains(otherLo.Id), 'another outside LO is never offered');

            BdCommandCenterController.InviteRequest bad = req(new List<Id>{ partner.Id }, 'lo');
            bad.coHostIds = new List<Id>{ otherLo.Id };
            System.assert(refused('invite', bad), 'an outside-LO co-host is rejected on create');
            System.assertEquals(0, [SELECT COUNT() FROM Campaign WHERE OwnerId = :lo.Id], 'nothing is created when refused');

            BdCommandCenterController.InviteRequest ok = req(new List<Id>{ partner.Id }, 'lo');
            ok.coHostIds = new List<Id>{ staff.Id };
            Test.startTest();
            Id campaignId = BdCommandCenterController.createInvite(ok);
            Test.stopTest();
            System.assertEquals(staff.Id, [SELECT Co_Host__c FROM Campaign_Co_Host__c WHERE Campaign__c = :campaignId].Co_Host__c);
        }
    }
}
