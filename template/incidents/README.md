# incidents/

One file per incident, `incidents/<id>.md`, with an INDEX row (family
`Incidents`, status `open` | `watching` | `resolved`). Sections:

- **Symptom** — what was seen, with numbers and times.
- **Root cause** — or "open" while unknown; never a guess presented as fact.
- **Impact** — who and what was affected, for how long.
- **Fix** — what changed, where (commit/PR), how it was verified.
- **Trap** — what will catch the next person out.
