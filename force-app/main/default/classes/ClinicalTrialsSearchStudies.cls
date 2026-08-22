public with sharing class ClinicalTrialsSearchStudies {
  private static final String NAMED_CREDENTIAL = 'ClinicalTrials_Gov_API';
  private static final Integer MAX_PAGE_SIZE = 10;
  private static final Integer MAX_VALUE_LENGTH = 4000;
  private static final String NCT_PATTERN = '^[Nn][Cc][Tt]0*[1-9]\\d{0,7}$';
  private static final String GEO_PATTERN = '^distance\\(-?\\d+(\\.\\d+)?,-?\\d+(\\.\\d+)?,\\d+(\\.\\d+)?(km|mi)?\\)$';
  private static final String SORT_PATTERN = '^(([a-zA-Z][a-zA-Z0-9\\-. ]*)|(@relevance))(:(asc|desc))?$';
  private static final String FIELD_PATTERN = '^([a-zA-Z][a-zA-Z0-9\\-. ]*)|(@query)$';

  private static final Set<String> STUDIES_PARAMETERS = new Set<String>{
    'format',
    'markupFormat',
    'query.cond',
    'query.term',
    'query.locn',
    'query.titles',
    'query.intr',
    'query.outc',
    'query.spons',
    'query.lead',
    'query.id',
    'query.patient',
    'filter.overallStatus',
    'filter.geo',
    'filter.ids',
    'filter.advanced',
    'filter.synonyms',
    'postFilter.overallStatus',
    'postFilter.geo',
    'postFilter.ids',
    'postFilter.advanced',
    'postFilter.synonyms',
    'aggFilters',
    'geoDecay',
    'fields',
    'sort',
    'countTotal',
    'pageSize',
    'pageToken'
  };

  @InvocableMethod(
    label='Search Clinical Trials'
    description='Executes an OAS-defined ClinicalTrials.gov /studies query. Input is a JSON array of name/value parameter objects.'
  )
  public static List<Result> search(List<Request> requests) {
    List<Result> results = new List<Result>();
    for (Request request : requests) {
      results.add(execute(request));
    }
    return results;
  }

  private static Result execute(Request request) {
    try {
      QueryBuild query = buildQuery(
        request == null ? null : request.queryParamsJson
      );
      HttpResponse response = sendRequest(query.queryString);
      if (response.getStatusCode() == 200) {
        Result result = parseSuccess(response.getBody());
        result.appliedQueryJson = query.appliedQueryJson;
        return result;
      }
      if (response.getStatusCode() == 400 || response.getStatusCode() == 404) {
        Result result = errorResult('No matching clinical trials were found.');
        result.appliedQueryJson = query.appliedQueryJson;
        return result;
      }
      Result result = errorResult(
        'The ClinicalTrials.gov service is temporarily unavailable. Please try again.'
      );
      result.appliedQueryJson = query.appliedQueryJson;
      return result;
    } catch (Exception ex) {
      return errorResult(
        'The ClinicalTrials.gov service is temporarily unavailable. Please try again.'
      );
    }
  }

  private static QueryBuild buildQuery(String queryParamsJson) {
    List<Object> rawParams = new List<Object>();
    if (String.isNotBlank(queryParamsJson)) {
      Object decoded = JSON.deserializeUntyped(queryParamsJson);
      if (!(decoded instanceof List<Object>)) {
        throw new QueryException('Query parameters must be a JSON array.');
      }
      rawParams = (List<Object>) decoded;
    }

    List<String> encodedParams = new List<String>();
    List<Map<String, String>> appliedParams = new List<Map<String, String>>();
    for (Object rawParam : rawParams) {
      if (!(rawParam instanceof Map<String, Object>)) {
        continue;
      }
      Map<String, Object> parameter = (Map<String, Object>) rawParam;
      String name = scalarValue(parameter.get('name'));
      if (String.isBlank(name) || !STUDIES_PARAMETERS.contains(name)) {
        continue;
      }
      Object value = parameter.get('value');
      String normalized = normalizeValue(name, value);
      if (normalized == null) {
        continue;
      }
      encodedParams.add(
        EncodingUtil.urlEncode(name, 'UTF-8') +
          '=' +
          EncodingUtil.urlEncode(normalized, 'UTF-8')
      );
      appliedParams.add(
        new Map<String, String>{ 'name' => name, 'value' => normalized }
      );
    }
    if (encodedParams.isEmpty()) {
      encodedParams.add('format=json');
      encodedParams.add('pageSize=10');
      appliedParams.add(
        new Map<String, String>{ 'name' => 'format', 'value' => 'json' }
      );
      appliedParams.add(
        new Map<String, String>{ 'name' => 'pageSize', 'value' => '10' }
      );
    }
    QueryBuild result = new QueryBuild();
    result.queryString = '?' + String.join(encodedParams, '&');
    result.appliedQueryJson = JSON.serialize(appliedParams);
    return result;
  }

  private static String normalizeValue(String name, Object rawValue) {
    if (rawValue == null) {
      return null;
    }
    String value = collectionValue(rawValue);
    if (String.isBlank(value) || value.length() > MAX_VALUE_LENGTH) {
      return null;
    }
    if (name == 'format') {
      return value == 'json' ? value : 'json';
    }
    if (name == 'countTotal') {
      return 'false';
    }
    if (name == 'pageSize') {
      Integer requestedSize;
      try {
        requestedSize = Integer.valueOf(value);
      } catch (Exception ex) {
        return '10';
      }
      return String.valueOf(
        Math.max(1, Math.min(MAX_PAGE_SIZE, requestedSize))
      );
    }
    if (name == 'filter.ids' || name == 'postFilter.ids') {
      List<String> validIds = new List<String>();
      for (String id : value.split('[|,]')) {
        if (matchesPattern(id.trim(), NCT_PATTERN)) {
          validIds.add(id.trim());
        }
      }
      return validIds.isEmpty() ? null : String.join(validIds, '|');
    }
    if (name == 'filter.geo' || name == 'postFilter.geo') {
      return matchesPattern(value, GEO_PATTERN) ? value : null;
    }
    if (name == 'filter.overallStatus' || name == 'postFilter.overallStatus') {
      Set<String> statuses = new Set<String>{
        'AVAILABLE',
        'NOT_YET_RECRUITING',
        'RECRUITING',
        'ENROLLING_BY_INVITATION',
        'ACTIVE_NOT_RECRUITING',
        'SUSPENDED',
        'TERMINATED',
        'COMPLETED',
        'WITHDRAWN',
        'UNKNOWN'
      };
      List<String> validStatuses = new List<String>();
      for (String status : value.split('[|,]')) {
        if (statuses.contains(status.trim())) {
          validStatuses.add(status.trim());
        }
      }
      return validStatuses.isEmpty() ? null : String.join(validStatuses, '|');
    }
    if (name == 'sort') {
      List<String> validSorts = new List<String>();
      for (String sortValue : value.split('[|,]')) {
        if (
          matchesPattern(sortValue.trim(), SORT_PATTERN) &&
          validSorts.size() < 2
        ) {
          validSorts.add(sortValue.trim());
        }
      }
      return validSorts.isEmpty() ? null : String.join(validSorts, '|');
    }
    if (name == 'fields') {
      List<String> validFields = new List<String>();
      for (String field : value.split('[|,]')) {
        if (matchesPattern(field.trim(), FIELD_PATTERN)) {
          validFields.add(field.trim());
        }
      }
      if (!validFields.contains('NCTId')) {
        validFields.add('NCTId');
      }
      return validFields.isEmpty() ? null : String.join(validFields, '|');
    }
    return value;
  }

  private static HttpResponse sendRequest(String queryString) {
    HttpRequest request = new HttpRequest();
    request.setEndpoint(
      'callout:' + NAMED_CREDENTIAL + '/studies' + queryString
    );
    request.setMethod('GET');
    request.setTimeout(10000);
    return new Http().send(request);
  }

  private static Result parseSuccess(String responseBody) {
    Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(
      responseBody
    );
    List<Object> summaries = new List<Object>();
    Object rawStudies = payload.get('studies');
    if (rawStudies instanceof List<Object>) {
      for (Object rawStudy : (List<Object>) rawStudies) {
        summaries.add(toSummary((Map<String, Object>) rawStudy));
      }
    }
    Result result = new Result();
    result.success = true;
    result.studiesJson = JSON.serialize(summaries);
    result.returnedStudyCount = summaries.size();
    result.nextPageToken = scalarValue(payload.get('nextPageToken'));
    return result;
  }

  private static Map<String, Object> toSummary(Map<String, Object> study) {
    Map<String, Object> protocol = mapValue(study.get('protocolSection'));
    Map<String, Object> identification = mapValue(
      protocol.get('identificationModule')
    );
    Map<String, Object> status = mapValue(protocol.get('statusModule'));
    Map<String, Object> sponsors = mapValue(
      protocol.get('sponsorCollaboratorsModule')
    );
    Map<String, Object> design = mapValue(protocol.get('designModule'));
    Map<String, Object> conditions = mapValue(protocol.get('conditionsModule'));
    Map<String, Object> eligibility = mapValue(
      protocol.get('eligibilityModule')
    );
    Map<String, Object> contactsLocations = mapValue(
      protocol.get('contactsLocationsModule')
    );
    Map<String, Object> description = mapValue(
      protocol.get('descriptionModule')
    );
    String nctId = scalarValue(identification.get('nctId'));
    return new Map<String, Object>{
      'nctId' => nctId,
      'studyUrl' => nctId == null
        ? null
        : 'https://clinicaltrials.gov/study/' + nctId,
      'briefTitle' => scalarValue(identification.get('briefTitle')),
      'overallStatus' => scalarValue(status.get('overallStatus')),
      'phase' => firstValue(design.get('phases')),
      'studyType' => scalarValue(design.get('studyType')),
      'conditions' => collectionValue(conditions.get('conditions')),
      'leadSponsor' => scalarValue(
        mapValue(sponsors.get('leadSponsor')).get('name')
      ),
      'locations' => locationValue(contactsLocations.get('locations')),
      'briefSummary' => scalarValue(description.get('briefSummary')),
      'hasResults' => study.get('hasResults'),
      'startDate' => dateStructValue(status.get('startDateStruct')),
      'primaryCompletionDate' => dateStructValue(
        status.get('primaryCompletionDateStruct')
      ),
      'completionDate' => dateStructValue(status.get('completionDateStruct')),
      'studyFirstPostDate' => dateStructValue(
        status.get('studyFirstPostDateStruct')
      ),
      'lastUpdatePostDate' => dateStructValue(
        status.get('lastUpdatePostDateStruct')
      )
    };
  }

  private static Result errorResult(String message) {
    Result result = new Result();
    result.success = false;
    result.errorMessage = message;
    result.studiesJson = '[]';
    result.returnedStudyCount = 0;
    return result;
  }

  private static String collectionValue(Object value) {
    if (value instanceof List<Object>) {
      List<String> values = new List<String>();
      for (Object item : (List<Object>) value) {
        values.add(scalarValue(item));
      }
      return String.join(values, '|');
    }
    return scalarValue(value);
  }

  private static String scalarValue(Object value) {
    return value == null ? null : String.valueOf(value);
  }

  private static Boolean matchesPattern(String value, String pattern) {
    return value.replaceAll(pattern, '') == '';
  }

  private static Map<String, Object> mapValue(Object value) {
    return value instanceof Map<String, Object>
      ? (Map<String, Object>) value
      : new Map<String, Object>();
  }

  private static String firstValue(Object value) {
    if (value instanceof List<Object> && !((List<Object>) value).isEmpty()) {
      return scalarValue(((List<Object>) value)[0]);
    }
    return scalarValue(value);
  }

  private static String dateStructValue(Object value) {
    return scalarValue(mapValue(value).get('date'));
  }

  private static String locationValue(Object value) {
    if (!(value instanceof List<Object>)) {
      return null;
    }
    List<String> locations = new List<String>();
    for (Object item : (List<Object>) value) {
      Map<String, Object> location = mapValue(item);
      List<String> parts = new List<String>();
      for (
        String field : new List<String>{
          'facility',
          'city',
          'state',
          'country'
        }
      ) {
        String part = scalarValue(location.get(field));
        if (String.isNotBlank(part)) {
          parts.add(part);
        }
      }
      if (!parts.isEmpty()) {
        locations.add(String.join(parts, ', '));
      }
      if (locations.size() == 3) {
        break;
      }
    }
    return locations.isEmpty() ? null : String.join(locations, '; ');
  }

  private static String truncate(String value, Integer maxLength) {
    if (String.isBlank(value) || value.length() <= maxLength) {
      return value;
    }
    return value.substring(0, maxLength - 3) + '...';
  }

  public class Request {
    @InvocableVariable(
      label='Query Parameters JSON'
      description='JSON array of ClinicalTrials.gov /studies name/value objects, for example [{"name":"query.cond","value":"lung cancer"}]'
      required=false
    )
    public String queryParamsJson;
  }

  public class Result {
    @InvocableVariable(
      label='Studies JSON'
      description='JSON array of matching clinical trial summaries'
    )
    public String studiesJson;

    @InvocableVariable(
      label='Next Page Token'
      description='Token for the next page of the same query'
    )
    public String nextPageToken;

    @InvocableVariable(
      label='Success'
      description='Whether the ClinicalTrials.gov request succeeded'
    )
    public Boolean success;

    @InvocableVariable(
      label='Error Message'
      description='Safe user-facing error message'
    )
    public String errorMessage;

    @InvocableVariable(
      label='Applied Query Parameters JSON'
      description='The normalized ClinicalTrials.gov parameters actually sent to the API'
    )
    public String appliedQueryJson;

    @InvocableVariable(
      label='Returned Study Count'
      description='Number of studies returned in this page'
    )
    public Integer returnedStudyCount;
  }

  private class QueryBuild {
    String queryString;
    String appliedQueryJson;
  }
}
