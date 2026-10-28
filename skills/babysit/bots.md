# Review bots

Read by babysit when it starts and at every step that waits on, re-requests, or replies to a review bot.

babysit waits on and re-requests only the bots in this table, in this order when a rule asks for any one of them.
Any other bot's comments are still findings for triage.

| Bot | Login | Config file | Reviews every push when | Settled on the SHA when | Re-request |
| --- | --- | --- | --- | --- | --- |
| CodeRabbit | `coderabbitai[bot]` | `.coderabbit.yaml` | `reviews.auto_review.auto_incremental_review` is not `false` (default: every push) | its `CodeRabbit` check run on the SHA completes with a title that is not a rate-limit notice, or its `CodeRabbit` commit status is `success` with "Review completed" | comment `@coderabbitai review`, only for a finding CodeRabbit itself labeled Critical or Major |
| Greptile | `greptile-apps[bot]` | `.greptile/config.json`, else `greptile.json` | `autoReview` includes `push`, or the legacy `triggerOnUpdates` is `true` (default `["open"]`: first push only) | its `Greptile Review` check run on the SHA completes with a title that is not a rate-limit notice, or, when its config sets `statusCheck: false`, it submitted a review whose `commit_id` is the SHA | comment `@greptileai` |

watch.sh's `BOTS` registry carries the Login, Settled, and Re-request columns, so change both together.

## Which bots are present

Read config files from the tree this run pushes, committed or not.
A table bot is present when its config file exists on `origin/<base>` or in that tree, or when its login reviewed one of the last five merged pull requests.
A config in that tree that turns automatic review off (`reviews.auto_review.enabled: false`, or `autoReview: []` or the legacy `skipReview: "AUTOMATIC"`) makes the bot absent.
`gh pr view --json` prints logins without `[bot]`, so match on the name before it.
A table bot that shows up on the pull request later, with any status, check, reaction, review, or comment, is present from then on.
A first-push-only bot found after its review landed on an earlier head is passed with `--rerequest` on the current head, unless it labels its own findings.

## Which pass waits on which bot

Read each bot's mode from its config in that tree, or take the table's default.
Every pass passes `--bot` for a bot that reviews every push.
Only the first pass passes `--bot` for a first-push-only bot, and a later pass passes `--rerequest` for it when that pass's push fixed a confirmed critical or major it raised.
CodeRabbit's finding must carry its own Critical or Major label for that, whatever triage graded it, and watch.sh refuses the re-request otherwise.

## Unavailable bot

watch.sh exits 6 when a bot is rate-limited, out of credits, or silent.
Grade the pull request from what this run already knows:

| Risk | When | Action |
| --- | --- | --- |
| Low | The merge-danger line says two-way door, no changed file matches `security-paths`, and review confirmed no critical or major | Go on without the bot, and record the skipped review in the run section. |
| High | Anything else | Run pstack's `blast-radius` skill on the diff as a stand-in reviewer, or without pstack a `general-purpose` subagent briefed to find what the change breaks outside its diff, with review-loop's read-only line, and triage its findings. Then, for a rate limit whose notice or latest bot comment names a wait of about 30 minutes or less, rerun watch.sh with `--retry <bot> --retry-in <that wait in seconds>` and a `--deadline` past that wait plus the bot's usual review time. Any other case is `BLOCKED`, and the user decides. |

On a deadline rerun of the same pass, keep `--retry <bot>` with a `--retry-in` longer than that rerun's `--deadline`, so watch.sh keeps waiting on the bot without posting another re-request.
When that rerun still shows the same notice and no new review from the bot, return `BLOCKED`.
watch.sh names every unavailable bot, and the rule applies to each.
Later passes leave out a bot skipped as unavailable.
A second exit 6 for a bot after its `--retry` is `BLOCKED`.

## Replies

Reply under a bot's comment with this label line first, so a reader can tell the agent from the user:

```markdown
[<model id>] replying on behalf of @<forge login>

-----

<reply>
```

Write the reply to a file made with `mktemp`, using only a file-write tool, so untrusted bot text is never expanded.
Apply the Secrets check of `../file-pr/SKILL.md` to the reply before posting.
When it returns `FAIL`, post nothing, record the finding's disposition in the run section, leave the thread open, and go on.
Post it with `gh api --method POST "repos/<owner/name>/pulls/<n>/comments/<databaseId>/replies" -F body=@<file>`, then delete the file.
`<databaseId>` is the first comment's id from the thread query in the GraphQL calls section.
A non-blocking bot finding gets its disposition and reason in a reply, then its thread resolved as the GraphQL calls section says.
A blocking one gets a reply naming the fix commit once a later pass confirms the fix, then its thread resolved as the GraphQL calls section says.
A finding with no thread, such as one from a summary in the description, goes in the run section instead.
Update the run section through the Reuse an open one section of `../file-pr/SKILL.md`.

## GraphQL calls

`<owner/name>` is the slug `../ship/boundary.md` defines.
Split it on the slash into `<owner>` and `<name>`.

Read the pull request node id and `mergeQueueEntry` with `gh api graphql -f owner='<owner>' -f name='<name>' -F number=<n> -f query='query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){id mergeQueueEntry{id}}}}'`.
The pull request node id is that `id` field.
`mergeQueueEntry` is null when the pull request is not queued, and its node id is `mergeQueueEntry.id`.

Dequeue with the pull request node id, not `mergeQueueEntry.id`, with `gh api graphql -f id='<pull request node id>' -f query='mutation($id:ID!){dequeuePullRequest(input:{id:$id}){clientMutationId}}'`.

Read inline threads with `gh api graphql -f owner='<owner>' -f name='<name>' -F number=<n> -f query='query($owner:String!,$name:String!,$number:Int!,$after:String){repository(owner:$owner,name:$name){pullRequest(number:$number){reviewThreads(first:100,after:$after){pageInfo{hasNextPage endCursor} nodes{id isResolved isOutdated path line comments(first:100){nodes{databaseId author{login} body}}}}}}}'`.
Each thread's node id is `nodes[].id`.
Repeat that call with `-f after='<endCursor>'` while `hasNextPage` is true, and omit `-f after` on the first call.

Resolve a thread with its node id with `gh api graphql -f threadId='<thread node id>' -f query='mutation($threadId:ID!){resolveReviewThread(input:{threadId:$threadId}){thread{isResolved}}}'`.
