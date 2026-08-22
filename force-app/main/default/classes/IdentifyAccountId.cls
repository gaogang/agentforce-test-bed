public with sharing class IdentifyAccountId {

    private static final Set<String> STOP_WORDS = new Set<String>{
        'dr', 'doctor', 'mr', 'mrs', 'ms', 'miss',
        'precall', 'summary', 'for', 'the', 'a', 'an', 'of', 'with', 'to', 'and'
    };

    @InvocableMethod(
        label='Identify Account Id'
        description='Searches the Account object by first name, last name, and optional specialty. Returns the matched account Id, full name, and specialty.'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();

        for (Request req : requests) {
            Result r = new Result();
            try {
                String firstName = req.firstName != null ? req.firstName.trim() : '';
                String lastName  = req.lastName  != null ? req.lastName.trim()  : '';

                List<String> nameTokens = extractNameTokens(firstName + ' ' + lastName);
                String normalizedFirst = nameTokens.size() > 0 ? nameTokens[0] : '';
                String normalizedLast  = nameTokens.size() > 1 ? nameTokens[nameTokens.size() - 1] : '';

                if (String.isBlank(firstName) && String.isNotBlank(normalizedFirst)) {
                    firstName = normalizedFirst;
                }
                if (String.isBlank(lastName) && String.isNotBlank(normalizedLast)) {
                    lastName = normalizedLast;
                }

                if (String.isNotBlank(normalizedFirst) && String.isNotBlank(normalizedLast)) {
                    firstName = normalizedFirst;
                    lastName = normalizedLast;
                }
                if (String.isNotBlank(normalizedLast) && String.isBlank(lastName)) {
                    lastName = normalizedLast;
                }

                // Build LIKE patterns for each name part and for the full name
                String firstLike = String.isNotBlank(firstName) ? '%' + firstName + '%' : null;
                String lastLike  = String.isNotBlank(lastName)  ? '%' + lastName  + '%' : null;

                List<Account> matches = new List<Account>();
                if (String.isNotBlank(firstName) && String.isNotBlank(lastName)) {
                    // Primary: exact FirstName + LastName fields
                    String q = 'SELECT Id, FirstName, LastName, Name FROM Account'
                             + ' WHERE FirstName = :firstName AND LastName = :lastName'
                             + ' ORDER BY Name LIMIT 5';
                    matches = Database.query(q, AccessLevel.USER_MODE);
                } else if (String.isNotBlank(lastName)) {
                    String q = 'SELECT Id, FirstName, LastName, Name FROM Account'
                             + ' WHERE LastName = :lastName'
                             + ' ORDER BY Name LIMIT 5';
                    matches = Database.query(q, AccessLevel.USER_MODE);
                } else if (String.isNotBlank(firstName)) {
                    String q = 'SELECT Id, FirstName, LastName, Name FROM Account'
                             + ' WHERE FirstName = :firstName'
                             + ' ORDER BY Name LIMIT 5';
                    matches = Database.query(q, AccessLevel.USER_MODE);
                }

                // Fallback: search the Name field using each provided part as a LIKE token
                if (matches.isEmpty() && (String.isNotBlank(firstName) || String.isNotBlank(lastName))) {
                    String q;
                    if (String.isNotBlank(firstLike) && String.isNotBlank(lastLike)) {
                        q = 'SELECT Id, FirstName, LastName, Name FROM Account'
                          + ' WHERE Name LIKE :firstLike AND Name LIKE :lastLike'
                          + ' ORDER BY Name LIMIT 5';
                    } else if (String.isNotBlank(lastLike)) {
                        q = 'SELECT Id, FirstName, LastName, Name FROM Account'
                          + ' WHERE Name LIKE :lastLike'
                          + ' ORDER BY Name LIMIT 5';
                    } else {
                        q = 'SELECT Id, FirstName, LastName, Name FROM Account'
                          + ' WHERE Name LIKE :firstLike'
                          + ' ORDER BY Name LIMIT 5';
                    }
                    matches = Database.query(q, AccessLevel.USER_MODE);
                }

                // Fallback: token-based Name search resilient to noisy inputs like "Precall summary for Dr. Linda Abriel"
                if (matches.isEmpty() && !nameTokens.isEmpty()) {
                    String q = 'SELECT Id, FirstName, LastName, Name FROM Account WHERE Name LIKE :nameLike ORDER BY Name LIMIT 5';
                    for (String token : nameTokens) {
                        String nameLike = '%' + token + '%';
                        List<Account> tokenMatches = Database.query(q, AccessLevel.USER_MODE);
                        if (matches.isEmpty()) {
                            matches.addAll(tokenMatches);
                        } else {
                            Set<Id> tokenIds = new Set<Id>();
                            for (Account a : tokenMatches) {
                                tokenIds.add(a.Id);
                            }

                            List<Account> intersection = new List<Account>();
                            for (Account a : matches) {
                                if (tokenIds.contains(a.Id)) {
                                    intersection.add(a);
                                }
                            }
                            matches = intersection;
                        }

                        if (matches.isEmpty()) {
                            break;
                        }
                    }
                }

                if (!matches.isEmpty()) {
                    Account acc = matches[0];
                    r.accountId        = acc.Id;
                    r.accountName      = acc.Name;
                    r.accountSpecialty = 'Not specified';
                } else {
                    r.accountId        = null;
                    r.accountName      = null;
                    r.accountSpecialty = null;
                }
            } catch (Exception e) {
                r.accountId        = '';
                r.accountName      = 'Error: ' + e.getMessage();
                r.accountSpecialty = '';
            }
            results.add(r);
        }

        return results;
    }

    private static List<String> extractNameTokens(String raw) {
        List<String> tokens = new List<String>();
        if (String.isBlank(raw)) {
            return tokens;
        }

        String normalized = raw.toLowerCase();
        normalized = normalized.replaceAll('[^a-z ]', ' ');
        normalized = normalized.replaceAll('\\s+', ' ').trim();
        if (String.isBlank(normalized)) {
            return tokens;
        }

        for (String token : normalized.split(' ')) {
            if (String.isBlank(token)) {
                continue;
            }
            if (STOP_WORDS.contains(token)) {
                continue;
            }
            tokens.add(token);
        }

        return tokens;
    }

    public class Request {
        @InvocableVariable(
            label='First Name'
            description='First name of the account to search for'
            required=false
        )
        public String firstName;

        @InvocableVariable(
            label='Last Name'
            description='Last name of the account to search for'
            required=false
        )
        public String lastName;

        @InvocableVariable(
            label='Specialty'
            description='Medical specialty of the account, used to refine search'
            required=false
        )
        public String specialty;
    }

    public class Result {
        @InvocableVariable(
            label='accountId'
            description='Salesforce Account record Id of the matched account'
        )
        public String accountId;

        @InvocableVariable(
            label='accountName'
            description='Full name of the matched account, e.g. Dr. Sarah Chen'
        )
        public String accountName;

        @InvocableVariable(
            label='accountSpecialty'
            description='Medical specialty of the matched account, e.g. Cardiology'
        )
        public String accountSpecialty;
    }
}
