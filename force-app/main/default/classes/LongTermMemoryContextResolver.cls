public with sharing class LongTermMemoryContextResolver {

    public class Context {
        public String orgKey;
        public String subjectType;
        public String unifiedSubjectId;
        public String scopeType;
        public String scopeKey;
        public String useCaseKey;
    }

    public static Context resolveFromSession(String useCaseKey) {
        String userId = UserInfo.getUserId().toLowerCase();
        Context out = new Context();
        out.orgKey          = UserInfo.getOrganizationId().toLowerCase();
        out.subjectType     = 'user';
        out.unifiedSubjectId = userId;
        out.scopeType       = 'personal';
        out.scopeKey        = userId;
        out.useCaseKey      = String.isNotBlank(useCaseKey) ? useCaseKey.trim().toLowerCase() : 'general';
        return out;
    }

    public static Context resolve(
        String contextJson,
        String orgKey,
        String subjectType,
        String unifiedSubjectId,
        String scopeType,
        String scopeKey,
        String useCaseKey
    ) {
        Map<String, Object> fromJson = parseContextJson(contextJson);

        Context out = new Context();
        out.orgKey = pick(
            orgKey,
            stringFrom(fromJson, 'orgKey'),
            UserInfo.getOrganizationId()
        );
        out.subjectType = pick(
            subjectType,
            stringFrom(fromJson, 'subjectType'),
            'user'
        ).toLowerCase();
        out.unifiedSubjectId = pick(
            unifiedSubjectId,
            stringFrom(fromJson, 'unifiedSubjectId'),
            UserInfo.getUserId()
        ).toLowerCase();
        out.scopeType = pick(
            scopeType,
            stringFrom(fromJson, 'scopeType'),
            'personal'
        ).toLowerCase();
        out.scopeKey = pick(
            scopeKey,
            stringFrom(fromJson, 'scopeKey'),
            out.unifiedSubjectId
        ).toLowerCase();
        out.useCaseKey = pick(
            useCaseKey,
            stringFrom(fromJson, 'useCaseKey'),
            'general'
        ).toLowerCase();

        out.orgKey = out.orgKey.toLowerCase();
        return out;
    }

    public static String resolveMemoryType(String memoryType, String memoryText) {
        if (String.isNotBlank(memoryType)) {
            String normalized = memoryType.trim().toLowerCase();
            if (normalized == 'semantic')   return 'Semantic';
            if (normalized == 'episodic')   return 'Episodic';
            if (normalized == 'procedural') return 'Procedural';
        }
        return inferMemoryType(memoryText);
    }

    private static String inferMemoryType(String memoryText) {
        if (String.isBlank(memoryText)) {
            return 'Semantic';
        }
        String lower = memoryText.toLowerCase();

        for (String kw : new List<String>{
            'start with', 'lead with', 'always show', 'begin with',
            'present', 'format as', 'open with', 'first show'
        }) {
            if (lower.contains(kw)) return 'Procedural';
        }

        for (String kw : new List<String>{
            'last meeting', 'previous', 'went well', 'last time',
            'during the last', 'at the last', 'last visit', 'last call',
            'previously', 'last quarter', 'failed'
        }) {
            if (lower.contains(kw)) return 'Episodic';
        }

        return 'Semantic';
    }

    private static Map<String, Object> parseContextJson(String contextJson) {
        if (String.isBlank(contextJson)) {
            return new Map<String, Object>();
        }

        try {
            Object parsed = JSON.deserializeUntyped(contextJson);
            if (parsed instanceof Map<String, Object>) {
                return (Map<String, Object>) parsed;
            }
            return new Map<String, Object>();
        } catch (Exception e) {
            return new Map<String, Object>();
        }
    }

    private static String stringFrom(Map<String, Object> payload, String key) {
        if (!payload.containsKey(key) || payload.get(key) == null) {
            return null;
        }
        return String.valueOf(payload.get(key));
    }

    private static String pick(String first, String second, String fallback) {
        if (String.isNotBlank(first)) {
            return first.trim();
        }
        if (String.isNotBlank(second)) {
            return second.trim();
        }
        return fallback;
    }
}
