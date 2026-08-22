# C4 — Reflection: Territory Insights Agent

## Overview

| Property | Value |
|---|---|
| Agent Name | `C4_reflection_territory_insights` |
| Pattern | Reflection |
| Domain | Pharma Sales — Territory Intelligence |
| Execution Mode | Autonomous — scheduled once daily |

The agent runs autonomously on a daily schedule. It collects territory data from multiple sources (market share, sales performance, cycle progress, and news), generates a narrative territory insights report plus claim-level evidence references, then applies a reflection loop in which a deterministic validator and critic subagent review the draft and return structured feedback to the generator subagent. The loop continues until quality is approved or the maximum iteration count (n = 3) is reached. Final insights are stored in a custom Salesforce object with run metadata and idempotent write semantics.

---

## Design Pattern: Reflection

The reflection pattern separates **generation** from **critique**. Rather than producing a single output and finishing, the generator subagent iterates on its draft based on structured feedback from an independent critic subagent. This pattern trades latency and token cost for higher accuracy and output quality — the right trade-off when territory insights are consumed by sales leadership and field managers who act on them directly.

```
Scheduled Trigger (daily)
        │
        ▼
[Action 1] Gather Territory Data
        │  Output: territoryDataBundle
        ▼
      [Subagent: Territory Insights Generator]
        │  Produces: insightsDraft (v1) + evidenceMap
        ▼
┌───────────────────────────────────────────┐
│           Reflection Loop (max 3)         │
│                                           │
│  [Deterministic Validator]                │
│       │  Checks schema, required content, │
│       │  numeric consistency, actionability
│       │                                   │
│  Pass? ──NO──► return fixes to Generator  │
│       │                                   │
│       YES                                 │
│       │                                   │
│  [Subagent: Territory Insights Critic]    │
│       │  Produces: critiqueReport         │
│       │                                   │
│  Approved? ──YES──────────────────────┐   │
│       │                               │   │
│       NO                              │   │
│       │                               │   │
│  [Subagent: Territory Insights        │   │
│   Generator] (revision pass)          │   │
│       │  Produces: insightsDraft (vN) │   │
│       └──► back to Critic             │   │
│                                       │   │
│  Max iterations reached? ─────────────┘   │
└───────────────────────────────────────────┘
        │
        ▼
[Action 2] Store Territory Insights
  │  Input: finalInsightsDraft, evidenceMap, iterationCount,
  │         approvalStatus, dataBundleHash, runMetadataJson
        │  Output: recordId
        ▼
Daily Insights Record saved to Territory_Insight__c
```

---

## Agent Structure

### Orchestrator Agent: `C4_reflection_territory_insights`

| Property | Value |
|---|---|
| Agent Label | C4 Territory Insights |
| Purpose | Daily autonomous collection, generation, and quality-gated storage of territory insights |
| Trigger | Scheduled Flow — fires once per day at 06:00 org time |
| Subagents | Territory Insights Generator, Territory Insights Critic |

**System Instructions (to be configured in Agentforce):**

```
You are a daily territory intelligence agent for a pharmaceutical sales organisation.

Each day you must:
1. Call the "Gather Territory Data" action to collect all required territory inputs.
2. Hand the complete data bundle to the Territory Insights Generator subagent to produce
   an initial insights draft and evidence map.
3. Run deterministic validation on the draft before invoking the Critic. The validator must
   check: required fields, internal numeric consistency, and actionability formatting.
4. If deterministic validation fails, pass deterministic issues back to the Generator.
5. Pass the draft, evidence map, and territoryDataBundle to the Territory Insights Critic
   subagent for review.
6. If the Critic returns status="approved", proceed to step 8.
7. If the Critic returns status="revise", pass the critique report back to the Territory
   Insights Generator for a revision pass. Repeat steps 3–7 up to a maximum of 3 total
   iterations (including the first draft).
8. Call the "Store Territory Insights" action with the final draft, evidence map,
   iteration count, approval status, dataBundleHash, and run metadata.

Do not fabricate territory data. Do not skip the critique loop. Do not exceed 3 iterations.
```

