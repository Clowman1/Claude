public without sharing class IntakeFormController {

    // Fallback ordering for realtors with no assigned primary LO. Previously this lived in the
    // IntakeForm Aura controller, where it re-sorted the server list and overrode the assignment.
    // Ordering lives here only, so there is a single source of truth.
    private static final Map<String, Integer> PREFERRED_LO_RANK = new Map<String, Integer>{
        'zach fritz' => 0,
        'zachary fritz' => 0,
        'rhett delaney' => 1,
        'joe olmsted' => 2,
        'alaina pugh' => 3,
        'alaina clare pugh' => 3,
        'berkeley peterson' => 4
    };
    private static final Integer UNRANKED_LO = 99;

    // Realtors carrying one of these Biz Dev designations are served a single fixed Loan Officer,
    // whatever their User_To_Account__c cards say. The designation IS the assignment, so there are
    // no junction records to create and no Nickley_Realtor_LO__c to backfill, and a realtor stamped
    // with the designation later picks the rule up on their next form load.
    private static final Map<String, String> BIZ_DEV_DESIGNATION_DEFAULT_LO = new Map<String, String>{
        'Biz Dev - Bondarevsky' => 'zfritz@reachhomeloans.com'
    };

    @AuraEnabled
    public static List<User> getLoanOfficers(String realtorEmail) {
        List<Account> accounts = [
            SELECT Id, Nickley_Realtor_LO__c, Biz_Dev_Designation__c
            FROM Account
            WHERE PersonEmail = :realtorEmail
        ];

        if (accounts.isEmpty()) {
            return new List<User>();
        }

        Account account = accounts[0];

        // A designation match returns exactly one officer, so that officer is the only tile on the
        // form and every submitted lead assigns to them. The Spanish Speaker answer is evaluated
        // ahead of the tile selection in the Aura controller, so Spanish routing still wins.
        List<User> designatedLoanOfficers = designationLoanOfficers(account.Biz_Dev_Designation__c);
        if (!designatedLoanOfficers.isEmpty()) {
            return designatedLoanOfficers;
        }

        Set<Id> userIds = new Set<Id>();
        List<User_To_Account__c> userToAccounts = [SELECT Id, User__c FROM User_To_Account__c WHERE Account__c = :account.Id AND Active__c = TRUE];
        for (User_To_Account__c uta : userToAccounts) {
            userIds.add(uta.User__c);
        }

        List<User> loanOfficers = [
            SELECT Id, Name, FirstName, LastName, Phone, Email, Headshot_URL__c
            FROM User
            WHERE Id IN :userIds
            AND IsActive = TRUE
            ORDER BY Name
        ];
        return orderLoanOfficers(loanOfficers, account.Nickley_Realtor_LO__c);
    }

    // Returns the designated officer for a Biz Dev designation, or an empty list when the
    // designation has no rule. Deliberately returns empty when that user is inactive so the caller
    // falls through to the normal card list -- a departed LO must never leave a form with no tiles,
    // which is exactly what happened to six realtors when Rhett Delaney was deactivated.
    private static List<User> designationLoanOfficers(String bizDevDesignation) {
        String username = String.isBlank(bizDevDesignation)
            ? null
            : BIZ_DEV_DESIGNATION_DEFAULT_LO.get(bizDevDesignation);
        if (username == null) {
            return new List<User>();
        }
        return [
            SELECT Id, Name, FirstName, LastName, Phone, Email, Headshot_URL__c
            FROM User
            WHERE Username = :username
            AND IsActive = TRUE
            LIMIT 1
        ];
    }

    // The realtor's assigned primary LO always leads, so their own officer is the first tile and
    // the form's default selection. Everyone else falls back to the preferred rank, then name.
    private static List<User> orderLoanOfficers(List<User> loanOfficers, String assignedName) {
        if (loanOfficers.size() < 2) {
            return loanOfficers;
        }
        List<OfficerOrder> ordering = new List<OfficerOrder>();
        for (User officer : loanOfficers) {
            Boolean isAssigned = String.isNotBlank(assignedName) && matchesAssignedName(officer, assignedName);
            ordering.add(new OfficerOrder(officer, isAssigned));
        }
        ordering.sort();
        List<User> ordered = new List<User>();
        for (OfficerOrder entry : ordering) {
            ordered.add(entry.officer);
        }
        return ordered;
    }

    private class OfficerOrder implements Comparable {
        private User officer;
        private Boolean isAssigned;
        private Integer rank;
        private String sortName;

        private OfficerOrder(User officer, Boolean isAssigned) {
            this.officer = officer;
            this.isAssigned = isAssigned;
            this.sortName = String.isBlank(officer.Name) ? '' : officer.Name.trim().toLowerCase();
            Integer preferredRank = PREFERRED_LO_RANK.get(this.sortName);
            this.rank = preferredRank == null ? UNRANKED_LO : preferredRank;
        }

        public Integer compareTo(Object otherValue) {
            OfficerOrder other = (OfficerOrder) otherValue;
            if (isAssigned != other.isAssigned) {
                return isAssigned ? -1 : 1;
            }
            if (rank != other.rank) {
                return rank < other.rank ? -1 : 1;
            }
            return sortName.compareTo(other.sortName);
        }
    }

    // The assignment field holds a display name that does not always match the User record
    // exactly -- "Zach Fritz" is the User "Zachary Fritz" -- so the last name must match while
    // the first names only need to share a prefix.
    private static Boolean matchesAssignedName(User candidate, String assignedName) {
        String assigned = assignedName.trim().toLowerCase();
        String candidateFullName = String.isBlank(candidate.Name) ? '' : candidate.Name.trim().toLowerCase();
        if (assigned == candidateFullName) {
            return true;
        }
        List<String> assignedParts = assigned.split('\\s+');
        if (assignedParts.size() < 2) {
            return false;
        }
        String assignedFirst = assignedParts[0];
        String assignedLast = assignedParts[assignedParts.size() - 1];
        String candidateFirst = String.isBlank(candidate.FirstName) ? '' : candidate.FirstName.trim().toLowerCase();
        String candidateLast = String.isBlank(candidate.LastName) ? '' : candidate.LastName.trim().toLowerCase();
        if (candidateLast != assignedLast || String.isBlank(candidateFirst) || String.isBlank(assignedFirst)) {
            return false;
        }
        return candidateFirst.startsWith(assignedFirst) || assignedFirst.startsWith(candidateFirst);
    }
}