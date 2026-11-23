# INDEX

Routing table: the brain-routing skill reads only this file first. One row per
card; `projects/<id>.md` is opened only after a match is clear.

This table is a **projection** of the cards' own fields — the compiler
regenerates it; do not edit rows by hand, edit the card.

| id | family | status | aliases |
|---|---|---|---|
| example-service | Services | active | the phrases your team uses for it, comma separated |

## Incidents

Rows from `incidents/<id>.md`. Status is `open`, `watching` or `resolved`;
open and watching ones are shown at every session start.

| example-outage-2026-01 | Incidents | resolved | one line: symptom, root cause, state |