---

## Subagents

### Subagent 1 — Territory Insights Generator

| Property | Value |
|---|---|
| Subagent Name | Territory Insights Generator |
| Role | Generate (and iteratively revise) a territory insights report |
| Invoked By | C4_reflection_territory_insights orchestrator |
| LLM Model | `sfdc_ai__DefaultBedrockAnthropicClaude35Sonnet` (Sonnet-class) |
| Model Rationale | Generation requires broad reasoning, synthesis across multiple data sources, and fluent narrative writing. A Sonnet-class model balances output quality with latency across up to 3 iterations. |

**Topic Instructions:**

```
You are a territory insights writer for a pharmaceutical sales organisation.

On first invocation:
- You will receive a territoryDataBundle containing market share data, sales performance,
  cycle plan progress, rep activity metrics, and local market news.
- Produce a territory insights report with five narrative text fields: performanceSummary,
  marketShareInsights, competitiveInsights, cyclePlanInsights, and recommendedFocusAreas.
- All fields must be written as clear, manager-readable prose — no JSON objects, no bullet
  lists of raw numbers. Interpret the data; do not restate it.
- Return the report as a single JSON object matching the TerritoryInsightsDraft schema.
- Also return an evidenceMap containing claim-level source references from territoryDataBundle.

On revision invocations:
- You will receive your previous insightsDraft together with a critiqueReport from the
  Territory Insights Critic subagent.
- Address every point raised in the critiqueReport.
- Return a revised insightsDraft with an incremented version number and an updated evidenceMap.

Do not fabricate data not present in the territoryDataBundle.
Do not change factual values when revising — only improve clarity, completeness, and structure.
```

**Output Schema — `TerritoryInsightsDraft`:**

| Field | Type | Description |
|---|---|---|
| `version` | Integer | Starts at 1; incremented on each revision |
| `territoryId` | String | Salesforce Territory record Id |
| `reportDate` | Date | Date of report generation |
| `performanceSummary` | String | Narrative overview of territory performance vs target, including attainment percentage and growth vs prior period |
| `marketShareInsights` | String | Narrative interpretation of product share trends and what they signal for rep focus |
| `competitiveInsights` | String | Narrative summary of identified competitor activity and recommended response |
| `cyclePlanInsights` | String | Narrative assessment of cycle plan progress, pace risk, and rep-level observations |
| `recommendedFocusAreas` | String | Prioritised narrative list of concrete actions for the territory manager, each assigned to a named rep with a suggested timeframe |
| `dataSourceTimestamp` | DateTime | Timestamp of the data bundle used as input |
| `evidenceMap` | Array | Claim-level references showing where each key statement came from in `territoryDataBundle` |
| `evidenceMap[].claimId` | String | Unique identifier for a claim in the narrative |
| `evidenceMap[].field` | String | Narrative field containing the claim |
| `evidenceMap[].claimText` | String | Exact claim text or compact paraphrase |
| `evidenceMap[].sourcePath` | String | JSON path in `territoryDataBundle` (example: `performance.revenueAttainment`) |
| `evidenceMap[].sourceValue` | String | Source value used to support the claim |
| `evidenceMap[].confidence` | Number | Generator confidence score from 0.0 to 1.0 |

---

### Subagent 2 — Territory Insights Critic

| Property | Value |
|---|---|
| Subagent Name | Territory Insights Critic |
| Role | Review the insights draft and return structured feedback or approval |
| Invoked By | C4_reflection_territory_insights orchestrator |
| LLM Model | `sfdc_ai__DefaultBedrockAnthropicClaude35Sonnet` (default), escalate to `sfdc_ai__DefaultBedrockAnthropicClaude3Opus` when needed |
| Model Rationale | Most critique passes can run on a Sonnet-class model at lower latency and cost. Escalation to Opus is reserved for low-confidence or contradiction-heavy drafts where deeper reasoning is required. |

