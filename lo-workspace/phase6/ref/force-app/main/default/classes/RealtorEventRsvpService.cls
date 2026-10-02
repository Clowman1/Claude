@RestResource(urlMapping='/event-rsvp/*')
global without sharing class RealtorEventRsvpService {
    @HttpGet
    global static void previewResponse() {
        String artworkType = RestContext.request.params.get('asset');
        if (!String.isBlank(artworkType)) {
            serveArtwork(artworkType);
            return;
        }
        CampaignMember member = getValidatedMember();
        if (member == null) return;
        String responseValue = RestContext.request.params.get('r');
        if (responseValue != 'Yes' && responseValue != 'No') {
            writePage('Choose an RSVP option', '<p>Please use the Yes or No link from your event invitation.</p>', 400);
            return;
        }
        String action = responseValue == 'Yes' ? 'Yes, I will attend' : 'No, I cannot attend';
        String actionUrl = 'https://reachhomeloans.my.salesforce-sites.com/integrations/services/apexrest/event-rsvp'
            + '?m=' + member.Id + '&t=' + member.Event_Invite_Token__c + '&r=' + responseValue;
        writePage('Confirm your RSVP', '<p>You are about to respond <strong>' + action + '</strong> for <strong>'
            + member.Campaign.Name.escapeHtml4() + '</strong>.</p><form method="post" action="' + actionUrl.escapeHtml4()
            + '"><button type="submit">Confirm response</button></form>', 200);
    }

    @HttpPost
    global static void submitResponse() {
        CampaignMember member = getValidatedMember();
        if (member == null) return;
        String responseValue = RestContext.request.params.get('r');
        if (responseValue != 'Yes' && responseValue != 'No') {
            writePage('Invalid RSVP', '<p>Please use the Yes or No link from your invitation.</p>', 400);
            return;
        }
        member.Status = responseValue == 'Yes' ? 'Yes - Attending' : 'No - Unable to Attend';
        update member;
        writePage('Thank you', responseValue == 'Yes'
            ? '<p>Your RSVP has been recorded. We look forward to seeing you!</p>'
            : '<p>Your response has been recorded. We hope to see you at a future event.</p>', 200);
    }

    private static CampaignMember getValidatedMember() {
        try {
            Id memberId = (Id)RestContext.request.params.get('m');
            String token = RestContext.request.params.get('t');
            CampaignMember member = [
                SELECT Id, Event_Invite_Token__c, Campaign.Name
                FROM CampaignMember WHERE Id = :memberId LIMIT 1
            ];
            if (String.isBlank(token) || token != member.Event_Invite_Token__c) throw new SecurityException();
            return member;
        } catch (Exception ex) {
            writePage('This RSVP link is not valid', '<p>This invitation link is invalid or has expired. Please contact your event host.</p>', 403);
            return null;
        }
    }

    // Public, non-sensitive artwork used inside event invitation emails.  This route
    // deliberately bypasses RSVP-token validation so mail clients can render it.
    private static void serveArtwork(String artworkType) {
        String resourceName;
        if (artworkType == 'coffee-lunch') {
            resourceName = 'realtorCoffeeLunchInvite';
        } else if (artworkType == 'lunch') {
            resourceName = 'realtorLunchInvite';
        } else if (artworkType == 'happy-hour') {
            resourceName = 'realtorHappyHourInvite';
        } else {
            writePage('Artwork unavailable', '<p>The requested event artwork is unavailable.</p>', 404);
            return;
        }
        try {
            StaticResource artwork = [SELECT Body, ContentType FROM StaticResource WHERE Name = :resourceName LIMIT 1];
            RestContext.response.statusCode = 200;
            RestContext.response.addHeader('Content-Type', artwork.ContentType);
            RestContext.response.addHeader('Cache-Control', 'public, max-age=86400');
            RestContext.response.responseBody = artwork.Body;
        } catch (Exception ex) {
            writePage('Artwork unavailable', '<p>The requested event artwork is unavailable.</p>', 404);
        }
    }

    private static void writePage(String title, String body, Integer statusCode) {
        RestContext.response.statusCode = statusCode;
        RestContext.response.addHeader('Content-Type', 'text/html; charset=UTF-8');
        RestContext.response.responseBody = Blob.valueOf('<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"><title>'
            + title.escapeHtml4() + '</title></head><body style="font-family:Arial,sans-serif;background:#f4f7fb;padding:32px;color:#13294b"><main style="max-width:540px;background:#fff;border-radius:12px;padding:28px;margin:auto;box-shadow:0 2px 12px #d8e2ef"><h1 style="font-size:24px">'
            + title.escapeHtml4() + '</h1>' + body + '</main></body></html>');
    }
}