public with sharing class ConfirmAccount {

    @InvocableMethod(
        label='Confirm Account'
        description='Called when the rep confirms the matched account. Returns accountConfirmed = true to ungate the prescriber behaviour step.'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result r = new Result();
            r.accountConfirmed = true;
            results.add(r);
        }
        return results;
    }

    public class Request {
        @InvocableVariable(
            label='Account Id'
            description='The confirmed Salesforce Account Id'
            required=true
        )
        public String accountId;
    }

    public class Result {
        @InvocableVariable(
            label='accountConfirmed'
            description='Always returns true — signals the agent to proceed to prescriber behaviour retrieval'
        )
        public Boolean accountConfirmed;
    }
}