**Topic Instructions:**

```
You are a quality reviewer for territory insights reports in a pharmaceutical sales organisation.

You will receive a TerritoryInsightsDraft, evidenceMap, and territoryDataBundle. Your job is to evaluate it against these criteria:
1. Factual completeness — all five narrative fields are present and contain specific,
   substantive content (not placeholder text or generic statements).
2. Internal consistency — figures and claims cited across the five narrative fields do not
   contradict each other.
3. Actionability — recommendedFocusAreas names specific reps and suggests concrete next
   steps with timeframes; it must not be a restatement of problems without solutions.
4. Clarity — all fields are written in plain language understandable by a non-technical
   territory manager; no raw JSON, no unexplained abbreviations.
5. Source fidelity — no claims are made that cannot be traced back to the territoryDataBundle
  provided as input, and evidenceMap source paths are valid.

Return a critiqueReport JSON object:
- If the draft meets all criteria: set status="approved", leave issues as an empty array.
- If the draft fails any criterion: set status="revise", populate issues with one entry per
  problem found, including the field name, the problem description, and a suggested fix.
- Add `criticConfidence` from 0.0 to 1.0 to indicate confidence in the verdict.

Be a rigorous reviewer. Do not approve a draft that contains vague language, missing data,
or unsupported claims.
```

**Output Schema — `CritiqueReport`:**

| Field | Type | Description |
|---|---|---|
| `status` | String | `"approved"` or `"revise"` |
| `iterationReviewed` | Integer | Version number of the draft reviewed |
| `criticConfidence` | Number | Critic confidence score from 0.0 to 1.0 |
| `issues` | Array | Empty if approved; otherwise one object per issue |
| `issues[].field` | String | Draft field where the issue was found |
| `issues[].problem` | String | Description of the quality problem |
| `issues[].suggestedFix` | String | Concrete guidance for the Generator subagent |

---

## Actions

### Action 1 — Gather Territory Data

| Property | Value |
|---|---|
| Action Name | Gather Territory Data |
| Type | Flow / Apex |
| Purpose | Collect all data inputs required for territory insight generation |

**Input Variables:**

| Variable | Type | Description |
|---|---|---|
| `territoryId` | String | Salesforce Territory record Id (injected by scheduled trigger) |
| `reportDate` | Date | Today's date (injected by scheduled trigger) |

**Output Variables:**

| Variable | Type | Description |
|---|---|---|
| `territoryDataBundle` | JSON | Aggregated territory data payload |
| `dataBundleHash` | String | Stable hash of the canonical bundle JSON for auditability and idempotency |

**Logic:**
1. Query `Territory2` and related records to retrieve territory metadata.
2. Query `Territory_Performance__c` for current-cycle and prior-cycle actuals vs targets.
3. Query `Market_Share__c` (or equivalent custom object) for product-level share by territory.
4. Query `Event` and `Task` records to derive rep call activity and cycle plan progress.
5. Query `Territory_News__c` or invoke an external news feed action for local market signals.
6. Assemble all results into a single `territoryDataBundle` JSON object.
7. Compute `dataBundleHash` from canonical JSON serialization of the bundle.
8. Return the bundle and hash to the orchestrator.

