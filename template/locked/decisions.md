# Locked decisions

Architecture and contract decisions the brain rests on. Only humans change this
file; the compiler never does — when a daily proposes changing one of these, the
compiler raises a `locked-change` for a human instead of applying anything.

Keep this list SHORT. Every entry here is something a proposal must not quietly
erode; ordinary design decisions belong in the cards. The summarizer lists each
row below by `ID: title`, so a `locked-change` is raised only for these.

| id | decision | why |
|---|---|---|
| D1 | **Dailies go straight to the default branch; cards change only via compiler PRs** | append-only logs never conflict; permanent knowledge is reviewed |
| D2 | **The compiler never touches locked/** | decisions must not be eroded by suggestion flow |

Longer decisions can also be written as sections: `## D3 — <title>` followed by
the text; the summarizer lists those headings too.
