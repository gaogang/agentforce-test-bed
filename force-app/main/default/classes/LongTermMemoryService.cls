public with sharing class LongTermMemoryService {

    public class RetrieveInput {
        public String orgKey;
        public String subjectType;
        public String unifiedSubjectId;
        public String scopeType;
        public String scopeKey;
        public String useCaseKey;
        public String queryText;
        public Set<String> memoryTypes;
        public Integer topK;
        public Datetime effectiveAt;
    }

    public class RetrieveMemory {
        public String memoryKey;
        public String memoryType;
        public String memoryText;
        public String retrievalSummary;
        public Decimal confidenceScore;
        public Decimal importanceScore;
        public Decimal recencyScore;
        public Decimal stalenessScore;
        public Decimal similarityScore;
        public Decimal finalRankScore;
        public String status;
        public Datetime effectiveFrom;
        public Datetime effectiveTo;
        public String sourceReference;
        public String whyRetrieved;
    }

    public class RetrieveResult {
        public String retrievalId;
        public List<RetrieveMemory> memories = new List<RetrieveMemory>();
        public String memoryContext;
        public Map<String, Object> appliedFilters = new Map<String, Object>();
        public Map<String, Object> retrievalMetrics = new Map<String, Object>();
        public List<Map<String, String>> conflictFlags = new List<Map<String, String>>();
    }

    public class StoreInput {
        public String orgKey;
        public String subjectType;
        public String unifiedSubjectId;
        public String scopeType;
        public String scopeKey;
        public String useCaseKey;
        public String memoryType;
        public String memoryText;
        public String structuredPayload;
        public String sourceSystem;
        public String sourceRecordId;
        public String writeReason;
        public String extractionMethod;
    }

    public class StoreResult {
        public String memoryKey;
        public String status;
        public Decimal validationScore;
        public String rejectionReason;
        public String supersedesMemoryId;
        public String embeddingStatus;
    }

    public class UpdateResult {
        public Boolean success;
        public String memoryKey;
        public String status;
    }

    private class MemoryRecord {
        String memoryKey;
        String orgKey;
        String subjectType;
        String unifiedSubjectId;
        String scopeType;
        String scopeKey;
        String useCaseKey;
        String memoryType;
        String memoryText;
        String retrievalSummary;
        String structuredPayload;
        Decimal confidenceScore;
        Decimal importanceScore;
        Decimal recencyScore;
        Decimal stalenessScore;
        String status;
        Datetime effectiveFrom;
        Datetime effectiveTo;
        String sourceReference;
        String supersedesMemoryId;
        String supersededByMemoryId;
        String conflictGroupId;
        Datetime createdAt;
    }

    private static List<MemoryRecord> memoryStore = new List<MemoryRecord>();
    private static Boolean isSeeded = false;

    public static RetrieveResult retrieve(RetrieveInput input) {
        RetrieveInput normalized = normalizeInput(input);

        // In runtime, use the Data Cloud integration client. Keep deterministic in-memory logic
        // only for tests and offline local behavior.
        if (!Test.isRunningTest()) {
            return LongTermMemoryPlatformClient.retrieve(normalized);
        }

        ensureSeeded();

        RetrieveResult result = new RetrieveResult();
        result.retrievalId = 'rtv_' + String.valueOf(Crypto.getRandomInteger());
        result.appliedFilters.put('orgKey', normalized.orgKey);
        result.appliedFilters.put('unifiedSubjectId', normalized.unifiedSubjectId);
        result.appliedFilters.put('scopeType', normalized.scopeType);
        result.appliedFilters.put('scopeKey', normalized.scopeKey);
        result.appliedFilters.put('useCaseKey', normalized.useCaseKey);
        result.appliedFilters.put('memoryTypes', new List<String>(normalized.memoryTypes));

        List<MemoryRecord> base = applyGlobalFilters(normalized, memoryStore);
        Integer beforeScope = base.size();

        List<MemoryRecord> scoped = filterByScope(base, normalized.scopeType, normalized.scopeKey);
        String scopeMode = 'strict';
        if (scoped.isEmpty()) {
            scoped = applyScopeFallback(base, normalized.scopeType, normalized.scopeKey);
            scopeMode = 'fallback';
        }

        List<MemoryRecord> candidates = applyLexicalAndTypeFiltering(scoped, normalized);
        Integer matchedCount = candidates.size();

        List<RetrieveMemory> ranked = rankCandidates(candidates, normalized, result.conflictFlags);
        Integer take = Math.min(normalized.topK, ranked.size());
        for (Integer i = 0; i < take; i++) {
            result.memories.add(ranked[i]);
        }

        result.memoryContext = buildMemoryContext(result.memories);
        result.retrievalMetrics.put('candidateCountBeforeScope', beforeScope);
        result.retrievalMetrics.put('candidateCountAfterMatch', matchedCount);
        result.retrievalMetrics.put('returnedCount', result.memories.size());
        result.retrievalMetrics.put('scopeMode', scopeMode);
        result.retrievalMetrics.put('retrievalMode', 'deterministic_non_semantic');

        return result;
    }

    public static StoreResult store(StoreInput input) {
        StoreInput normalized = normalizeStoreInput(input);

        if (!Test.isRunningTest()) {
            return LongTermMemoryPlatformClient.store(normalized);
        }

        ensureSeeded();

        StoreResult output = new StoreResult();

        if (String.isBlank(normalized.orgKey) || String.isBlank(normalized.unifiedSubjectId) || String.isBlank(normalized.memoryText)) {
            output.status = 'Rejected';
            output.validationScore = 0;
            output.rejectionReason = 'Missing required fields: orgKey, unifiedSubjectId, memoryText';
            output.embeddingStatus = 'not_applicable';
            return output;
        }

        if (!isSupportedMemoryType(normalized.memoryType)) {
            output.status = 'Rejected';
            output.validationScore = 0;
            output.rejectionReason = 'Unsupported memoryType. Allowed: Semantic, Episodic, Procedural';
            output.embeddingStatus = 'not_applicable';
            return output;
        }

        Decimal quality = estimateValidationScore(normalized.memoryText, normalized.memoryType);
        if (quality < 0.35) {
            output.status = 'Rejected';
            output.validationScore = quality;
            output.rejectionReason = 'Memory text is too short or too vague for durable storage.';
            output.embeddingStatus = 'not_applicable';
            return output;
        }

        MemoryRecord duplicate = findActiveDuplicate(normalized);
        if (duplicate != null) {
            duplicate.recencyScore = 1;
            output.memoryKey = duplicate.memoryKey;
            output.status = 'Updated';
            output.validationScore = quality;
            output.rejectionReason = '';
            output.supersedesMemoryId = null;
            output.embeddingStatus = 'not_applicable';
            return output;
        }

        MemoryRecord record = new MemoryRecord();
        record.memoryKey = 'mem_' + String.valueOf(Crypto.getRandomInteger());
        record.orgKey = normalized.orgKey;
        record.subjectType = normalized.subjectType;
        record.unifiedSubjectId = normalized.unifiedSubjectId;
        record.scopeType = normalized.scopeType;
        record.scopeKey = normalized.scopeKey;
        record.useCaseKey = normalized.useCaseKey;
        record.memoryType = normalizeMemoryType(normalized.memoryType);
        record.memoryText = normalized.memoryText.trim();
        record.retrievalSummary = buildRetrievalSummary(normalized.memoryText);
        record.structuredPayload = normalized.structuredPayload;
        record.confidenceScore = quality;
        record.importanceScore = inferImportanceScore(normalized.memoryType, normalized.memoryText);
        record.recencyScore = 1;
        record.stalenessScore = 0;
        record.status = 'Active';
        record.effectiveFrom = System.now();
        record.effectiveTo = System.now().addYears(1);
        record.sourceReference = buildSourceReference(normalized.sourceSystem, normalized.sourceRecordId);
        record.createdAt = System.now();

        String superseded = supersedeConflictingActiveMemory(record);
        if (String.isNotBlank(superseded)) {
            record.supersedesMemoryId = superseded;
        }

        memoryStore.add(record);

        output.memoryKey = record.memoryKey;
        output.status = 'Accepted';
        output.validationScore = quality;
        output.rejectionReason = '';
        output.supersedesMemoryId = record.supersedesMemoryId;
        output.embeddingStatus = 'not_applicable';
        return output;
    }

    public static UpdateResult updateStatus(String memoryKey, String targetStatus, String suppressionReason) {
        if (!Test.isRunningTest()) {
            return LongTermMemoryPlatformClient.updateStatus(memoryKey, targetStatus, suppressionReason);
        }

        ensureSeeded();
        UpdateResult result = new UpdateResult();

        if (String.isBlank(memoryKey) || String.isBlank(targetStatus)) {
            result.success = false;
            result.memoryKey = memoryKey;
            result.status = 'Rejected';
            return result;
        }

        for (MemoryRecord record : memoryStore) {
            if (record.memoryKey == memoryKey) {
                record.status = targetStatus.trim();
                if ('Suppressed'.equalsIgnoreCase(record.status) && String.isNotBlank(suppressionReason)) {
                    record.structuredPayload = mergeSuppressionReason(record.structuredPayload, suppressionReason);
                }
                result.success = true;
                result.memoryKey = memoryKey;
                result.status = record.status;
                return result;
            }
        }

        result.success = false;
        result.memoryKey = memoryKey;
        result.status = 'NotFound';
        return result;
    }

    private static RetrieveInput normalizeInput(RetrieveInput input) {
        RetrieveInput normalized = input == null ? new RetrieveInput() : input;
        normalized.orgKey = safeLower(normalized.orgKey);
        normalized.subjectType = safeLower(normalized.subjectType);
        normalized.unifiedSubjectId = safeLower(normalized.unifiedSubjectId);
        normalized.scopeType = safeLower(normalized.scopeType);
        normalized.scopeKey = safeLower(normalized.scopeKey);
        normalized.useCaseKey = safeLower(normalized.useCaseKey);
        normalized.queryText = normalized.queryText == null ? '' : normalized.queryText;
        normalized.effectiveAt = normalized.effectiveAt == null ? System.now() : normalized.effectiveAt;
        normalized.topK = normalized.topK == null || normalized.topK <= 0 ? 5 : Math.min(normalized.topK, 20);
        if (normalized.memoryTypes == null || normalized.memoryTypes.isEmpty()) {
            normalized.memoryTypes = new Set<String>{ 'semantic', 'episodic', 'procedural' };
        } else {
            Set<String> normalizedTypes = new Set<String>();
            for (String t : normalized.memoryTypes) {
                if (String.isNotBlank(t)) {
                    normalizedTypes.add(t.trim().toLowerCase());
                }
            }
            normalized.memoryTypes = normalizedTypes;
        }
        return normalized;
    }

    private static StoreInput normalizeStoreInput(StoreInput input) {
        StoreInput normalized = input == null ? new StoreInput() : input;
        normalized.orgKey = safeLower(normalized.orgKey);
        normalized.subjectType = safeLower(normalized.subjectType);
        normalized.unifiedSubjectId = safeLower(normalized.unifiedSubjectId);
        normalized.scopeType = safeLower(normalized.scopeType);
        normalized.scopeKey = safeLower(normalized.scopeKey);
        normalized.useCaseKey = safeLower(normalized.useCaseKey);
        normalized.memoryType = normalizeMemoryType(normalized.memoryType);
        normalized.memoryText = normalized.memoryText == null ? '' : normalized.memoryText;
        normalized.structuredPayload = normalized.structuredPayload == null ? '' : normalized.structuredPayload;
        normalized.sourceSystem = String.isBlank(normalized.sourceSystem) ? 'agentforce' : normalized.sourceSystem;
        normalized.sourceRecordId = normalized.sourceRecordId == null ? '' : normalized.sourceRecordId;
        normalized.writeReason = normalized.writeReason == null ? '' : normalized.writeReason;
        normalized.extractionMethod = normalized.extractionMethod == null ? '' : normalized.extractionMethod;
        return normalized;
    }

    private static List<MemoryRecord> applyGlobalFilters(RetrieveInput input, List<MemoryRecord> records) {
        List<MemoryRecord> filtered = new List<MemoryRecord>();
        for (MemoryRecord r : records) {
            if (r.orgKey != input.orgKey) {
                continue;
            }
            if (!(r.unifiedSubjectId == input.unifiedSubjectId || r.scopeType == 'organization')) {
                continue;
            }
            if (r.status == null || r.status.toLowerCase() != 'active') {
                continue;
            }
            if (!input.memoryTypes.contains(r.memoryType.toLowerCase())) {
                continue;
            }
            if (r.effectiveFrom != null && r.effectiveFrom.getTime() > input.effectiveAt.getTime()) {
                continue;
            }
            if (r.effectiveTo != null && r.effectiveTo.getTime() < input.effectiveAt.getTime()) {
                continue;
            }
            filtered.add(r);
        }
        return filtered;
    }

    private static List<MemoryRecord> filterByScope(List<MemoryRecord> records, String scopeType, String scopeKey) {
        List<MemoryRecord> filtered = new List<MemoryRecord>();
        for (MemoryRecord r : records) {
            if (r.scopeType == scopeType && r.scopeKey == scopeKey) {
                filtered.add(r);
            }
        }
        return filtered;
    }

    private static List<MemoryRecord> applyScopeFallback(List<MemoryRecord> records, String scopeType, String scopeKey) {
        List<String> order = new List<String>{ 'personal', 'account', 'territory', 'organization' };
        Integer start = order.indexOf(scopeType);
        if (start < 0) {
            start = 0;
        }

        for (Integer i = start; i < order.size(); i++) {
            String candidateScope = order[i];
            List<MemoryRecord> candidate = new List<MemoryRecord>();
            for (MemoryRecord r : records) {
                if (r.scopeType == candidateScope) {
                    if (candidateScope == 'organization' || r.scopeKey == scopeKey) {
                        candidate.add(r);
                    }
                }
            }
            if (!candidate.isEmpty()) {
                return candidate;
            }
        }

        return new List<MemoryRecord>();
    }

    private static List<MemoryRecord> applyLexicalAndTypeFiltering(List<MemoryRecord> records, RetrieveInput input) {
        Set<String> queryTokens = tokenize(input.queryText);
        if (queryTokens.isEmpty()) {
            List<MemoryRecord> passthrough = new List<MemoryRecord>();
            passthrough.addAll(records);
            return passthrough;
        }

        List<MemoryRecord> matches = new List<MemoryRecord>();
        for (MemoryRecord r : records) {
            Set<String> memoryTokens = tokenize((r.retrievalSummary == null ? '' : r.retrievalSummary) + ' ' + (r.memoryText == null ? '' : r.memoryText));
            Integer overlap = overlapCount(queryTokens, memoryTokens);
            if (overlap > 0) {
                matches.add(r);
            }
        }

        if (matches.isEmpty()) {
            List<MemoryRecord> fallback = new List<MemoryRecord>();
            fallback.addAll(records);
            return fallback;
        }
        return matches;
    }

    private static List<RetrieveMemory> rankCandidates(List<MemoryRecord> candidates, RetrieveInput input, List<Map<String, String>> conflictFlags) {
        Map<String, ScoredMemory> selectedByConflictGroup = new Map<String, ScoredMemory>();
        List<ScoredMemory> scored = new List<ScoredMemory>();

        for (MemoryRecord r : candidates) {
            ScoredMemory sm = new ScoredMemory();
            sm.record = r;
            sm.score = computeDeterministicScore(r, input);

            if (String.isNotBlank(r.conflictGroupId)) {
                if (!selectedByConflictGroup.containsKey(r.conflictGroupId) || selectedByConflictGroup.get(r.conflictGroupId).score < sm.score) {
                    selectedByConflictGroup.put(r.conflictGroupId, sm);
                }
            } else {
                scored.add(sm);
            }
        }

        for (String groupId : selectedByConflictGroup.keySet()) {
            ScoredMemory winner = selectedByConflictGroup.get(groupId);
            scored.add(winner);
            conflictFlags.add(new Map<String, String>{
                'conflictGroupId' => groupId,
                'selectedMemoryKey' => winner.record.memoryKey
            });
        }

        scored.sort();

        List<RetrieveMemory> output = new List<RetrieveMemory>();
        for (ScoredMemory sm : scored) {
            output.add(toRetrieveMemory(sm.record, sm.score, input));
        }
        return output;
    }

    private class ScoredMemory implements Comparable {
        MemoryRecord record;
        Decimal score;

        public Integer compareTo(Object otherObj) {
            ScoredMemory other = (ScoredMemory) otherObj;
            if (score == other.score) {
                return 0;
            }
            return score > other.score ? -1 : 1;
        }
    }

    private static Decimal computeDeterministicScore(MemoryRecord r, RetrieveInput input) {
        Decimal scopeMatch = (r.scopeType == input.scopeType && r.scopeKey == input.scopeKey) ? 1 : (r.scopeType == 'organization' ? 0.3 : 0.5);
        Decimal typePriority = inferTypePriority(r.memoryType, input.queryText);
        Decimal importance = clamp(r.importanceScore);
        Decimal recency = clamp(r.recencyScore);
        Decimal confidence = clamp(r.confidenceScore);
        Decimal staleness = clamp(r.stalenessScore);

        return (0.30 * scopeMatch)
             + (0.20 * typePriority)
             + (0.20 * importance)
             + (0.15 * recency)
             + (0.15 * confidence)
             - (0.10 * staleness);
    }

    private static RetrieveMemory toRetrieveMemory(MemoryRecord r, Decimal score, RetrieveInput input) {
        RetrieveMemory out = new RetrieveMemory();
        out.memoryKey = r.memoryKey;
        out.memoryType = r.memoryType;
        out.memoryText = r.memoryText;
        out.retrievalSummary = r.retrievalSummary;
        out.confidenceScore = r.confidenceScore;
        out.importanceScore = r.importanceScore;
        out.recencyScore = r.recencyScore;
        out.stalenessScore = r.stalenessScore;
        out.similarityScore = 0;
        out.finalRankScore = score;
        out.status = r.status;
        out.effectiveFrom = r.effectiveFrom;
        out.effectiveTo = r.effectiveTo;
        out.sourceReference = r.sourceReference;
        out.whyRetrieved = buildWhyRetrieved(r, input);
        return out;
    }

    private static String buildWhyRetrieved(MemoryRecord r, RetrieveInput input) {
        List<String> reasons = new List<String>();
        reasons.add('scope=' + r.scopeType + ':' + r.scopeKey);
        if (String.isNotBlank(input.queryText)) {
            reasons.add('query_match');
        }
        reasons.add('type=' + r.memoryType);
        return String.join(reasons, '; ');
    }

    private static String buildMemoryContext(List<RetrieveMemory> memories) {
        if (memories.isEmpty()) {
            return 'No long-term memory matched this request under current scope and policy filters.';
        }

        List<String> lines = new List<String>();
        Integer index = 1;
        for (RetrieveMemory m : memories) {
            lines.add(String.valueOf(index) + '. [' + m.memoryType + '] ' + m.retrievalSummary);
            index++;
        }
        return String.join(lines, '\n');
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

    private static Decimal estimateValidationScore(String memoryText, String memoryType) {
        Integer words = tokenize(memoryText).size();
        Decimal score = words >= 6 ? 0.7 : 0.2;
        if (words >= 12) {
            score += 0.15;
        }
        if (memoryType != null && memoryType.toLowerCase() == 'episodic' && memoryText != null && memoryText.toLowerCase().contains('last')) {
            score += 0.05;
        }
        return clamp(score);
    }

    private static MemoryRecord findActiveDuplicate(StoreInput input) {
        String type = normalizeMemoryType(input.memoryType);
        String normalizedText = input.memoryText == null ? '' : input.memoryText.trim().toLowerCase();
        for (MemoryRecord record : memoryStore) {
            if (record.orgKey == input.orgKey
                && record.unifiedSubjectId == input.unifiedSubjectId
                && record.scopeType == input.scopeType
                && record.scopeKey == input.scopeKey
                && record.useCaseKey == input.useCaseKey
                && record.memoryType.toLowerCase() == type.toLowerCase()
                && record.status == 'Active'
                && record.memoryText != null
                && record.memoryText.trim().toLowerCase() == normalizedText) {
                return record;
            }
        }
        return null;
    }

    private static String supersedeConflictingActiveMemory(MemoryRecord incoming) {
        String incomingType = incoming.memoryType == null ? '' : incoming.memoryType.toLowerCase();
        if (incomingType != 'semantic' && incomingType != 'procedural') {
            return null;
        }

        for (MemoryRecord current : memoryStore) {
            if (current.orgKey == incoming.orgKey
                && current.unifiedSubjectId == incoming.unifiedSubjectId
                && current.scopeType == incoming.scopeType
                && current.scopeKey == incoming.scopeKey
                && current.useCaseKey == incoming.useCaseKey
                && current.memoryType == incoming.memoryType
                && current.status == 'Active') {
                current.status = 'Superseded';
                current.supersededByMemoryId = incoming.memoryKey;
                incoming.conflictGroupId = current.conflictGroupId == null ? current.memoryType + '_' + current.scopeType + '_' + current.scopeKey : current.conflictGroupId;
                return current.memoryKey;
            }
        }
        return null;
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

    private static Boolean isSupportedMemoryType(String memoryType) {
        String normalized = normalizeMemoryType(memoryType);
        return normalized == 'Semantic' || normalized == 'Episodic' || normalized == 'Procedural';
    }

    private static String normalizeMemoryType(String memoryType) {
        String value = String.isBlank(memoryType) ? 'Semantic' : memoryType.trim().toLowerCase();
        if (value == 'semantic') {
            return 'Semantic';
        }
        if (value == 'episodic') {
            return 'Episodic';
        }
        if (value == 'procedural') {
            return 'Procedural';
        }
        return memoryType == null ? '' : memoryType.trim();
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

    private static Set<String> tokenize(String text) {
        Set<String> tokens = new Set<String>();
        if (String.isBlank(text)) {
            return tokens;
        }

        String normalized = text.toLowerCase().replaceAll('[^a-z0-9 ]', ' ').replaceAll('\\s+', ' ').trim();
        if (String.isBlank(normalized)) {
            return tokens;
        }

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

    private static String safeLower(String value) {
        return String.isBlank(value) ? '' : value.trim().toLowerCase();
    }

    private static String buildRetrievalSummary(String text) {
        if (String.isBlank(text)) {
            return '';
        }
        String trimmed = text.trim();
        Integer max = 180;
        if (trimmed.length() <= max) {
            return trimmed;
        }
        return trimmed.substring(0, max - 3) + '...';
    }

    private static void ensureSeeded() {
        if (isSeeded) {
            return;
        }
        isSeeded = true;

        Datetime now = System.now();
        addSeed('mem_seed_001', 'org_demo', 'user', 'user_001', 'personal', 'user_001', 'precall', 'Semantic',
            'The rep prefers concise call prep in bullet points with no extra commentary.',
            'seed:semantic', 0.9, 0.85, 0.7, 0.1, now.addMonths(-2), now.addMonths(10));

        addSeed('mem_seed_002', 'org_demo', 'account', 'acct_101', 'account', 'acct_101', 'precall', 'Episodic',
            'Last meeting with account acct_101 went best when affordability programs were discussed before efficacy comparisons.',
            'seed:episodic', 0.82, 0.8, 0.75, 0.2, now.addMonths(-1), now.addMonths(6));

        addSeed('mem_seed_003', 'org_demo', 'user', 'user_001', 'personal', 'user_001', 'precall', 'Procedural',
            'Always present top three recommendations first, then supporting rationale.',
            'seed:procedural', 0.92, 0.88, 0.8, 0.05, now.addMonths(-3), now.addYears(1));
    }

    private static void addSeed(
        String memoryKey,
        String orgKey,
        String subjectType,
        String unifiedSubjectId,
        String scopeType,
        String scopeKey,
        String useCaseKey,
        String memoryType,
        String memoryText,
        String sourceReference,
        Decimal confidence,
        Decimal importance,
        Decimal recency,
        Decimal staleness,
        Datetime effectiveFrom,
        Datetime effectiveTo
    ) {
        MemoryRecord record = new MemoryRecord();
        record.memoryKey = memoryKey;
        record.orgKey = orgKey;
        record.subjectType = subjectType;
        record.unifiedSubjectId = unifiedSubjectId;
        record.scopeType = scopeType;
        record.scopeKey = scopeKey;
        record.useCaseKey = useCaseKey;
        record.memoryType = memoryType;
        record.memoryText = memoryText;
        record.retrievalSummary = buildRetrievalSummary(memoryText);
        record.structuredPayload = '';
        record.confidenceScore = confidence;
        record.importanceScore = importance;
        record.recencyScore = recency;
        record.stalenessScore = staleness;
        record.status = 'Active';
        record.effectiveFrom = effectiveFrom;
        record.effectiveTo = effectiveTo;
        record.sourceReference = sourceReference;
        record.createdAt = System.now();
        memoryStore.add(record);
    }
}
