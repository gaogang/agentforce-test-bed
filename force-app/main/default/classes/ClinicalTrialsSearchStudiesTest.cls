@IsTest
private class ClinicalTrialsSearchStudiesTest {
  private static String lastEndpoint;

  @IsTest
  static void searchesWithOasParametersAndBuildsSummary() {
    Test.setMock(
      HttpCalloutMock.class,
      new ClinicalTrialsMock(
        200,
        '{"studies":[{"protocolSection":{"identificationModule":{"nctId":"NCT00000001","briefTitle":"Lung cancer study"},"statusModule":{"overallStatus":"RECRUITING","startDateStruct":{"date":"2023-01-15","type":"ACTUAL"},"primaryCompletionDateStruct":{"date":"2025-06-30","type":"ESTIMATED"},"completionDateStruct":{"date":"2025-12-31","type":"ESTIMATED"},"studyFirstPostDateStruct":{"date":"2022-11-01","type":"ACTUAL"},"lastUpdatePostDateStruct":{"date":"2023-02-01","type":"ACTUAL"}},"designModule":{"phases":["PHASE2"],"studyType":"INTERVENTIONAL"},"sponsorCollaboratorsModule":{"leadSponsor":{"name":"Example Pharma"}},"conditionsModule":{"conditions":["Lung cancer"]},"eligibilityModule":{"eligibilityCriteria":"Adults eligible"},"contactsLocationsModule":{"locations":[{"facility":"General Hospital","city":"Boston","state":"Massachusetts","country":"United States"}]},"descriptionModule":{"briefSummary":"A study summary"}},"hasResults":false}],"nextPageToken":"next-token"}'
      )
    );
    ClinicalTrialsSearchStudies.Request request = new ClinicalTrialsSearchStudies.Request();
    request.queryParamsJson = '[{"name":"query.cond","value":"lung cancer"},{"name":"filter.overallStatus","value":["RECRUITING"]},{"name":"pageSize","value":100},{"name":"unknown","value":"ignored"}]';

    Test.startTest();
    ClinicalTrialsSearchStudies.Result result = ClinicalTrialsSearchStudies.search(
      new List<ClinicalTrialsSearchStudies.Request>{ request }
    )[0];
    Test.stopTest();

    System.assertEquals(true, result.success);
    System.assert(result.studiesJson.contains('NCT00000001'));
    System.assert(
      result.studiesJson.contains(
        'https://clinicaltrials.gov/study/NCT00000001'
      )
    );
    System.assert(
      result.studiesJson.contains(
        'General Hospital, Boston, Massachusetts, United States'
      )
    );
    System.assert(result.studiesJson.contains('A study summary'));
    System.assert(result.studiesJson.contains('2023-01-15'));
    System.assert(result.studiesJson.contains('2025-06-30'));
    System.assert(result.studiesJson.contains('2025-12-31'));
    System.assert(result.studiesJson.contains('2022-11-01'));
    System.assert(result.studiesJson.contains('2023-02-01'));
    System.assert(result.appliedQueryJson.contains('query.cond'));
    System.assert(result.appliedQueryJson.contains('filter.overallStatus'));
    System.assertEquals(1, result.returnedStudyCount);
    System.assertEquals('next-token', result.nextPageToken);
    System.assert(
      result.appliedQueryJson.contains('LastUpdateSubmitDate:desc')
    );
    System.assert(lastEndpoint.contains('query.cond=lung+cancer'));
    System.assert(lastEndpoint.contains('filter.overallStatus=RECRUITING'));
    System.assert(lastEndpoint.contains('pageSize=10'));
    System.assert(lastEndpoint.contains('sort=LastUpdateSubmitDate%3Adesc'));
    System.assert(!lastEndpoint.contains('unknown'));
  }

