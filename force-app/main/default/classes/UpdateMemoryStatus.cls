public with sharing class UpdateMemoryStatus {

    @InvocableMethod(
        label='Update Memory Status'
        description='Updates long-term memory status for suppression, deletion, expiry, or supersession in deterministic memory flow.'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();

        for (Request req : requests) {
            Result out = new Result();
            try {
                LongTermMemoryService.UpdateResult serviceResult = LongTermMemoryService.updateStatus(
                    req.memoryKey,
                    req.targetStatus,
                    req.suppressionReason
                );
                out.memoryKey = serviceResult.memoryKey;
                out.success = serviceResult.success;
                out.status = serviceResult.status;
            } catch (Exception e) {
                out.memoryKey = req.memoryKey;
                out.success = false;
                out.status = 'Rejected: ' + e.getMessage();
            }
            results.add(out);
        }

        return results;
    }

    public class Request {
        @InvocableVariable(
            label='Memory Key'
            description='Canonical memory key to update'
            required=true
        )
        public String memoryKey;

        @InvocableVariable(
            label='Target Status'
            description='Active, Superseded, Expired, Deleted, or Suppressed'
            required=true
        )
        public String targetStatus;

        @InvocableVariable(
            label='Suppression Reason'
            description='Reason if target status is Suppressed'
            required=false
        )
        public String suppressionReason;
    }

    public class Result {
        @InvocableVariable(
            label='memoryKey'
            description='Canonical memory key that was updated'
        )
        public String memoryKey;

        @InvocableVariable(
            label='success'
            description='True if the update succeeded'
        )
        public Boolean success;

        @InvocableVariable(
            label='status'
            description='Final status after update, or failure message'
        )
        public String status;
    }
}
