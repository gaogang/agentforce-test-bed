/**
 * Platform-native memory store backed by Long_Term_Memory__c.
 * The Name field on Long_Term_Memory__c holds the memoryKey value.
 */
public with sharing class LongTermMemoryPlatformClient {

    private static final Integer MAX_RETRIEVE_LIMIT = 200;

    // ─── Retrieve ────────────────────────────────────────────────────────────

    /**
     * @param input Normalised retrieve input from LongTermMemoryService
     * @return Populated RetrieveResult
     */
    public static LongTermMemoryService.RetrieveResult retrieve(LongTermMemoryService.RetrieveInput input) {
        Datetime effectiveAt = input.effectiveAt == null ? System.now() : input.effectiveAt;

        List<Long_Term_Memory__c> records = [
            SELECT Name, Org_Key__c, Subject_Type__c, Unified_Subject_Id__c,
                   Scope_Type__c, Scope_Key__c, Use_Case_Key__c,
                   Memory_Type__c, Memory_Text__c, Retrieval_Summary__c,
                   Confidence_Score__c, Importance_Score__c, Recency_Score__c, Staleness_Score__c,
                   Status__c, Effective_From__c, Effective_To__c,
                   Source_Reference__c, Supersedes_Memory_Id__c, Superseded_By_Memory_Id__c,
                   Conflict_Group_Id__c, Structured_Payload__c
            FROM Long_Term_Memory__c
            WHERE Org_Key__c = :input.orgKey
              AND Status__c = 'Active'
              AND (Unified_Subject_Id__c = :input.unifiedSubjectId OR Scope_Type__c = 'organization')
              AND (Effective_From__c = null OR Effective_From__c <= :effectiveAt)
              AND (Effective_To__c = null OR Effective_To__c >= :effectiveAt)
            WITH USER_MODE
            LIMIT :MAX_RETRIEVE_LIMIT
        ];

        List<Long_Term_Memory__c> filtered = filterByMemoryTypes(records, input.memoryTypes);
        List<Long_Term_Memory__c> scoped = filterByScope(filtered, input.scopeType, input.scopeKey);
        if (scoped.isEmpty()) {
            scoped = applyScopeFallback(filtered, input.scopeType, input.scopeKey);
        }

        List<Long_Term_Memory__c> candidates = applyLexicalFilter(scoped, input.queryText);
        List<Map<String, String>> conflictFlags = new List<Map<String, String>>();
        List<Long_Term_Memory__c> ranked = rankRecords(candidates, input, conflictFlags);

        Integer take = Math.min(input.topK == null || input.topK <= 0 ? 5 : Math.min(input.topK, 20), ranked.size());

        LongTermMemoryService.RetrieveResult result = new LongTermMemoryService.RetrieveResult();
        result.retrievalId = 'rtv_' + String.valueOf(Crypto.getRandomInteger());
        result.conflictFlags = conflictFlags;
        result.appliedFilters.put('orgKey', input.orgKey);
        result.appliedFilters.put('unifiedSubjectId', input.unifiedSubjectId);
        result.appliedFilters.put('scopeType', input.scopeType);
        result.appliedFilters.put('scopeKey', input.scopeKey);
        result.appliedFilters.put('useCaseKey', input.useCaseKey);
        result.retrievalMetrics.put('candidateCountBeforeScope', filtered.size());
        result.retrievalMetrics.put('candidateCountAfterMatch', candidates.size());
        result.retrievalMetrics.put('returnedCount', take);
        result.retrievalMetrics.put('retrievalMode', 'platform_soql');

        for (Integer i = 0; i < take; i++) {
            result.memories.add(toRetrieveMemory(ranked[i], input));
        }
        result.memoryContext = buildMemoryContext(result.memories);
        return result;
    }

    // ─── Store ───────────────────────────────────────────────────────────────

    /**
     * @param input Normalised store input from LongTermMemoryService
     * @return StoreResult with memoryKey and status
     */
    public static LongTermMemoryService.StoreResult store(LongTermMemoryService.StoreInput input) {
        LongTermMemoryService.StoreResult output = new LongTermMemoryService.StoreResult();

        if (String.isBlank(input.orgKey) || String.isBlank(input.unifiedSubjectId) || String.isBlank(input.memoryText)) {
            output.status = 'Rejected';
            output.validationScore = 0;
            output.rejectionReason = 'Missing required fields: orgKey, unifiedSubjectId, memoryText';
            output.embeddingStatus = 'not_applicable';
            return output;
        }

        if (!isSupportedMemoryType(input.memoryType)) {
            output.status = 'Rejected';
            output.validationScore = 0;
            output.rejectionReason = 'Unsupported memoryType. Allowed: Semantic, Episodic, Procedural';
            output.embeddingStatus = 'not_applicable';
            return output;
        }

        Decimal quality = estimateValidationScore(input.memoryText, input.memoryType);
        if (quality < 0.35) {
            output.status = 'Rejected';
            output.validationScore = quality;
            output.rejectionReason = 'Memory text is too short or too vague for durable storage.';
            output.embeddingStatus = 'not_applicable';
            return output;
        }

        Long_Term_Memory__c existing = findActiveDuplicate(input);
        if (existing != null) {
            existing.Recency_Score__c = 1;
            update as user existing;
            output.memoryKey = existing.Name;
            output.status = 'Updated';
            output.validationScore = quality;
            output.rejectionReason = '';
            output.embeddingStatus = 'not_applicable';
            return output;
        }

        String supersededKey = supersedeConflictingActive(input);

        String memoryKey = 'mem_' + String.valueOf(Crypto.getRandomInteger());
        Long_Term_Memory__c record = new Long_Term_Memory__c(
            Name = memoryKey,
            Org_Key__c = input.orgKey,
            Subject_Type__c = input.subjectType,
            Unified_Subject_Id__c = input.unifiedSubjectId,
            Scope_Type__c = input.scopeType,
            Scope_Key__c = input.scopeKey,
            Use_Case_Key__c = input.useCaseKey,
            Memory_Type__c = input.memoryType,
            Memory_Text__c = input.memoryText.trim(),
            Retrieval_Summary__c = buildRetrievalSummary(input.memoryText),
            Structured_Payload__c = input.structuredPayload,
            Confidence_Score__c = quality,
            Importance_Score__c = inferImportanceScore(input.memoryType, input.memoryText),
            Recency_Score__c = 1,
            Staleness_Score__c = 0,
            Status__c = 'Active',
            Effective_From__c = System.now(),
            Effective_To__c = System.now().addYears(1),
            Source_Reference__c = buildSourceReference(input.sourceSystem, input.sourceRecordId),
            Supersedes_Memory_Id__c = supersededKey
        );
        insert as user record;

        output.memoryKey = memoryKey;
        output.status = 'Accepted';
        output.validationScore = quality;
        output.rejectionReason = '';
        output.supersedesMemoryId = supersededKey;
        output.embeddingStatus = 'not_applicable';
        return output;
    }

    // ─── Update Status ───────────────────────────────────────────────────────

    /**
     * @param memoryKey  Name field value of the record to update
     * @param targetStatus  New status value
     * @param suppressionReason  Populated only when targetStatus = Suppressed
     * @return UpdateResult
     */
    public static LongTermMemoryService.UpdateResult updateStatus(String memoryKey, String targetStatus, String suppressionReason) {
        LongTermMemoryService.UpdateResult result = new LongTermMemoryService.UpdateResult();

        if (String.isBlank(memoryKey) || String.isBlank(targetStatus)) {
            result.success = false;
            result.memoryKey = memoryKey;
            result.status = 'Rejected';
            return result;
        }

        List<Long_Term_Memory__c> matches = [
            SELECT Id, Name, Status__c, Structured_Payload__c
            FROM Long_Term_Memory__c
            WHERE Name = :memoryKey
            WITH USER_MODE
            LIMIT 1
        ];

        if (matches.isEmpty()) {
            result.success = false;
            result.memoryKey = memoryKey;
            result.status = 'NotFound';
            return result;
        }

        Long_Term_Memory__c record = matches[0];
        record.Status__c = targetStatus.trim();
        if ('Suppressed'.equalsIgnoreCase(record.Status__c) && String.isNotBlank(suppressionReason)) {
            record.Structured_Payload__c = mergeSuppressionReason(record.Structured_Payload__c, suppressionReason);
        }
        update as user record;

        result.success = true;
        result.memoryKey = memoryKey;
        result.status = record.Status__c;
        return result;
    }

    // ─── Private Helpers ─────────────────────────────────────────────────────

    private static List<Long_Term_Memory__c> filterByMemoryTypes(List<Long_Term_Memory__c> records, Set<String> memoryTypes) {
        if (memoryTypes == null || memoryTypes.isEmpty()) {
            return records;
        }
        List<Long_Term_Memory__c> out = new List<Long_Term_Memory__c>();
        for (Long_Term_Memory__c r : records) {
            if (r.Memory_Type__c != null && memoryTypes.contains(r.Memory_Type__c.toLowerCase())) {
                out.add(r);
            }
        }
        return out;
    }

    private static List<Long_Term_Memory__c> filterByScope(List<Long_Term_Memory__c> records, String scopeType, String scopeKey) {
        List<Long_Term_Memory__c> out = new List<Long_Term_Memory__c>();
        for (Long_Term_Memory__c r : records) {
            if (r.Scope_Type__c == scopeType && r.Scope_Key__c == scopeKey) {
                out.add(r);
            }
        }
        return out;
    }

    private static List<Long_Term_Memory__c> applyScopeFallback(List<Long_Term_Memory__c> records, String scopeType, String scopeKey) {
        List<String> order = new List<String>{ 'personal', 'account', 'territory', 'organization' };
        Integer start = order.indexOf(scopeType);
        if (start < 0) {
            start = 0;
        }
        for (Integer i = start; i < order.size(); i++) {
            String candidateScope = order[i];
            List<Long_Term_Memory__c> candidate = new List<Long_Term_Memory__c>();
            for (Long_Term_Memory__c r : records) {
                if (r.Scope_Type__c == candidateScope) {
                    if (candidateScope == 'organization' || r.Scope_Key__c == scopeKey) {
                        candidate.add(r);
                    }
                }
            }
            if (!candidate.isEmpty()) {
                return candidate;
            }
        }
        return new List<Long_Term_Memory__c>();
    }

    private static List<Long_Term_Memory__c> applyLexicalFilter(List<Long_Term_Memory__c> records, String queryText) {
        Set<String> queryTokens = tokenize(queryText);
        if (queryTokens.isEmpty()) {
            return records;
        }
        List<Long_Term_Memory__c> matches = new List<Long_Term_Memory__c>();
        for (Long_Term_Memory__c r : records) {
            Set<String> memTokens = tokenize(
                (r.Retrieval_Summary__c == null ? '' : r.Retrieval_Summary__c) + ' ' +
                (r.Memory_Text__c == null ? '' : r.Memory_Text__c)
            );
            if (overlapCount(queryTokens, memTokens) > 0) {
                matches.add(r);
            }
        }
        return matches.isEmpty() ? records : matches;
    }

    private static List<Long_Term_Memory__c> rankRecords(
        List<Long_Term_Memory__c> candidates,
        LongTermMemoryService.RetrieveInput input,
        List<Map<String, String>> conflictFlags
    ) {
        Map<String, ScoredRecord> byConflictGroup = new Map<String, ScoredRecord>();
        List<ScoredRecord> scored = new List<ScoredRecord>();

        for (Long_Term_Memory__c r : candidates) {
            ScoredRecord sr = new ScoredRecord();
            sr.record = r;
            sr.score = computeScore(r, input);
            if (String.isNotBlank(r.Conflict_Group_Id__c)) {
                if (!byConflictGroup.containsKey(r.Conflict_Group_Id__c) ||
                    byConflictGroup.get(r.Conflict_Group_Id__c).score < sr.score) {
                    byConflictGroup.put(r.Conflict_Group_Id__c, sr);
                }
            } else {
                scored.add(sr);
            }
        }

        for (String groupId : byConflictGroup.keySet()) {
            ScoredRecord winner = byConflictGroup.get(groupId);
            scored.add(winner);
            conflictFlags.add(new Map<String, String>{
                'conflictGroupId' => groupId,
                'selectedMemoryKey' => winner.record.Name
            });
        }

        scored.sort();
        List<Long_Term_Memory__c> out = new List<Long_Term_Memory__c>();
        for (ScoredRecord sr : scored) {
            out.add(sr.record);
        }
        return out;
    }

    private class ScoredRecord implements Comparable {
        Long_Term_Memory__c record;
        Decimal score;

        public Integer compareTo(Object otherObj) {
            ScoredRecord other = (ScoredRecord) otherObj;
            if (score == other.score) {
                return 0;
            }
            return score > other.score ? -1 : 1;
        }
    }

    private static Decimal computeScore(Long_Term_Memory__c r, LongTermMemoryService.RetrieveInput input) {
        Decimal scopeMatch = (r.Scope_Type__c == input.scopeType && r.Scope_Key__c == input.scopeKey)
            ? 1
            : (r.Scope_Type__c == 'organization' ? 0.3 : 0.5);
        Decimal typePriority = inferTypePriority(r.Memory_Type__c, input.queryText);
        Decimal importance = clamp(r.Importance_Score__c);
        Decimal recency = clamp(r.Recency_Score__c);
        Decimal confidence = clamp(r.Confidence_Score__c);
        Decimal staleness = clamp(r.Staleness_Score__c);
        return (0.30 * scopeMatch)
             + (0.20 * typePriority)
             + (0.20 * importance)
             + (0.15 * recency)
             + (0.15 * confidence)
             - (0.10 * staleness);
    }

    private static LongTermMemoryService.RetrieveMemory toRetrieveMemory(
        Long_Term_Memory__c r,
        LongTermMemoryService.RetrieveInput input
    ) {
        LongTermMemoryService.RetrieveMemory out = new LongTermMemoryService.RetrieveMemory();
        out.memoryKey = r.Name;
        out.memoryType = r.Memory_Type__c;
        out.memoryText = r.Memory_Text__c;
        out.retrievalSummary = r.Retrieval_Summary__c;
        out.confidenceScore = r.Confidence_Score__c;
        out.importanceScore = r.Importance_Score__c;
        out.recencyScore = r.Recency_Score__c;
        out.stalenessScore = r.Staleness_Score__c;
        out.similarityScore = 0;
        out.finalRankScore = computeScore(r, input);
        out.status = r.Status__c;
        out.effectiveFrom = r.Effective_From__c;
        out.effectiveTo = r.Effective_To__c;
        out.sourceReference = r.Source_Reference__c;
        out.whyRetrieved = buildWhyRetrieved(r, input);
        return out;
    }

    private static String buildWhyRetrieved(Long_Term_Memory__c r, LongTermMemoryService.RetrieveInput input) {
        List<String> reasons = new List<String>();
        reasons.add('scope=' + r.Scope_Type__c + ':' + r.Scope_Key__c);
        if (String.isNotBlank(input.queryText)) {
            reasons.add('query_match');
        }
        reasons.add('type=' + r.Memory_Type__c);
        return String.join(reasons, '; ');
    }

    private static String buildMemoryContext(List<LongTermMemoryService.RetrieveMemory> memories) {
        if (memories.isEmpty()) {
            return 'No long-term memory matched this request under current scope and policy filters.';
        }
        List<String> lines = new List<String>();
        Integer index = 1;
        for (LongTermMemoryService.RetrieveMemory m : memories) {
            lines.add(String.valueOf(index) + '. [' + m.memoryType + '] ' + m.retrievalSummary);
            index++;
        }
        return String.join(lines, '\n');
    }

    private static Long_Term_Memory__c findActiveDuplicate(LongTermMemoryService.StoreInput input) {
        String normalizedText = input.memoryText == null ? '' : input.memoryText.trim();
        List<Long_Term_Memory__c> matches = [
            SELECT Id, Name, Recency_Score__c, Memory_Text__c
            FROM Long_Term_Memory__c
            WHERE Org_Key__c = :input.orgKey
              AND Unified_Subject_Id__c = :input.unifiedSubjectId
              AND Scope_Type__c = :input.scopeType
              AND Scope_Key__c = :input.scopeKey
              AND Use_Case_Key__c = :input.useCaseKey
              AND Memory_Type__c = :input.memoryType
              AND Status__c = 'Active'
            WITH USER_MODE
        ];
        for (Long_Term_Memory__c r : matches) {
            String existingText = r.Memory_Text__c == null ? '' : r.Memory_Text__c.trim();
            if (existingText == normalizedText) {
                return r;
            }
        }
        return null;
    }

    private static String supersedeConflictingActive(LongTermMemoryService.StoreInput input) {
        String memType = input.memoryType == null ? '' : input.memoryType.toLowerCase();
        if (memType != 'semantic' && memType != 'procedural') {
            return null;
        }

        List<Long_Term_Memory__c> conflicts = [
            SELECT Id, Name, Memory_Type__c, Conflict_Group_Id__c
            FROM Long_Term_Memory__c
            WHERE Org_Key__c = :input.orgKey
              AND Unified_Subject_Id__c = :input.unifiedSubjectId
              AND Scope_Type__c = :input.scopeType
              AND Scope_Key__c = :input.scopeKey
              AND Use_Case_Key__c = :input.useCaseKey
              AND Memory_Type__c = :input.memoryType
              AND Status__c = 'Active'
            WITH USER_MODE
            LIMIT 1
        ];

        if (conflicts.isEmpty()) {
            return null;
        }

        Long_Term_Memory__c conflict = conflicts[0];
        conflict.Status__c = 'Superseded';
        update as user conflict;
        return conflict.Name;
    }

    private static Boolean isSupportedMemoryType(String memoryType) {
        return memoryType == 'Semantic' || memoryType == 'Episodic' || memoryType == 'Procedural';
    }

    private static Decimal estimateValidationScore(String memoryText, String memoryType) {
        Integer words = tokenize(memoryText).size();
        Decimal score = words >= 6 ? 0.7 : 0.2;
        if (words >= 12) {
            score += 0.15;
        }
        if (memoryType != null && memoryType.toLowerCase() == 'episodic'
            && memoryText != null && memoryText.toLowerCase().contains('last')) {
            score += 0.05;
        }
        return clamp(score);
    }

    private static Decimal inferImportanceScore(String memoryType, String text) {
        Decimal base = 0.6;
        String t = text == null ? '' : text.toLowerCase();
        if (t.contains('must') || t.contains('always') || t.contains('never')) {
            base += 0.2;
        }
        if (memoryType != null && memoryType.toLowerCase() == 'procedural') {
            base += 0.1;
        }
        return clamp(base);
    }

    private static Decimal inferTypePriority(String memoryType, String queryText) {
        String q = queryText == null ? '' : queryText.toLowerCase();
        String type = memoryType == null ? '' : memoryType.toLowerCase();
        if (q.contains('format') || q.contains('style') || q.contains('how should')) {
            return type == 'procedural' ? 1 : 0.4;
        }
        if (q.contains('what happened') || q.contains('last time') || q.contains('history')) {
            return type == 'episodic' ? 1 : 0.4;
        }
        if (q.contains('preference') || q.contains('prefer') || q.contains('fact')) {
            return type == 'semantic' ? 1 : 0.4;
        }
        return 0.7;
    }

    private static String buildRetrievalSummary(String text) {
        if (String.isBlank(text)) {
            return '';
        }
        String trimmed = text.trim();
        Integer max = 180;
        return trimmed.length() <= max ? trimmed : trimmed.substring(0, max - 3) + '...';
    }

    private static String buildSourceReference(String sourceSystem, String sourceRecordId) {
        if (String.isBlank(sourceRecordId)) {
            return sourceSystem;
        }
        return sourceSystem + ':' + sourceRecordId;
    }

    private static String mergeSuppressionReason(String structuredPayload, String reason) {
        Map<String, Object> payload = new Map<String, Object>();
        if (String.isNotBlank(structuredPayload)) {
            try {
                payload = (Map<String, Object>) JSON.deserializeUntyped(structuredPayload);
            } catch (Exception e) {
                payload = new Map<String, Object>();
            }
        }
        payload.put('suppressionReason', reason);
        return JSON.serialize(payload);
    }

    private static Set<String> tokenize(String text) {
        Set<String> tokens = new Set<String>();
        if (String.isBlank(text)) {
            return tokens;
        }
        String normalized = text.toLowerCase().replaceAll('[^a-z0-9 ]', ' ').replaceAll('\\s+', ' ').trim();
        for (String token : normalized.split(' ')) {
            if (token.length() > 2) {
                tokens.add(token);
            }
        }
        return tokens;
    }

    private static Integer overlapCount(Set<String> a, Set<String> b) {
        Integer overlap = 0;
        for (String token : a) {
            if (b.contains(token)) {
                overlap++;
            }
        }
        return overlap;
    }

    private static Decimal clamp(Decimal value) {
        Decimal v = value == null ? 0 : value;
        if (v < 0) {
            return 0;
        }
        if (v > 1) {
            return 1;
        }
        return v;
    }
}
