import { LightningElement, api, wire, track } from 'lwc';
import getCallInsights from '@salesforce/apex/CallInsightListController.getCallInsights';
import getZoomRecordings from '@salesforce/apex/CallInsightListController.getZoomRecordings';
import { CurrentPageReference } from 'lightning/navigation';

export default class CallInsightList extends LightningElement {
    _recordId;
    _contextRecordKey;
    // Set in App Builder: "RingSense" or "Zoom". One instance per tab, same object.
    @api source = 'RingSense';
    @track logs = [];

    _loaded = false;

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        if (value !== this._recordId) {
            this._recordId = value;
            this._loaded = false;
        }
    }

    @api
    get contextRecordKey() {
        return this._contextRecordKey;
    }

    set contextRecordKey(value) {
        if (value !== this._contextRecordKey) {
            this._contextRecordKey = value;
            this._loaded = false;
        }
    }

    get resolvedRecordId() {
        return this.contextRecordKey || this.recordId;
    }

    // The CurrentPageReference wire can emit before App Builder has assigned the design
    // properties, so loading from inside it read the default source of "RingSense" and
    // made the Zoom tab show RingSense data. Loading is driven from renderedCallback
    // instead, which is guaranteed to run after every @api property is set. Assigning
    // recordId below triggers a re-render, so a late recordId is still picked up.
    @wire(CurrentPageReference)
    getPageRef(pageRef) {
        if (!this.recordId && pageRef?.attributes?.recordId) {
            this.recordId = pageRef.attributes.recordId;
        }
    }

    renderedCallback() {
        if (this._loaded || !this.resolvedRecordId) return;
        this._loaded = true;
        this.loadCallInsights();
    }

    loadCallInsights() {

        //console.log('THIS RECORD ID', this.recordId);
        getCallInsights({ recordId: this.resolvedRecordId, source: this.source })
            .then(data => {
                this.logs = data.map(rec => {
                    const score = rec.AI_Score__c;

                    let scoreClass = 'score-badge ';

                    if (score === null || score === undefined) {
                        scoreClass += 'score-none';
                    } else if (score <= 3) {
                        scoreClass += 'score-red';
                    } else if (score <= 6) {
                        scoreClass += 'score-yellow';
                    } else {
                        scoreClass += 'score-green';
                    }
                    return  {
                            ...rec,
                            turns: this.buildTurns(rec.Transcript__c),
                            hasTurns: !!(rec.Transcript__c && rec.Transcript__c.trim()),
                            userName: rec.Salesforce_User__r
                                ? rec.Salesforce_User__r.FirstName + ' ' + rec.Salesforce_User__r.LastName
                                : '',
                            expanded: false,

                            // Zoom rows get the five Zoom-named tabs; everything else keeps
                            // the original RingSense tabs. Source__c arrives with the row, so
                            // this is known at first render and is safe to branch a tabset on.
                            isZoom: rec.Source__c === 'Zoom',

                            // Original RingSense fields, unchanged: those tabs report their
                            // data exactly as they did before the Zoom tab existed.
                            transcript: rec.Transcript__c ? rec.Transcript__c : 'No data',
                            highlights: rec.HighLights__c ? rec.HighLights__c : 'No data',

                            // One flag per tab so each Zoom tab can show its own empty state.
                            // Zoom rows arrive with a transcript but no AI fields until Smart
                            // Recording has run, so "empty" has to read as normal, not broken.
                            formattedHighlights: this.formatNiceList(rec.HighLights__c, 'summary'),
                            hasHighlights: this.hasText(rec.HighLights__c),
                            formattedSummary: this.formatNiceList(rec.Summary__c, 'summary'),
                            hasSummary: this.hasText(rec.Summary__c),
                            formattedChapters: this.formatNiceList(rec.Bulleted_Summary__c, 'summary'),
                            hasChapters: this.hasText(rec.Bulleted_Summary__c),
                            hasSummaryOrChapters: this.hasText(rec.Summary__c) || this.hasText(rec.Bulleted_Summary__c),
                            formattedNextSteps: this.formatNiceList(rec.Next_Steps__c, 'next'),
                            hasNextSteps: this.hasText(rec.Next_Steps__c),
                            recordings: [],
                            hasRecordings: false,
                            scoreClass
                        }
                    }
                );
                this.attachRecordings();
            })
            .catch(error => {
                console.error('Error loading call insights:', error);
            });
    }

    /**
     * Loads the playable Zoom files for whichever rows have a Zoom meeting, then hangs
     * them off those rows. Runs as a second call because Zoom_Recording__c is a sibling of
     * Call_Insight__c rather than a child, so one query cannot return both.
     */
    attachRecordings() {
        const meetingIds = [...new Set(this.logs.map(log => log.Zoom_Meeting__c).filter(Boolean))];
        if (!meetingIds.length) return;

        getZoomRecordings({ zoomMeetingIds: meetingIds })
            .then(files => {
                const byMeeting = {};
                files.forEach(file => {
                    const list = byMeeting[file.Zoom_Meeting__c] || (byMeeting[file.Zoom_Meeting__c] = []);
                    list.push({
                        id: file.Id,
                        fileType: file.File_Type__c,
                        url: file.Play_URL__c,
                        passcode: file.Play_Passcode__c,
                        hasPasscode: !!file.Play_Passcode__c,
                        durationLabel: this.formatDuration(file.Duration_Seconds__c)
                    });
                });
                this.logs = this.logs.map(log => {
                    const files = byMeeting[log.Zoom_Meeting__c] || [];
                    return { ...log, recordings: files, hasRecordings: files.length > 0 };
                });
            })
            .catch(error => {
                console.error('Error loading Zoom recordings:', error);
            });
    }

    formatDuration(seconds) {
        if (!seconds) return '';
        const total = Math.round(seconds);
        const minutes = Math.floor(total / 60);
        const remainder = String(total % 60).padStart(2, '0');
        return minutes + ':' + remainder;
    }

    /**
     * Splits a "Speaker: text" transcript into conversation turns for the template.
     *
     * The transcript is stored as one line per speaker turn, but it was rendered through
     * lightning-formatted-rich-text, which collapses newlines — so a 24-minute call
     * appeared as a single unbroken wall of text. Turns are parsed here and rendered as
     * structured markup instead of assembling an HTML string, so nothing from a borrower
     * conversation is ever interpreted as markup.
     */
    buildTurns(transcript) {
        if (!transcript) return [];
        const speakerOrder = [];

        return transcript
            .split('\n')
            .map(line => line.trim())
            .filter(line => line.length > 0)
            .map((line, index) => {
                const colon = line.indexOf(':');
                // Matches ZoomVttParser: a label longer than 60 chars is prose, not a name.
                const labelled = colon > 0 && colon <= 60;
                const speaker = labelled ? line.slice(0, colon).trim() : '';
                const text = labelled ? line.slice(colon + 1).trim() : line;

                if (speaker && !speakerOrder.includes(speaker)) speakerOrder.push(speaker);
                const alternate = speaker ? speakerOrder.indexOf(speaker) % 2 === 1 : false;

                return {
                    key: index,
                    speaker,
                    text,
                    turnClass: alternate ? 'ci-turn ci-turn-alt' : 'ci-turn'
                };
            });
    }

    hasText(value) {
        return !!(value && String(value).trim());
    }

    /**
     * Escapes text before it is placed into the HTML that lightning-formatted-rich-text
     * renders. These fields carry borrower conversation content, and the original
     * formatNiceList interpolated it straight into markup.
     */
    escapeHtml(value) {
        return String(value)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    formatNiceList(htmlString, type) {
        if (!htmlString) return '';

        // Remove bullets like &#8226;, •, -, *
        htmlString = htmlString
            .replace(/&#8226;/g, '')
            .replace(/•/g, '')
            .replace(/^\s*[-*]\s*/gm, '');

        // Convert <br/> to newlines
        let lines = htmlString
            .replace(/<br\s*\/?>/gi, '\n')
            .split('\n')
            .map(l => l.trim())
            .filter(l => l.length > 0)
            // Remove any <div> or </div> tags in each line
            .map(l => l.replace(/<\/?div[^>]*>/gi, ''));

        if (!lines.length) return htmlString;

        // Pick icon
        let icon = type === 'next' ? '➡️' : '🟦';

        // Build simple <ul> list
        const formatted = `
            <ul style="padding-left: 1.2rem; margin: 0;">
                ${lines
                    .map(line => `
                        <li style="margin-bottom:4px; list-style-type:none;">
                            <span style="margin-right:6px;">${icon}</span>
                            <span>${this.escapeHtml(line)}</span>
                        </li>
                    `)
                    .join('')}
            </ul>
        `;

        return formatted;
    }


    toggleExpand(event) {
        const id = event.currentTarget.dataset.id;

        this.logs = this.logs.map(log => ({
            ...log,
            expanded: log.Id === id ? !log.expanded : false
        }));
    }
}