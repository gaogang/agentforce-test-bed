public with sharing class GetPrescriberBehaviour {

    @InvocableMethod(
        label='Get Prescriber Behaviour'
        description='Returns mock prescriber behaviour data for the given accountId. Returns a JSON string summarising prescription frequency, last interaction, channel preference, competitor products, and open concerns.'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();

        for (Request req : requests) {
            Result r = new Result();
            r.prescriberBehaviourSummary = buildMockSummary(req.accountId);
            results.add(r);
        }

        return results;
    }

    private static String buildMockSummary(String accountId) {
        Map<String, Object> summary = new Map<String, Object>{
            'accountId'              => accountId,
            'prescriptionFrequency'  => 'high',
            'lastInteractionDate'    => '2026-05-14',
            'lastInteractionOutcome' => 'Interested in new clinical data',
            'preferredChannel'       => 'in-person',
            'competitorProducts'     => new List<String>{ 'BrandX', 'BrandY' },
            'keyOpenConcerns'        => new List<String>{ 'Long-term side effect profile', 'Patient affordability' }
        };
        return JSON.serialize(summary);
    }

    public class Request {
        @InvocableVariable(
            label='Account Id'
            description='Salesforce Account Id for which to retrieve prescriber behaviour'
            required=true
        )
        public String accountId;
    }

    public class Result {
        @InvocableVariable(
            label='prescriberBehaviourSummary'
            description='JSON string summarising prescriber behaviour: prescription frequency, last interaction, channel preference, competitor products, and open concerns'
        )
        public String prescriberBehaviourSummary;
    }
}
