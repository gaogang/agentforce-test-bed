public with sharing class RecommendTalkpoint {

    @InvocableMethod(
        label='Recommend Talkpoint'
        description='Generates prioritised talkpoints based on prescriber behaviour data. Returns a JSON array of talkpoints, each with priority, topic, rationale, and suggestedOpener fields.'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();

        for (Request req : requests) {
            Result r = new Result();
            r.talkpoints = generateTalkpoints(req.prescriberBehaviourSummary);
            results.add(r);
        }

        return results;
    }

    private static String generateTalkpoints(String behaviourJson) {
        Map<String, Object> behaviour = new Map<String, Object>();
        try {
            behaviour = (Map<String, Object>) JSON.deserializeUntyped(behaviourJson);
        } catch (Exception e) {
            // Fall through to empty behaviour — default talkpoint will be generated
        }

        List<Object> concerns    = behaviour.containsKey('keyOpenConcerns')
            ? (List<Object>) behaviour.get('keyOpenConcerns')
            : new List<Object>();

        List<Object> competitors = behaviour.containsKey('competitorProducts')
            ? (List<Object>) behaviour.get('competitorProducts')
            : new List<Object>();

        String lastOutcome       = behaviour.containsKey('lastInteractionOutcome')
            ? (String) behaviour.get('lastInteractionOutcome')
            : '';

        String primaryCompetitor = !competitors.isEmpty() ? (String) competitors[0] : 'competitor products';

        List<Map<String, Object>> talkpoints = new List<Map<String, Object>>();

        if (!concerns.isEmpty()) {
            talkpoints.add(new Map<String, Object>{
                'priority'        => 1,
                'topic'           => 'New Clinical Safety Data',
                'rationale'       => 'Last visit outcome: ' + lastOutcome + '. Open concern: ' + (String) concerns[0],
                'suggestedOpener' => 'We have new Phase IV data I\'d love to walk you through — it directly addresses the tolerability question you raised last time.'
            });
        }

        if (concerns.size() > 1) {
            talkpoints.add(new Map<String, Object>{
                'priority'        => 2,
                'topic'           => 'Patient Affordability Programme',
                'rationale'       => 'Open concern: ' + (String) concerns[1],
                'suggestedOpener' => 'We\'ve expanded our patient support programme — most patients on ' + primaryCompetitor + ' would qualify for zero co-pay.'
            });
        }

        if (!competitors.isEmpty()) {
            talkpoints.add(new Map<String, Object>{
                'priority'        => 3,
                'topic'           => 'Head-to-Head vs ' + primaryCompetitor,
                'rationale'       => 'Account currently uses ' + primaryCompetitor + '. Recent trial data shows superiority in their patient segment.',
                'suggestedOpener' => 'Have you had a chance to see the ACCEL-3 trial results? The outcomes data in this patient segment is compelling.'
            });
        }

        if (talkpoints.isEmpty()) {
            talkpoints.add(new Map<String, Object>{
                'priority'        => 1,
                'topic'           => 'Product Overview',
                'rationale'       => 'No prior interaction data available — introduce the product portfolio.',
                'suggestedOpener' => 'I\'d love to share what\'s new in our portfolio and hear about your current patient challenges.'
            });
        }

        return JSON.serialize(talkpoints);
    }

    public class Request {
        @InvocableVariable(
            label='Prescriber Behaviour Summary'
            description='JSON string from the Get Prescriber Behaviour action'
            required=true
        )
        public String prescriberBehaviourSummary;
    }

    public class Result {
        @InvocableVariable(
            label='talkpoints'
            description='JSON array of prioritised talkpoints, each with priority, topic, rationale, and suggestedOpener fields'
        )
        public String talkpoints;
    }
}
