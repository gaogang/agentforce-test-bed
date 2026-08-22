public with sharing class RetrieveLongTermMemory {

    @InvocableMethod(
        label='Retrieve Long Term Memory'
        description='Recalls relevant long-term memories for the current session. Context is derived automatically from the running user. Only queryText and useCaseKey are required.'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();

        for (Request req : requests) {
            Result out = new Result();
            try {
                LongTermMemoryContextResolver.Context ctx = String.isNotBlank(req.contextJson)
                    ? LongTermMemoryContextResolver.resolve(req.contextJson, null, null, null, null, null, req.useCaseKey)
                    : LongTermMemoryContextResolver.resolveFromSession(req.useCaseKey);

                LongTermMemoryService.RetrieveInput input = new LongTermMemoryService.RetrieveInput();
                input.orgKey           = ctx.orgKey;
                input.subjectType      = ctx.subjectType;
                input.unifiedSubjectId = ctx.unifiedSubjectId;
                input.scopeType        = ctx.scopeType;
                input.scopeKey         = ctx.scopeKey;
                input.useCaseKey       = ctx.useCaseKey;
                input.queryText        = req.queryText;
                input.memoryTypes      = new Set<String>{ 'semantic', 'episodic', 'procedural' };
                input.topK             = 5;

                LongTermMemoryService.RetrieveResult serviceResult = LongTermMemoryService.retrieve(input);
                out.retrievalId         = serviceResult.retrievalId;
                out.memoryContext       = serviceResult.memoryContext;
                out.memoriesJson        = JSON.serialize(serviceResult.memories);
                out.appliedFiltersJson  = JSON.serialize(serviceResult.appliedFilters);
                out.retrievalMetricsJson = JSON.serialize(serviceResult.retrievalMetrics);
                out.conflictFlagsJson   = JSON.serialize(serviceResult.conflictFlags);
            } catch (Exception e) {
                out.retrievalId          = '';
                out.memoryContext        = 'Memory retrieval failed: ' + e.getMessage();
                out.memoriesJson         = '[]';
                out.appliedFiltersJson   = '{}';
                out.retrievalMetricsJson = '{}';
                out.conflictFlagsJson    = '[]';
            }
            results.add(out);
        }

        return results;
    }

    public class Request {
        @InvocableVariable(
            label='Query Text'
            description='Natural language query describing what to recall for this session'
            required=false
        )
        public String queryText;

        @InvocableVariable(
            label='Use Case Key'
            description='Static workflow identifier wired by the agent author, e.g. precall. Scopes retrieval to this agent workflow.'
            required=false
        )
        public String useCaseKey;

        @InvocableVariable(
            label='Context JSON'
            description='Advanced override. Supported fields: orgKey, subjectType, unifiedSubjectId, scopeType, scopeKey, useCaseKey. Leave blank to use session-derived context.'
            required=false
        )
        public String contextJson;
    }

    public class Result {
        @InvocableVariable(
            label='retrievalId'
            description='Correlation id for this retrieval execution'
        )
        public String retrievalId;

        @InvocableVariable(
            label='memoryContext'
            description='Prompt-safe memory context block for the agent'
        )
        public String memoryContext;

        @InvocableVariable(
            label='memoriesJson'
            description='JSON array containing ranked memory items and explainability fields'
        )
        public String memoriesJson;

        @InvocableVariable(
            label='appliedFiltersJson'
            description='JSON object of filters applied during retrieval'
        )
        public String appliedFiltersJson;

        @InvocableVariable(
            label='retrievalMetricsJson'
            description='JSON object of retrieval metrics and mode information'
        )
        public String retrievalMetricsJson;

        @InvocableVariable(
            label='conflictFlagsJson'
            description='JSON array of conflict or supersession notices'
        )
        public String conflictFlagsJson;
    }
}