**Mock Data:**
```json
{
  "territory": {
    "territoryId": "0MWg00000001AbcAAE",
    "territoryName": "North West Region — Cardiology",
    "manager": "Jane Holloway",
    "targetCalls": 120,
    "cycleStartDate": "2026-07-01",
    "cycleEndDate": "2026-07-31"
  },
  "performance": {
    "revenueActual": 1420000,
    "revenueTarget": 1600000,
    "revenueAttainment": 0.888,
    "priorPeriodRevenue": 1310000,
    "growthVsPriorPeriod": 0.084
  },
  "marketShare": [
    {
      "product": "CardioPlus",
      "currentShare": 0.28,
      "priorShare": 0.25,
      "trend": "up",
      "marketRank": 2
    },
    {
      "product": "VascuShield",
      "currentShare": 0.14,
      "priorShare": 0.17,
      "trend": "down",
      "marketRank": 4
    }
  ],
  "cyclePlanProgress": {
    "callsPlanned": 120,
    "callsCompleted": 74,
    "daysRemainingInCycle": 8,
    "callsRequiredPerDay": 5.75
  },
  "repActivity": [
    {
      "repName": "Carlos Mendes",
      "callsCompleted": 38,
      "callsTarget": 40,
      "lastActivityDate": "2026-07-22"
    },
    {
      "repName": "Priya Nair",
      "callsCompleted": 19,
      "callsTarget": 40,
      "lastActivityDate": "2026-07-18"
    },
    {
      "repName": "Tom Bauer",
      "callsCompleted": 17,
      "callsTarget": 40,
      "lastActivityDate": "2026-07-21"
    }
  ],
  "marketNews": [
    {
      "headline": "BrandX receives new cardiology indication approval",
      "source": "PharmaTimes",
      "date": "2026-07-20",
      "relevance": "high",
      "impactSummary": "Primary competitor expands label into shared patient population"
    },
    {
      "headline": "Regional cardiology conference scheduled for 2026-08-05",
      "source": "CardioSociety NW",
      "date": "2026-07-19",
      "relevance": "medium",
      "impactSummary": "Opportunity for KOL engagement ahead of new cycle"
    }
  ]
}
```

---

### Action 2 — Store Territory Insights

| Property | Value |
|---|---|
| Action Name | Store Territory Insights |
| Type | Flow / Apex |
| Purpose | Persist the final approved insights draft as a `Territory_Insight__c` record |

**Input Variables:**

| Variable | Type | Description |
|---|---|---|
| `territoryId` | String | Salesforce Territory2 record Id |
| `reportDate` | Date | Date the insights were generated |
| `performanceSummary` | String | Synthesised narrative from `TerritoryInsightsDraft.performanceSummary` |
| `marketShareInsights` | String | Synthesised narrative from `TerritoryInsightsDraft.marketShareInsights` |
| `competitiveInsights` | String | Synthesised narrative from `TerritoryInsightsDraft.competitiveInsights` |
| `cyclePlanInsights` | String | Synthesised narrative from `TerritoryInsightsDraft.cyclePlanInsights` |
| `recommendedFocusAreas` | String | Synthesised narrative from `TerritoryInsightsDraft.recommendedFocusAreas` |
| `evidenceMapJson` | String | Serialized `TerritoryInsightsDraft.evidenceMap` for audit traceability |
| `iterationCount` | Integer | Number of generator–critic iterations completed |
| `approvalStatus` | String | `"approved"` or `"max_iterations_reached"` |
| `dataBundleHash` | String | Stable hash returned by Action 1 |
| `runMetadataJson` | String | Serialized metadata including model route, durations, and critic confidence |

**Output Variables:**

| Variable | Type | Description |
|---|---|---|
| `recordId` | String | Id of the newly created `Territory_Insight__c` record |
| `success` | Boolean | `true` if record was created without error |

**Logic:**
1. Map each synthesised narrative input to its corresponding `Territory_Insight__c` Long Text Area field.
2. Set `Territory__c` lookup to `territoryId`.
3. Set `Approval_Status__c` and `Iteration_Count__c` from the corresponding inputs.
4. Set `Unique_Key__c` = `territoryId + ':' + reportDate` and upsert to enforce idempotency.
5. Persist `Data_Bundle_Hash__c`, `Run_Metadata__c`, and `Evidence_Map__c` from corresponding inputs.
6. Return the record Id and a `success` flag.

