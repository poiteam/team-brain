# Content contracts

Contract version: 1

The kit's code reads some formats that live in **your** files — files `update`
never touches. This page lists them. `brain.conf` records which contract version
your content follows (`CONTRACT_VERSION`); `bash install.sh doctor` compares it
with the kit's (`kit/CONTRACT`).

## Daily — `daily/<YYYY-MM-DD>-<user>-<session8>.md`

Front matter `author`, `date`, `session`, `related: [<INDEX ids>]`, then the
sections `## Done`, `## Decisions`, `## Open`, `## Traps`, `## Card candidate`
(drop the ones you do not need). Read by: session start (recent dailies, the
`related` ids), the summarizer (`compiler/summarize.sh`).

## Routing index — `projects/INDEX.md`

Rows `| id | family | status | aliases |`. Incidents use family `Incidents` and
status `open`, `watching` or `resolved`; open and watching ones are shown at every
session start. The table is a projection of the cards: the compiler regenerates
it. Read by: session start, the `brain-routing` skill, the compiler.

## Project card — `projects/<id>.md`

A title and a field table (`id`, `family`, `status`, `aliases`), then the
sections `## Owns`, `## Depends on`, `## Known traps`, `## Open debts`,
`## Archive`. The compiler only appends under `Known traps` and `Archive`; the
merge gate lets exactly those appends merge without a human.

## Locked decisions — `locked/decisions.md`

A table `| id | decision | why |` and/or sections `## D<n> — <title>`. The
summarizer lists them by `ID: title`, so a proposal to change one becomes a
`locked-change` for a human. The compiler never edits `locked/`.

## Policy candidates and the queue

`policies/candidates/<id>.md` (one file per candidate) and its generated table
`policies/CANDIDATES.md`; `queue/candidates.md` holds candidates a run could not
fit. `brain-checks` fails when the table is stale or the queue is malformed.

## When a contract changes

A change to any format above is a **major** kit release. Its CHANGELOG entry
lists the manual steps to convert your content; after doing them, set
`CONTRACT_VERSION` in `brain.conf` to the new number. `update` does not migrate
content for you.
