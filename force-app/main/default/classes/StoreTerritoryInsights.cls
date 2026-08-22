public with sharing class StoreTerritoryInsights {

    @InvocableMethod(
        label='Store Territory Insights'
        description='Persists the final synthesised territory insights as a Territory_Insight__c record. Stores only the five narrative text fields produced by the reflection loop — raw source data is not stored.'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result r = new Result();
            try {
                Territory_Insight__c record = new Territory_Insight__c(
                    Territory_Id__c              = req.territoryId,
                    Report_Date__c               = req.reportDate,
                    Performance_Summary__c       = req.performanceSummary,
                    Market_Share_Insights__c     = req.marketShareInsights,
                    Competitive_Insights__c      = req.competitiveInsights,
                    Cycle_Plan_Insights__c       = req.cyclePlanInsights,
                    Recommended_Focus_Areas__c   = req.recommendedFocusAreas,
                    Iteration_Count__c           = req.iterationCount,
                    Approval_Status__c           = req.approvalStatus
                );
                insert as user record;
                r.recordId = record.Id;
                r.success  = true;
            } catch (Exception e) {
                r.recordId = null;
                r.success  = false;
                r.errorMessage = e.getMessage();
            }
            results.add(r);
        }
        return results;
    }

    public class Request {
        @InvocableVariable(
            label='Territory Id'
            description='Salesforce Territory2 record Id'
            required=true
        )
        public String territoryId;

        @InvocableVariable(
            label='Report Date'
            description='Date the insights were generated'
            required=true
        )
        public Date reportDate;

        @InvocableVariable(
            label='Performance Summary'
            description='Synthesised narrative overview of territory performance vs target'
            required=true
        )
        public String performanceSummary;

        @InvocableVariable(
            label='Market Share Insights'
            description='Synthesised narrative interpretation of product share trends'
            required=true
        )
        public String marketShareInsights;

        @InvocableVariable(
            label='Competitive Insights'
            description='Synthesised narrative summary of competitor activity and recommended response'
            required=true
        )
        public String competitiveInsights;

        @InvocableVariable(
            label='Cycle Plan Insights'
            description='Synthesised narrative assessment of cycle plan progress and rep-level observations'
            required=true
        )
        public String cyclePlanInsights;

        @InvocableVariable(
            label='Recommended Focus Areas'
            description='Prioritised narrative list of concrete actions for the territory manager'
            required=true
        )
        public String recommendedFocusAreas;

        @InvocableVariable(
            label='Iteration Count'
            description='Number of generator-critic reflection iterations completed'
            required=true
        )
        public Integer iterationCount;

        @InvocableVariable(
            label='Approval Status'
            description='approved or max_iterations_reached'
            required=true
        )
        public String approvalStatus;
    }

    public class Result {
        @InvocableVariable(
            label='recordId'
            description='Salesforce Id of the newly created Territory_Insight__c record'
        )
        public String recordId;

        @InvocableVariable(
            label='success'
            description='True if the record was created without error'
        )
        public Boolean success;

        @InvocableVariable(
            label='errorMessage'
            description='Error message if the insert failed; empty on success'
        )
        public String errorMessage;
    }
}
