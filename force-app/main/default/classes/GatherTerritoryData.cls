public with sharing class GatherTerritoryData {

    @InvocableMethod(
        label='Gather Territory Data'
        description='Collects territory performance, market share, cycle plan progress, rep activity, and market news for the given territory. Returns a JSON bundle used as input to the territory insights generator.'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result r = new Result();
            r.territoryDataBundle = buildMockBundle(req.territoryId, req.reportDate);
            results.add(r);
        }
        return results;
    }

    private static String buildMockBundle(String territoryId, Date reportDate) {
        String reportDateStr = reportDate != null
            ? String.valueOf(reportDate)
            : String.valueOf(Date.today());

        Map<String, Object> bundle = new Map<String, Object>{
            'territory' => new Map<String, Object>{
                'territoryId'    => territoryId,
                'territoryName'  => 'North West Region — Cardiology',
                'manager'        => 'Jane Holloway',
                'targetCalls'    => 120,
                'cycleStartDate' => '2026-07-01',
                'cycleEndDate'   => '2026-07-31'
            },
            'performance' => new Map<String, Object>{
                'revenueActual'        => 1420000,
                'revenueTarget'        => 1600000,
                'revenueAttainment'    => 0.888,
                'priorPeriodRevenue'   => 1310000,
                'growthVsPriorPeriod'  => 0.084
            },
            'marketShare' => new List<Object>{
                new Map<String, Object>{
                    'product'      => 'CardioPlus',
                    'currentShare' => 0.28,
                    'priorShare'   => 0.25,
                    'trend'        => 'up',
                    'marketRank'   => 2
                },
                new Map<String, Object>{
                    'product'      => 'VascuShield',
                    'currentShare' => 0.14,
                    'priorShare'   => 0.17,
                    'trend'        => 'down',
                    'marketRank'   => 4
                }
            },
            'cyclePlanProgress' => new Map<String, Object>{
                'callsPlanned'          => 120,
                'callsCompleted'        => 74,
                'daysRemainingInCycle'  => 8,
                'callsRequiredPerDay'   => 5.75
            },
            'repActivity' => new List<Object>{
                new Map<String, Object>{
                    'repName'          => 'Carlos Mendes',
                    'callsCompleted'   => 38,
                    'callsTarget'      => 40,
                    'lastActivityDate' => '2026-07-22'
                },
                new Map<String, Object>{
                    'repName'          => 'Priya Nair',
                    'callsCompleted'   => 19,
                    'callsTarget'      => 40,
                    'lastActivityDate' => '2026-07-18'
                },
                new Map<String, Object>{
                    'repName'          => 'Tom Bauer',
                    'callsCompleted'   => 17,
                    'callsTarget'      => 40,
                    'lastActivityDate' => '2026-07-21'
                }
            },
            'marketNews' => new List<Object>{
                new Map<String, Object>{
                    'headline'      => 'BrandX receives new cardiology indication approval',
                    'source'        => 'PharmaTimes',
                    'date'          => '2026-07-20',
                    'relevance'     => 'high',
                    'impactSummary' => 'Primary competitor expands label into shared patient population'
                },
                new Map<String, Object>{
                    'headline'      => 'Regional cardiology conference scheduled for 2026-08-05',
                    'source'        => 'CardioSociety NW',
                    'date'          => '2026-07-19',
                    'relevance'     => 'medium',
                    'impactSummary' => 'Opportunity for KOL engagement ahead of new cycle'
                }
            },
            'reportDate' => reportDateStr
        };

        return JSON.serialize(bundle);
    }

    public class Request {
        @InvocableVariable(
            label='Territory Id'
            description='Salesforce Territory2 record Id for which to gather data'
            required=true
        )
        public String territoryId;

        @InvocableVariable(
            label='Report Date'
            description='Date for which the insights report is being generated'
            required=false
        )
        public Date reportDate;
    }

    public class Result {
        @InvocableVariable(
            label='territoryDataBundle'
            description='JSON string containing territory performance, market share, cycle plan progress, rep activity, and market news'
        )
        public String territoryDataBundle;
    }
}
