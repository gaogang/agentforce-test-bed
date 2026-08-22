# C1 — Prompt Chaining: Pre-Call Recommendation Agent

## Overview

| Property | Value |
|---|---|
| Agent Name | `C1_prompt_chaining_pre_call_recomm` |
| Pattern | Prompt Chaining |
| Domain | Pharma Sales — Pre-Call Preparation |
| Optimisation Applied | Option A — Account Confirmation Gate |

The agent assists sales representatives in preparing for customer visits by resolving an account from natural-language input, confirming the match with the rep, retrieving the account's prescriber behaviour data, and generating targeted talkpoints.

---

## Design Pattern: Prompt Chaining

Each action in this agent produces an output that becomes the explicit input to the next action. The chain does not proceed to a subsequent step until the prior step's output is confirmed or available.

```
User Input
    │
    ▼
[Action 1] Identify Account Id
    │  Output: accountId, accountName, specialty
    ▼
Confirmation Gate  ◄─── User confirms or corrects
    │  Confirmed
    ▼
[Action 2] Get Prescriber Behaviour
    │  Input:  accountId
    │  Output: prescriberBehaviourSummary
    ▼
[Action 3] Recommend Talkpoint
    │  Input:  prescriberBehaviourSummary
    │  Output: talkpoints[ ]
    ▼
Formatted Response to Rep
```

---

## Agent Structure

### Custom Subagent: `Precall Recommendation`

| Property | Value |
|---|---|
| Subagent Name | Precall Recommendation |
| Purpose | End-to-end pre-call preparation for a named account |
| Triggers | Rep asks for call prep, talkpoints, or account briefing |

**Topic Instructions (to be configured in Agentforce):**

```
You are a pre-call recommendation assistant for pharmaceutical sales reps.

When the rep asks for call prep or talkpoints for a customer:
1. Call the "Identify Account Id" action with the name or details provided by the rep.
2. Present the matched account to the rep and ask for confirmation before proceeding.
3. Only after the rep confirms, call the "Get Prescriber Behaviour" action using the
   accountId returned in step 1.
4. Pass the prescriberBehaviourSummary from step 3 to the "Recommend Talkpoint" action.
5. Present the returned talkpoints to the rep in a clear, prioritised list.

Do not proceed to the next action without the output of the previous action.
Do not infer or fabricate accountId, behaviour data, or talkpoints.
```

---

## Actions

### Action 1 — Identify Account Id

| Property | Value |
|---|---|
| Action Name | Identify Account Id |
| Type | Flow / Apex |
| Purpose | Resolve a Salesforce Account from rep-provided natural-language input |

**Input Variables:**

| Variable | Type | Description |
|---|---|---|
| `firstName` | String | Extracted from rep's message |
| `lastName` | String | Extracted from rep's message |
| `specialty` | String | Optional — extracted if mentioned |

**Output Variables:**

| Variable | Type | Description |
|---|---|---|
| `accountId` | String | Salesforce Account record Id |
| `accountName` | String | Full name of the matched account |
| `specialty` | String | Account's medical specialty |

**Logic:**
1. Extract name tokens from the user's utterance.
2. SOQL search against the Account object (match on `FirstName`, `LastName`, and optionally `Specialty__c`).
3. Return the first matched record's Id, full name, and specialty.
4. If no match is found, return a descriptive error message in `accountName` (error handling deferred to a later iteration).

**Confirmation Gate (subagent instruction, not a separate action):**

After Action 1 returns, the subagent presents the result to the rep before calling Action 2:

> *"I found **Dr. Sarah Chen, Cardiology**. Shall I pull up her prescriber profile and generate talkpoints?"*

The rep must confirm (yes / proceed / correct me) before Action 2 is invoked.

---

### Action 2 — Get Prescriber Behaviour

| Property | Value |
|---|---|
| Action Name | Get Prescriber Behaviour |
| Type | Flow / Apex |
| Purpose | Retrieve prescriber behaviour data for the confirmed account |

**Input Variables:**

| Variable | Type | Description |
|---|---|---|
| `accountId` | String | Account Id from Action 1 output — **must be explicitly passed** |

**Output Variables:**

| Variable | Type | Description |
|---|---|---|
| `prescriberBehaviourSummary` | String / JSON | Structured summary of prescribing patterns and engagement history |

**Logic (mock implementation):**
Returns a mock prescriber behaviour payload keyed on `accountId`. The mock dataset covers:
- Product prescription frequency (high / medium / low)
- Last rep interaction date and outcome
- Preferred engagement channel (in-person / digital)
- Current competitor product usage
- Key concerns raised in prior visits

**Mock Data Example:**
```json
{
  "accountId": "0015g00000XxYzZ",
  "accountName": "Dr. Sarah Chen",
  "specialty": "Cardiology",
  "prescriptionFrequency": "high",
  "lastInteractionDate": "2026-05-14",
  "lastInteractionOutcome": "Interested in new clinical data",
  "preferredChannel": "in-person",
  "competitorProducts": ["BrandX", "BrandY"],
  "keyOpenConcerns": ["Long-term side effect profile", "Patient affordability"]
}
```