Raw input data bundle is not stored in full. The design stores a stable hash plus compact evidence metadata to support traceability without persisting the full payload.

**Custom Object — `Territory_Insight__c`:**

| Field API Name | Type | Description |
|---|---|---|
| `Territory__c` | Lookup (Territory2) | Parent territory |
| `Report_Date__c` | Date | Date insights were generated |
| `Performance_Summary__c` | Long Text Area (32,768) | Synthesised performance narrative |
| `Market_Share_Insights__c` | Long Text Area (32,768) | Synthesised market share narrative |
| `Competitive_Insights__c` | Long Text Area (32,768) | Synthesised competitive activity narrative |
| `Cycle_Plan_Insights__c` | Long Text Area (32,768) | Synthesised cycle plan narrative |
| `Recommended_Focus_Areas__c` | Long Text Area (32,768) | Synthesised recommended actions narrative |
| `Evidence_Map__c` | Long Text Area (32,768) | JSON evidence map linking claims to source paths |
| `Data_Bundle_Hash__c` | Text (64) | Stable hash of source bundle used for generation |
| `Run_Metadata__c` | Long Text Area (32,768) | JSON run metadata (models, timings, confidence, errors if any) |
| `Unique_Key__c` | Text (80), External ID, Unique | Idempotency key (`territoryId:reportDate`) |
| `Iteration_Count__c` | Number (2, 0) | How many reflection iterations ran |
| `Approval_Status__c` | Picklist | `Approved` / `Max Iterations Reached` |

---

## Salesforce Technologies

### Platform Stack

| Layer | Technology | Role in This Agent |
|---|---|---|
| Agent runtime | **Agentforce** | Hosts the orchestrator and both subagents; routes between them; enforces iteration ceiling |
| Subagent LLMs | **Einstein LLM Gateway** (Bedrock-backed) | Routes each subagent's prompt to its configured model; Sonnet default for both, with conditional Opus escalation for complex critique |
| Scheduling | **Salesforce Scheduled Flow** | Triggers the agent once per day; injects `territoryId` and `reportDate` |
| Data collection | **Apex invocable method** (Action 1) | Runs SOQL across Territory2, custom objects, Event/Task; returns the data bundle |
| Deterministic validation | **Apex validator** (or Flow formula checks) | Performs schema and numeric checks before LLM critique |
| Data persistence | **Apex invocable method** (Action 2) | Inserts the `Territory_Insight__c` record via DML |
| Custom object | **Territory_Insight__c** | Stores the final synthesised insights text and run metadata |
| Org data | **SOQL / standard and custom objects** | Source of truth for performance, market share, and activity data |

### Scheduler: How the Agent Is Triggered

The agent is autonomous — no human initiates a session. The trigger mechanism is a **Salesforce Scheduled Flow** configured as follows:

**Scheduled Flow configuration:**

| Setting | Value |
|---|---|
| Flow Type | Schedule-Triggered Flow |
| Object | Territory2 (one flow run per active territory record) |
| Schedule | Daily at 06:00 org time |
| Batch Size | 1 record per run (one territory at a time) |
| Start Condition | Filter: `Territory2.IsActive = true` |

**How it works step by step:**

