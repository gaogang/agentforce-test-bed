public with sharing class LongTermMemoryGetLastSuccessWatermark {

    private static final String DEFAULT_RUN_LOG_OBJECT = 'Long_Term_Memory_Run_Log__c';
    private static final String DEFAULT_STATUS_FIELD = 'Status__c';
    private static final String DEFAULT_WATERMARK_FIELD = 'Watermark_To_Utc__c';
    private static final String DEFAULT_SUCCESS_STATUS = 'success';
    private static final Integer DEFAULT_BOOTSTRAP_LOOKBACK_DAYS = 30;

    @InvocableMethod(
        label='Get Last Success Watermark'
        description='Returns watermark window for the daily memory generation run by reading the latest successful run log entry. Falls back to bootstrap lookback when no successful run is found.'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        List<Request> inputRequests = (requests == null || requests.isEmpty())
            ? new List<Request>{ new Request() }
            : requests;

        for (Request req : inputRequests) {
            results.add(resolveWindow(req));
        }

        return results;
    }

    private static Result resolveWindow(Request req) {
        Result out = new Result();

        Datetime runStartedAt = System.now();
        Integer lookbackDays = req != null && req.bootstrapLookbackDays != null
            ? Math.max(1, req.bootstrapLookbackDays)
            : DEFAULT_BOOTSTRAP_LOOKBACK_DAYS;

        out.runStartedAtUtc = runStartedAt;
        out.watermarkToUtc = runStartedAt;
        out.watermarkFromUtc = runStartedAt.addDays(-lookbackDays);
        out.bootstrapUsed = true;
        out.hasPreviousSuccess = false;
        out.success = true;
        out.message = 'Using bootstrap lookback window.';

        String objectApiName = pick(req == null ? null : req.runLogObjectApiName, DEFAULT_RUN_LOG_OBJECT);
        String statusFieldApiName = pick(req == null ? null : req.statusFieldApiName, DEFAULT_STATUS_FIELD);
        String watermarkFieldApiName = pick(req == null ? null : req.watermarkFieldApiName, DEFAULT_WATERMARK_FIELD);
        String successStatusValue = pick(req == null ? null : req.successStatusValue, DEFAULT_SUCCESS_STATUS);

        if (!isSafeApiName(objectApiName) || !isSafeApiName(statusFieldApiName) || !isSafeApiName(watermarkFieldApiName)) {
            out.success = false;
            out.message = 'Invalid object or field API name in request.';
            return out;
        }

        Schema.SObjectType runLogType = Schema.getGlobalDescribe().get(objectApiName);
        if (runLogType == null) {
            out.runLogObjectFound = false;
            out.message = 'Run log object not found. Using bootstrap lookback window.';
            return out;
        }

        out.runLogObjectFound = true;

        Map<String, Schema.SObjectField> fieldsByName = runLogType.getDescribe().fields.getMap();
        if (!fieldsByName.containsKey(statusFieldApiName) || !fieldsByName.containsKey(watermarkFieldApiName)) {
            out.success = false;
            out.message = 'Run log object found, but status/watermark fields are missing.';
            return out;
        }

        String escapedSuccess = String.escapeSingleQuotes(successStatusValue);
        String soql =
            'SELECT ' + watermarkFieldApiName +
            ' FROM ' + objectApiName +
            ' WHERE ' + statusFieldApiName + ' = \'' + escapedSuccess + '\'' +
            ' AND ' + watermarkFieldApiName + ' != null' +
            ' ORDER BY ' + watermarkFieldApiName + ' DESC' +
            ' LIMIT 1';

        try {
            List<SObject> rows = Database.query(soql + ' WITH USER_MODE');
            if (!rows.isEmpty()) {
                Datetime previousWatermark = (Datetime) rows[0].get(watermarkFieldApiName);
                if (previousWatermark != null) {
                    out.watermarkFromUtc = previousWatermark;
                    out.bootstrapUsed = false;
                    out.hasPreviousSuccess = true;
                    out.message = 'Loaded last successful watermark from run log.';
                }
            }
            out.queryUsed = soql;
            return out;
        } catch (Exception e) {
            out.success = false;
            out.message = 'Failed to query run log: ' + e.getMessage();
            out.queryUsed = soql;
            return out;
        }
    }

    private static String pick(String value, String fallbackValue) {
        return String.isNotBlank(value) ? value.trim() : fallbackValue;
    }

    private static Boolean isSafeApiName(String value) {
        if (String.isBlank(value)) {
            return false;
        }
        return Pattern.matches('[A-Za-z][A-Za-z0-9_]*', value);
    }

    public class Request {
        @InvocableVariable(
            label='Run Log Object API Name'
            description='API name of the run log object. Defaults to Long_Term_Memory_Run_Log__c.'
            required=false
        )
        public String runLogObjectApiName;

        @InvocableVariable(
            label='Status Field API Name'
            description='Status field API name. Defaults to Status__c.'
            required=false
        )
        public String statusFieldApiName;

        @InvocableVariable(
            label='Watermark Field API Name'
            description='Watermark field API name to read from successful runs. Defaults to Watermark_To_Utc__c.'
            required=false
        )
        public String watermarkFieldApiName;

        @InvocableVariable(
            label='Success Status Value'
            description='Status value treated as successful. Defaults to success.'
            required=false
        )
        public String successStatusValue;

        @InvocableVariable(
            label='Bootstrap Lookback Days'
            description='Lookback days when no successful run is found. Defaults to 30.'
            required=false
        )
        public Integer bootstrapLookbackDays;
    }

    public class Result {
        @InvocableVariable(
            label='success'
            description='True when step 1 executed without error'
        )
        public Boolean success;

        @InvocableVariable(
            label='runLogObjectFound'
            description='True when the configured run log object exists'
        )
        public Boolean runLogObjectFound;

        @InvocableVariable(
            label='hasPreviousSuccess'
            description='True when a previous successful watermark was found'
        )
        public Boolean hasPreviousSuccess;

        @InvocableVariable(
            label='bootstrapUsed'
            description='True when bootstrap lookback was used'
        )
        public Boolean bootstrapUsed;

        @InvocableVariable(
            label='runStartedAtUtc'
            description='Current run start timestamp used as watermarkToUtc'
        )
        public Datetime runStartedAtUtc;

        @InvocableVariable(
            label='watermarkFromUtc'
            description='Lower bound (exclusive) for the next extraction window'
        )
        public Datetime watermarkFromUtc;

        @InvocableVariable(
            label='watermarkToUtc'
            description='Upper bound (inclusive) for the next extraction window'
        )
        public Datetime watermarkToUtc;

        @InvocableVariable(
            label='message'
            description='Execution summary or error message'
        )
        public String message;

        @InvocableVariable(
            label='queryUsed'
            description='Dynamic query used to read successful watermark'
        )
        public String queryUsed;
    }
}