---

### Action 3 — Recommend Talkpoint

| Property | Value |
|---|---|
| Action Name | Recommend Talkpoint |
| Type | Prompt Template / Flow |
| Purpose | Generate prioritised talkpoints based on prescriber behaviour |

**Input Variables:**

| Variable | Type | Description |
|---|---|---|
| `prescriberBehaviourSummary` | String / JSON | Output from Action 2 — **must be explicitly passed** |

**Output Variables:**

| Variable | Type | Description |
|---|---|---|
| `talkpoints` | List | Structured list of recommended talkpoints |

**Output Schema (per talkpoint):**

| Field | Type | Description |
|---|---|---|
| `priority` | Integer | 1 = highest priority |
| `topic` | String | Short talkpoint label |
| `rationale` | String | Why this talkpoint is relevant to this prescriber |
| `suggestedOpener` | String | Suggested opening line for the rep |

**Logic:**
Using the prescriber behaviour summary, generate talkpoints that:
- Address open concerns from prior visits
- Leverage the prescriber's prescription frequency trend
- Counter identified competitor product usage with relevant differentiators
- Are ordered by estimated impact / relevance

**Example Output:**
```json
[
  {
    "priority": 1,
    "topic": "New Clinical Safety Data",
    "rationale": "Dr. Chen raised long-term side effect concerns in the last visit.",
    "suggestedOpener": "We have new Phase IV data I'd love to walk you through — it directly addresses the tolerability question you raised last time."
  },
  {
    "priority": 2,
    "topic": "Patient Affordability Programme",
    "rationale": "Affordability was flagged as a barrier; our co-pay programme removes this objection.",
    "suggestedOpener": "We've expanded our patient support programme — most of your patients on BrandX would qualify for zero co-pay."
  },
  {
    "priority": 3,
    "topic": "Head-to-Head vs BrandX",
    "rationale": "Dr. Chen currently prescribes BrandX; recent trial data shows superiority in her patient segment.",
    "suggestedOpener": "Have you had a chance to see the ACCEL-3 trial results? The outcomes data in cardiology patients is compelling."
  }
]
```

---

## Data Flow Summary

```
Rep: "Get me talkpoints for Dr. Sarah Chen"
       │
       ▼
Action 1: Identify Account Id
  Input : firstName="Sarah", lastName="Chen"
  Output: accountId="0015g00000XxYzZ", accountName="Dr. Sarah Chen", specialty="Cardiology"
       │
       ▼
Confirmation Gate (subagent presents match, waits for rep confirmation)
  Prompt: "Found Dr. Sarah Chen, Cardiology. Shall I continue?"
  Rep:    "Yes"
       │
       ▼
Action 2: Get Prescriber Behaviour
  Input : accountId="0015g00000XxYzZ"
  Output: prescriberBehaviourSummary={...mock data...}
       │
       ▼
Action 3: Recommend Talkpoint
  Input : prescriberBehaviourSummary={...}
  Output: talkpoints=[{priority:1,...}, {priority:2,...}, {priority:3,...}]
       │
       ▼
Rep sees: prioritised talkpoints with rationale and suggested openers
```

---

## Subagent Configuration Reference

| Setting | Value |
|---|---|
| Subagent Label | Precall Recommendation |
| Actions | Identify Account Id, Get Prescriber Behaviour, Recommend Talkpoint |
| Escalation Subagent | Default Escalation |
| Off-Topic Subagent | Default Off Topic |
| Ambiguous Question Subagent | Default Ambiguous Question |
| Router Subagent | Default Router |

---

## Implementation Checklist

- [ ] Create Apex class or Flow for **Identify Account Id** action
- [ ] Wire `accountId` as explicit output variable on Action 1
- [ ] Configure confirmation gate wording in subagent topic instructions
- [ ] Create Apex class or Flow for **Get Prescriber Behaviour** with mock data
- [ ] Wire `accountId` as explicit input variable on Action 2
- [ ] Create Prompt Template or Flow for **Recommend Talkpoint**
- [ ] Wire `prescriberBehaviourSummary` as explicit input variable on Action 3
- [ ] Define `talkpoints` structured output schema on Action 3
- [ ] Register all 3 actions on the `Precall Recommendation` subagent
- [ ] Configure subagent topic instructions with explicit variable handoff wording
- [ ] Register subagent on agent `C1_prompt_chaining_pre_call_recomm`
- [ ] Test end-to-end with a known mock account

---

## Deferred (Out of Scope for This Iteration)

- No-match handling when Action 1 finds no account
- Multi-match disambiguation when Action 1 finds more than one account
- Live CRM data integration for Actions 2 and 3 (mock data used)
- Error propagation and user-facing error messages across the chain
- Personalisation tuning on talkpoint generation prompt
