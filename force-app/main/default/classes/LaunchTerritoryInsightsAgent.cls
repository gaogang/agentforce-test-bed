public with sharing class LaunchTerritoryInsightsAgent implements Queueable, Database.AllowsCallouts {

    private final String territoryId;
    private final Date   reportDate;

    public LaunchTerritoryInsightsAgent(String territoryId, Date reportDate) {
        this.territoryId = territoryId;
        this.reportDate  = reportDate;
    }

    public void execute(QueueableContext ctx) {
        Date effectiveReportDate = (reportDate == null) ? Date.today() : reportDate;
        String initialMessage =
            'territoryId=' + territoryId +
            ' reportDate=' + String.valueOf(effectiveReportDate);

        // Placeholder implementation for orgs where Agent runtime ConnectApi types are unavailable.
        // Swap this debug block for the org-specific Agent Runtime API call once enabled.
        System.debug(LoggingLevel.INFO,
            'LaunchTerritoryInsightsAgent queued message: ' + initialMessage);
    }

    // Invocable entry-point called by the Scheduled Flow.
    @InvocableMethod(
        label='Launch Territory Insights Agent'
        description='Enqueues an async job that starts a C4_reflection_territory_insights agent session for the given territory. Must be called from a Scheduled Flow to avoid mixed-DML errors.'
    )
    public static void launch(List<LaunchRequest> requests) {
        for (LaunchRequest req : requests) {
            if (String.isBlank(req.territoryId)) {
                continue;
            }
            System.enqueueJob(new LaunchTerritoryInsightsAgent(req.territoryId, req.reportDate));
        }
    }

    public class LaunchRequest {
        @InvocableVariable(
            label='Territory Id'
            description='Salesforce Territory2 record Id to process'
            required=true
        )
        public String territoryId;

        @InvocableVariable(
            label='Report Date'
            description='Date for which insights should be generated; defaults to today when blank'
            required=false
        )
        public Date reportDate;
    }
}
