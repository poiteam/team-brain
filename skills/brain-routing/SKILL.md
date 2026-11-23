---
name: brain-routing
description: Routes a request about the team's systems to the closed set of cards in the brain's projects/INDEX.md — returns one card, a cluster of related cards, or a clarifying question. Use before answering, drafting or changing anything about a service, repo, incident, ticket or config ("what is X", "why does Y fail", "open a ticket for Z"), so the answer rests on the right card instead of a guess.
---

# brain-routing

Classify the request against a **closed set**: the cards listed in
`projects/INDEX.md`. The answer set is finite and known in advance — this is
classification, not open search.

## Input discipline — the INDEX first, cards later

Read `projects/INDEX.md` first; often it is the only file you need. A row is:

```
| id | family | status | aliases |
```

`aliases` holds the team's own phrases for that card — the strongest signal.
Open a card (`projects/<id>.md`) only when (a) a single match is clear and you
need its sections (`Owns`, `Depends on`, `Known traps`), or (b) you suspect a
cluster and must check `Depends on`. Business logic, stacks and file paths live
in the card, not in the INDEX: do not claim them before opening it.

## Step 1 — match against the INDEX only

Use only what the row itself tells you:
- exact or near overlap with `aliases` (strongest);
- the plain meaning of the `id`'s parts (`-api`, `-worker`, `eod` = end of day);
- `family` / `status` when the request names them ("the service we are retiring");
- general software vocabulary (gateway, worker, panel, SDK).

## Step 2 — result class

Decided by **signal strength**: how many cards stand out, by how much.

| Class | Definition | Next |
|---|---|---|
| **Clean single** | Clear multi-term overlap with one card, none with others. | Open the card, continue; check `Depends on` (step 5). |
| **Weak single** | One card is clearly stronger (several signals, or one distinctive one) but a rival cannot be ruled out; the sentence often hedges ("I think", "seems like"). | Step 4 — there is a defensible candidate. |
| **Multiple** | Two or more cards match with **equal** strength. | Step 4 — there is no single defensible candidate. |
| **Zero** | No card matches. | Step 4 — there is no candidate at all. |

Weak single vs multiple is the critical line. Ask: *is there one defensible
candidate, or are they equal?* If a word like "api" appears in five ids and
nothing else in the request separates them, picking one is a coin toss, not an
assumption — that is **multiple**.

## Step 3 — read or write?

- **Write**, if a verb targets a concrete object to create or change: open /
  update / close / transition a ticket; add / remove / change / deploy / commit /
  merge code, config or a migration. Look at the verb's **object**: "the service
  we are shutting down" describes a state (read); "close the ticket" mutates (write).
- **Read**, if there is no write signal and the request asks or describes: a
  question, a symptom ("keeps disconnecting", "never ran"), or a discussion of
  scope and priority. A discussion authorizes no mutation by itself.
- **Unclear → assume write.** An extra question costs one sentence; a mutation
  on a wrong assumption costs a cleanup.

## Step 4 — the asymmetric gate (the rule that matters most)

Two axes: **the cost of being wrong** (read: a correcting sentence; write:
tickets or changes someone must clean up) and **whether one defensible
candidate exists**. "State the assumption and continue" presupposes that there
is an assumption to state — with equal candidates or none, there is not.

| Class | Read | Write |
|---|---|---|
| **Clean single** | Continue. | Continue. |
| **Weak single** | Say it and continue: *"Assuming `billing-api` —"*. | **Stop and ask.** No id, no draft, no ticket until confirmed. |
| **Multiple** | List the candidates and ask in one sentence (you may say which looks likeliest, without committing). | **Stop and ask**, same candidates, no suggestion. |
| **Zero** | Say it matches none of the INDEX's cards and ask: new topic, or part of a known card? | **Stop and ask.** Never invent a card. |

In read mode the question is a cheap clarification and the flow resumes with
the answer; in write mode "stop" blocks the write entirely — no drafts, no
preparation.

## Step 5 — clusters

A request can resolve to a **cluster**. After opening a single card: every
entry of its `Depends on` that is also an INDEX `id` joins the cluster
(infrastructure and vendor names do not). Early hints in the INDEX itself: a
cross-cutting family (an initiative spanning many services) and collective
wording in the aliases ("rotate all keys"). A cluster is not a multiple match:
there is still exactly one resolved card — the cluster is the structure behind
it, handed on whole.

## Step 6 — learning note (feeds the compiler)

If this conversation **settled** a phrase ↔ id mapping (the person answered
your question, or corrected your assumption) and the phrase is **not** already
in the card's `aliases`, put an alias candidate in the "Card candidate" section
of this session's daily — the nightly compiler turns it into an alias:

```
CANDIDATE: alias
TARGET: <card id>
BODY: "<the phrase as the person said it>" refers to <card id> (confirmed in this session)
```

Only genuinely new mappings: re-reporting a known alias is noise.

## Decision flow

```
request → read projects/INDEX.md only → match, weigh signal strength
  clean single → open card → Depends on has INDEX ids? → cluster : single
  weak single  → read: state the assumption, continue | write: STOP, ask
  multiple     → read: list candidates, ask cheaply   | write: STOP, ask
  zero         → read: "matches no card", ask         | write: STOP, ask
  mapping settled and new? → alias candidate in the daily
```

## Hand-off

Downstream skills (ticket breakdown, code changes) receive only a **resolved**
result: a clean single card, or a single card with its cluster. A weak, multiple
or zero result is never handed on unresolved. A read-mode assumption or
candidate list informs; it never authorizes a mutation until the person names
the id.

## What this skill does not do

- Write tickets, code or drafts — it ends with a classification and, if needed,
  one question.
- Read card content before the match is clear.
- Continue a write on an assumption.