  @IsTest
  static void forcesLastUpdateSubmitDateDescendingSort() {
    Test.setMock(
      HttpCalloutMock.class,
      new ClinicalTrialsMock(200, '{"studies":[]}')
    );
    ClinicalTrialsSearchStudies.Request request = new ClinicalTrialsSearchStudies.Request();
    request.queryParamsJson = '[{"name":"query.cond","value":"asthma"},{"name":"sort","value":"@relevance"}]';

    Test.startTest();
    ClinicalTrialsSearchStudies.Result result = ClinicalTrialsSearchStudies.search(
      new List<ClinicalTrialsSearchStudies.Request>{ request }
    )[0];
    Test.stopTest();

    System.assertEquals(true, result.success);
    System.assert(
      result.appliedQueryJson.contains('LastUpdateSubmitDate:desc')
    );
    System.assert(!result.appliedQueryJson.contains('@relevance'));
    System.assert(lastEndpoint.contains('sort=LastUpdateSubmitDate%3Adesc'));
    System.assert(!lastEndpoint.contains('@relevance'));
  }

  @IsTest
  static void filtersInvalidStructuredValuesAndForcesJson() {
    Test.setMock(
      HttpCalloutMock.class,
      new ClinicalTrialsMock(200, '{"studies":[]}')
    );
    ClinicalTrialsSearchStudies.Request request = new ClinicalTrialsSearchStudies.Request();
    request.queryParamsJson = '[{"name":"filter.ids","value":"bad-id|NCT00000002"},{"name":"filter.geo","value":"Boston"},{"name":"format","value":"csv"},{"name":"countTotal","value":true}]';

    Test.startTest();
    ClinicalTrialsSearchStudies.Result result = ClinicalTrialsSearchStudies.search(
      new List<ClinicalTrialsSearchStudies.Request>{ request }
    )[0];
    Test.stopTest();

    System.assertEquals(true, result.success);
    System.assert(lastEndpoint.contains('filter.ids=NCT00000002'));
    System.assert(!lastEndpoint.contains('filter.geo'));
    System.assert(lastEndpoint.contains('format=json'));
    System.assert(lastEndpoint.contains('countTotal=false'));
  }

  @IsTest
  static void alwaysRequestsNctIdWhenFieldsAreRestricted() {
    Test.setMock(
      HttpCalloutMock.class,
      new ClinicalTrialsMock(200, '{"studies":[]}')
    );
    ClinicalTrialsSearchStudies.Request request = new ClinicalTrialsSearchStudies.Request();
    request.queryParamsJson = '[{"name":"fields","value":["BriefTitle","OverallStatus"]}]';

    Test.startTest();
    ClinicalTrialsSearchStudies.search(
      new List<ClinicalTrialsSearchStudies.Request>{ request }
    );
    Test.stopTest();

    System.assert(
      lastEndpoint.contains('fields=BriefTitle%7COverallStatus%7CNCTId')
    );
  }

  @IsTest
  static void returnsSafeErrorForServiceFailure() {
    Test.setMock(
      HttpCalloutMock.class,
      new ClinicalTrialsMock(503, 'service unavailable')
    );
    ClinicalTrialsSearchStudies.Request request = new ClinicalTrialsSearchStudies.Request();

    Test.startTest();
    ClinicalTrialsSearchStudies.Result result = ClinicalTrialsSearchStudies.search(
      new List<ClinicalTrialsSearchStudies.Request>{ request }
    )[0];
    Test.stopTest();

    System.assertEquals(false, result.success);
    System.assertEquals(
      'The ClinicalTrials.gov service is temporarily unavailable. Please try again.',
      result.errorMessage
    );
    System.assertEquals('[]', result.studiesJson);
  }

  private class ClinicalTrialsMock implements HttpCalloutMock {
    private Integer statusCode;
    private String responseBody;
    ClinicalTrialsMock(Integer statusCode, String responseBody) {
      this.statusCode = statusCode;
      this.responseBody = responseBody;
    }

    public HttpResponse respond(HttpRequest request) {
      ClinicalTrialsSearchStudiesTest.lastEndpoint = request.getEndpoint();
      HttpResponse response = new HttpResponse();
      response.setStatusCode(statusCode);
      response.setBody(responseBody);
      return response;
    }
  }
}
