# Candidate queue — backlog mode

Candidates the compiler's size gate (COMPILER.md step 5) could not fit wait
here; the next run applies them BEFORE new ones and deletes what it applied.
Same block format as `compiler/summarize.sh` output, plus the date the block
entered the queue. Never edited by hand; CI runs
`python3 compiler/queue_candidates.py --check`. A block waiting more than
7 days makes session start warn.

```
CANDIDATE: <card-feed|new-card|alias|locked-change|policy-candidate>
TARGET: <id>
BODY: <one paragraph>
SOURCE: <daily file name>
ADDED: <YYYY-MM-DD>
```

<!-- QUEUE:BEGIN -->
<!-- QUEUE:END -->