1. At 06:00, Salesforce fires the Scheduled Flow for each active `Territory2` record.
2. The Flow calls an **Apex invocable action** (`LaunchTerritoryInsightsAgent`) and passes `territoryId` (from the current Territory2 record) and `reportDate` (today's date via `$Flow.CurrentDate`).
3. The Apex action creates `uniqueRunKey = territoryId + ':' + reportDate` and checks for an existing `Territory_Insight__c` record before launching.
4. The Apex action calls the **Agentforce Agent API** (`ConnectApi.AgentRuntime`) to create a new agent session for `C4_reflection_territory_insights` and submits the initial message containing `territoryId`, `reportDate`, and `uniqueRunKey`.
5. The Agentforce runtime picks up the session, the orchestrator agent begins execution, and the reflection loop runs to completion asynchronously.
6. On completion, Action 2 (Store Territory Insights) upserts using `Unique_Key__c`.

**Key configuration notes:**
- The Scheduled Flow uses **record-triggered batch mode** so each territory runs in its own transaction — one territory's failure does not block others.
- The Apex action that calls the Agent API must run in a **future context** or be enqueued via `Queueable` to avoid mixed-DML errors, since the Flow itself operates in a trigger context.
- The `LaunchTerritoryInsightsAgent` Apex class must be added to the **Connected App** that owns the Agentforce agent session token.
- Retry handling should reuse the same `uniqueRunKey`; Action 2 idempotency prevents duplicate insight records.

### Model Configuration in Agentforce

Each subagent's LLM is set in its **Subagent configuration** inside Agentforce Builder:

- Navigate to **Agentforce > Agents > C4 Territory Insights > Subagents**.
- Open each subagent, go to **Advanced Settings > Model**.
- Select the target model from the Einstein LLM Gateway model list.
- Save and re-activate the agent after changing a model.

This allows the Generator and Critic to use different models without any code change — the routing is handled by the Einstein LLM Gateway at runtime.

**Recommended model routing policy:**
- Generator: always `sfdc_ai__DefaultBedrockAnthropicClaude35Sonnet`
- Critic: default `sfdc_ai__DefaultBedrockAnthropicClaude35Sonnet`
- Critic escalation to `sfdc_ai__DefaultBedrockAnthropicClaude3Opus` when either:
  - `criticConfidence < 0.70`, or
  - deterministic validator detects unresolved numeric contradictions after revision 1

---

## Data Flow Summary

```
Scheduled Flow fires at 06:00 — one run per active Territory2 record
       │  Injects: territoryId="0MWg00000001AbcAAE", reportDate="2026-07-23"
       ▼
Action 1: Gather Territory Data (Apex invocable)
  Output: territoryDataBundle (performance, market share,
          cycle progress, rep activity, market news)
       │
       ▼
Territory Insights Generator — Sonnet model (iteration 1)
  Input : territoryDataBundle
  Output: insightsDraft {
    version: 1,
    performanceSummary:    "North West Cardiology is tracking at 88.8% of revenue
                            target with 8 days left in the cycle, up 8.4% on the
                            prior period. Acceleration is needed to close the gap.",
    marketShareInsights:   "CardioPlus gained 3 points to reach 28% share,
                            confirming positive momentum. VascuShield has slipped
                            to 14%, down 3 points — requires attention.",
    competitiveInsights:   "BrandX received a new cardiology indication on 20 July.
                            This expands their addressable patient population and
                            poses a direct risk to CardioPlus accounts.",
    cyclePlanInsights:     "74 of 120 calls completed. At current pace the territory
                            needs 5.75 calls per rep per day to close out the cycle.
                            Priya Nair and Tom Bauer are significantly behind.",
    recommendedFocusAreas: "1. Carlos Mendes to prioritise BrandX accounts this week.
                            2. Jane Holloway to coach Priya Nair on call scheduling
                            by 2026-07-25. 3. All reps to attend cardiology
                            conference on 2026-08-05 for KOL engagement.",
    evidenceMap: [{
      claimId: "C-001",
      field: "performanceSummary",
      claimText: "Territory is at 88.8% attainment",
      sourcePath: "performance.revenueAttainment",
      sourceValue: "0.888",
      confidence: 0.98
    }]
  }
       │
       ▼
Deterministic Validator
  Input : insightsDraft v1 + territoryDataBundle
  Output: pass
       │
       ▼
Territory Insights Critic — Sonnet model (review 1)
  Input : insightsDraft v1 + evidenceMap + territoryDataBundle
  Output: critiqueReport {
    status: "revise",
    iterationReviewed: 1,
    criticConfidence: 0.82,
    issues: [{
      field: "recommendedFocusAreas",
      problem: "Action 1 does not specify which BrandX accounts or what message to use.",
      suggestedFix: "Name the top 2-3 BrandX accounts and reference the new indication
                    as the conversation trigger."
    }]
  }
       │ status=revise
       ▼
Territory Insights Generator — Sonnet model (iteration 2)
  Input : insightsDraft v1 + critiqueReport
  Output: insightsDraft {
    version: 2,
    ...
    recommendedFocusAreas: "1. Carlos Mendes to visit Dr. Patel and Dr. Okafor this
                            week — lead with BrandX's new indication and position
                            CardioPlus's longer safety record as the differentiator.
                            2. Jane Holloway to coach Priya Nair on call scheduling
                            by 2026-07-25. 3. All reps to attend cardiology
                            conference on 2026-08-05 for KOL engagement."
  }
       │
       ▼
Territory Insights Critic — Sonnet model (review 2)
  Input : insightsDraft v2 + evidenceMap + territoryDataBundle
  Output: critiqueReport {
    status: "approved",
    iterationReviewed: 2,
    criticConfidence: 0.93,
    issues: []
  }
       │ status=approved
       ▼
Action 2: Store Territory Insights (Apex invocable)
  Input : territoryId, reportDate, performanceSummary, marketShareInsights,
          competitiveInsights, cyclePlanInsights, recommendedFocusAreas (all narrative),
          evidenceMapJson, dataBundleHash, runMetadataJson,
          iterationCount=2, approvalStatus="approved"
  Output: recordId="a1Bg00000003XyzAAE", success=true
       │
       ▼
Territory_Insight__c record upserted — narrative fields + audit metadata
```

---

## Reflection Loop Decision Logic

```
iterationCount = 1

LOOP:
  insightsDraft = Generator.run(territoryDataBundle, previousDraft?, critiqueReport?)
  validationResult = DeterministicValidator.run(insightsDraft, territoryDataBundle)

  IF validationResult.status == "revise":
    critiqueReport = validationResult.asCritiqueReport()
    GOTO REVISION_CHECK

  criticModel = "sonnet"
  critiqueReport = Critic.run(insightsDraft, evidenceMap, territoryDataBundle, criticModel)

  IF critiqueReport.status == "revise" AND iterationCount > 1 AND critiqueReport.criticConfidence < 0.70:
    criticModel = "opus"
    critiqueReport = Critic.run(insightsDraft, evidenceMap, territoryDataBundle, criticModel)

  IF critiqueReport.status == "approved":
      approvalStatus = "approved"
      BREAK

REVISION_CHECK:
  IF iterationCount >= 3:
      approvalStatus = "max_iterations_reached"
      BREAK

  iterationCount += 1

StoreInsights(insightsDraft, evidenceMap, dataBundleHash, runMetadataJson, iterationCount, approvalStatus)
```

The orchestrator is responsible for tracking `iterationCount`, model escalation, and enforcing the ceiling. The Generator and Critic subagents are stateless — they do not track iteration history themselves.

---

## Subagent Configuration Reference

| Setting | Value |
|---|---|
| Orchestrator Label | C4 Territory Insights |
| Subagent 1 | Territory Insights Generator |
| Subagent 2 | Territory Insights Critic |
| Actions | Gather Territory Data, Store Territory Insights |
| Escalation Subagent | Default Escalation |
| Off-Topic Subagent | Default Off Topic |
| Ambiguous Question Subagent | Default Ambiguous Question |
| Router Subagent | Default Router |

---

## Implementation Checklist

**Custom Object**
- [ ] Create `Territory_Insight__c` with the five narrative Long Text Area fields, `Evidence_Map__c`, `Data_Bundle_Hash__c`, `Run_Metadata__c`, `Unique_Key__c` (External ID + Unique), `Iteration_Count__c`, `Approval_Status__c`, `Territory__c`, and `Report_Date__c`

**Actions**
- [ ] Create Apex invocable method `GatherTerritoryData` with mock data; wire `territoryId` and `reportDate` as inputs, `territoryDataBundle` and `dataBundleHash` as outputs
- [ ] Create deterministic validator action to check required fields, numeric consistency, and minimum actionability constraints before critic invocation
- [ ] Create Apex invocable method `StoreTerritoryInsights`; wire the five narrative text fields, `evidenceMapJson`, `dataBundleHash`, `runMetadataJson`, `territoryId`, `reportDate`, `iterationCount`, and `approvalStatus` as inputs; wire `recordId` and `success` as outputs
- [ ] Confirm Store action persists compact audit metadata (hash + evidence + run metadata) without storing the full raw `territoryDataBundle`

**Subagents**
- [ ] Configure **Territory Insights Generator** subagent topic instructions (including "all fields must be narrative prose" constraint)
- [ ] Set Generator model to `sfdc_ai__DefaultBedrockAnthropicClaude35Sonnet` in Agentforce Builder > Advanced Settings > Model
- [ ] Define `TerritoryInsightsDraft` output schema on Generator (five String fields + metadata + evidenceMap)
- [ ] Configure **Territory Insights Critic** subagent topic instructions (five criteria)
- [ ] Set Critic default model to `sfdc_ai__DefaultBedrockAnthropicClaude35Sonnet`; define escalation rule to `sfdc_ai__DefaultBedrockAnthropicClaude3Opus`
- [ ] Define `CritiqueReport` output schema on Critic

**Orchestrator**
- [ ] Configure orchestrator system instructions with deterministic validation, critic review, and 3-iteration ceiling
- [ ] Register both actions and both subagents on the `C4_reflection_territory_insights` agent

**Scheduler**
- [ ] Create Schedule-Triggered Flow on Territory2, daily at 06:00, filtered to `IsActive = true`
- [ ] Add Apex invocable action `LaunchTerritoryInsightsAgent` to the Flow; pass `territoryId` from the current record and `reportDate` from `$Flow.CurrentDate`
- [ ] Implement `LaunchTerritoryInsightsAgent` as a `Queueable` Apex class that calls the Agentforce Agent API (`ConnectApi.AgentRuntime`) to avoid mixed-DML errors
- [ ] In `LaunchTerritoryInsightsAgent`, create `uniqueRunKey = territoryId + ':' + reportDate` and pass it into the session payload
- [ ] Add the Apex class to the Connected App that owns the Agentforce session token

**Testing**
- [ ] Test Generator in isolation with the mock data bundle — confirm all five fields are narrative prose
- [ ] Test Generator evidenceMap output — confirm source paths resolve against `territoryDataBundle`
- [ ] Test deterministic validator with malformed draft — confirm fast-fail before critic invocation
- [ ] Test Critic with a deliberately weak draft — confirm `status="revise"` and specific `issues` are returned
- [ ] Test Critic with a strong draft — confirm `status="approved"` and empty `issues`
- [ ] Test critic escalation rule — confirm Opus is used only when confidence/contradiction thresholds are met
- [ ] Test full reflection loop end-to-end — confirm iteration ceiling at 3 is respected
- [ ] Verify `Territory_Insight__c` record contains five narrative text fields plus `Evidence_Map__c`, `Data_Bundle_Hash__c`, and `Run_Metadata__c`
- [ ] Confirm `Iteration_Count__c` and `Approval_Status__c` are set correctly for both the approved and max-iterations-reached outcomes
- [ ] Test idempotency by replaying the same `uniqueRunKey` — confirm existing record is upserted, not duplicated

---

## Deferred (Out of Scope for This Iteration)

- Live data integration for market share and sales performance (mock data used)
- External news feed API integration (mock news records used)
- Alerting or notification to territory manager on record creation
- Historical trend comparison beyond prior-period delta
- Critic scoring rubric persistence (critique reasoning is ephemeral per run)
