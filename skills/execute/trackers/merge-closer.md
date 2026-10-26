# Merge closer

A merge closer is whatever closes an issue when its review merges, recorded in the tracker profile as `merge-closer`.
The tracker adapters send a run here on profile load when the profile has no `merge-closer:` line or records `merge-closer: installed`.

## The question

Both arrangements below are GitHub-specific.
When the resolved forge is not GitHub, skip the question and record `merge-closer: none (forge is not GitHub)`.
When it declares no `ciHooks`, skip the question and record `merge-closer: none (forge has no hooks)`.
Otherwise ask once, record the answer right away, and never ask again in this repository.
With any value the done-on-merge sweep in `../trackers.md` still runs as the backstop.

For Linear, ask whether the workspace has Linear's GitHub integration connected, and take the user's answer as authoritative.
A fresh workspace has none, so never assume it.
An empty `attachments` field on an issue whose pull request already merged suggests no integration, and a populated one proves nothing.
When it is connected, record `native`.
It only reacts to merges into the default branch, so the sweep closes an issue whose review targeted another `base-branch`.
When it is not connected, offer the Linear template below.

For Asana, first mention Asana's free GitHub App, which links a pull request to a task when the body holds the task URL or the branch holds the task id.
Paired with an Asana rule "when a GitHub pull request is merged, mark the task complete", it closes the task with no workflow file and no repository secret.
When the team relies on it, record `native`.
Otherwise offer the Asana template below.

On a yes to a template, write `.github/workflows/fathom-close.yml` from it, record `merge-closer: installed`, and commit both on the issue branch, as Committing the profile in `../first-run.md` says.
On a no, record `merge-closer: declined`, and the sweep closes the issue.
The Linear template needs a `LINEAR_API_KEY` repository secret, a personal API key from Linear's settings.
Substitute the `done` state's id, read from the team's workflow states, for `REPLACE_WITH_DONE_STATE_ID` before writing the file.
Say when offering it that it has never run end to end and assumes `issueUpdate` accepts a key such as `TES-5` as its `id`, and suggest checking the first merge.
When it does not accept the key, change the template to resolve the key to a UUID with a query first.
The Asana template needs an `ASANA_TOKEN` repository secret, a personal token the user creates in Asana's developer console.

## Completion comment

The completion comment and step 12's report say what closes the issue, taking the first case that matches.
1. The resolved forge declares `reviewLookup: none`: closing the issue is a manual step, since the sweep cannot see the review.
2. The plan document carries `- Merge-closer: suppressed`, as a stack's does: the done-on-merge sweep closes the issue once every bundle's review merges, as `../trackers.md` says.
3. The profile records `native`: the tracker's GitHub integration closes it when the review merges into the default branch, and the sweep closes it otherwise.
4. The profile records `installed`: the `fathom-close.yml` workflow closes it when the review merges.
5. Any other value: the done-on-merge sweep closes it on the next run of a Fathom skill in this repository.
Never say the tracker closes it on its own outside case 3.

## Template updates

An installed workflow is a copy taken at install time.
When the profile records `merge-closer: installed`, compare the repository's `.github/workflows/fathom-close.yml` with the current template's file-discovery block, ignoring comment lines.
When they differ, offer once to rewrite the file, saying what differs and that only the workflow file changes.
On a yes, rewrite it and keep `merge-closer: installed`.
On a no, record `merge-closer: installed (template-rewrite declined)`, which means `installed` everywhere else and is never offered again.

## Boundary

The `curl` calls in these templates run only in the Action on CI, with its own repository secret.
The agent never runs them, never calls a tracker API directly, and never reads a token from disk; the connected tracker MCP is its only channel.

## The discovery block

The block between `fathom:discovery-block start` and `fathom:discovery-block end` is identical in both templates, so apply a change to both copies.
These differences are expected: the leading comment says "an issue ... the wrong one" in Linear's copy and "a task ... the wrong issue" in Asana's, and the selected file is `FILE` in Linear's copy and `TASK_FILE` in Asana's.

## Linear template

```yaml
name: fathom-close

on:
  pull_request:
    types: [closed]

jobs:
  close-linear-issue:
    if: github.event.pull_request.merged == true
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0

      - name: Close the Linear issue for the merged branch
        env:
          LINEAR_API_KEY: ${{ secrets.LINEAR_API_KEY }}
          DONE_STATE_ID: REPLACE_WITH_DONE_STATE_ID
          # Pass the branch through env, never into the script text: branch
          # names may contain shell metacharacters, which would run as code.
          BRANCH: ${{ github.event.pull_request.head.ref }}
        run: |
          if [ -z "$LINEAR_API_KEY" ]; then
            echo "No LINEAR_API_KEY secret set, skipping."
            exit 0
          fi

          if [ "$DONE_STATE_ID" = "REPLACE_WITH_DONE_STATE_ID" ]; then
            echo "DONE_STATE_ID was never substituted; refusing to run with a placeholder."
            exit 1
          fi

          # fathom:discovery-block start
          # This block matches the other template in Fathom's merge-closer.md.
          # A branch must map to exactly one record; closing an issue picked
          # arbitrarily from several matches could complete the wrong one.
          # Only a labeled Branch line is trusted, and it must equal the branch
          # exactly. An unanchored search also hits the branch name quoted in
          # another issue's prose, and a bare substring makes feat/tes-5 match
          # feat/tes-50; either one yields a false multi-match that refuses to
          # close anything, or picks the wrong record.
          BRANCH_RE=$(printf '%s' "$BRANCH" | sed 's/[][\^$.*+?(){}|]/\\&/g')
          LABELED='^[[:space:]]*[-*]?[[:space:]]*(\*\*)?[Bb]ranch(\*\*)?[[:space:]]*[:-][[:space:]]*`?'
          MATCHES=$(grep -rlE "${LABELED}${BRANCH_RE}\`?[[:space:]]*$" .fathom/ 2>/dev/null | sort || true)
          MATCH_COUNT=$(printf '%s' "$MATCHES" | grep -c . || true)

          # Records written before the labeled Branch line was required still
          # resolve through a token-bounded search of the whole record, so upgrading does
          # not silently stop closing issues that were already in flight.
          if [ "$MATCH_COUNT" -eq 0 ]; then
            MATCHES=$(grep -rlE "(^|[^[:alnum:]/_.-])${BRANCH_RE}([^[:alnum:]/_.-]|$)" .fathom/ 2>/dev/null | sort || true)
            MATCH_COUNT=$(printf '%s' "$MATCHES" | grep -c . || true)
            if [ "$MATCH_COUNT" -gt 0 ]; then
              echo "No labeled Branch line matched $BRANCH; using the legacy unanchored search over:"
              echo "$MATCHES"
              # The legacy search matches the branch name as a whole token, so
              # feat/tes-5 no longer matches a record for feat/tes-50.
            fi
          fi

          if [ "$MATCH_COUNT" -eq 0 ]; then
            echo "No file under .fathom/ references branch $BRANCH, skipping."
            exit 0
          fi

          # One issue legitimately has two records: the plan document under
          # plans/ and, in checklist mode, the task file under tasks/. Both are
          # named <ISSUE-REF>.md, so collapse on the file name before judging
          # ambiguity. Counting files instead would refuse every checklist-mode
          # merge, since both records carry the same labeled Branch line.
          STEMS=$(printf '%s\n' "$MATCHES" | sed 's#.*/##' | sort -u)
          STEM_COUNT=$(printf '%s' "$STEMS" | grep -c . || true)
          if [ "$STEM_COUNT" -gt 1 ]; then
            echo "Files under .fathom/ for branch $BRANCH name different issues; refusing to guess:"
            echo "$MATCHES"
            exit 1
          fi

          # A stacked issue records one branch per bundle, so any one bundle's
          # merge reaches this Action while the rest of the work is still open.
          # Such an issue records a suppression marker and is closed by fathom's
          # own sweep once every bundle reports merged. Check every matching
          # record rather than the one selected below: in checklist mode the
          # marker lives in the plan document while the task file is preferred.
          # Read the list the same way everything above does, through
          # printf and a quoted read: an unquoted for loop word-splits and
          # glob-expands the path, so one record named with a space or a
          # bracket would silently fail the grep and close a stacked issue.
          SUPPRESSED=$(printf '%s\n' "$MATCHES" | while IFS= read -r RECORD; do
            [ -n "$RECORD" ] || continue
            if grep -qE '^[[:space:]]*[-*]?[[:space:]]*(\*\*)?[Mm]erge-closer(\*\*)?[[:space:]]*[:-][[:space:]]*(\*\*)?[Ss]uppressed' "$RECORD"; then
              printf '%s\n' "$RECORD"
              break
            fi
          done) || true
          if [ -n "$SUPPRESSED" ]; then
            echo "$SUPPRESSED records merge-closer: suppressed, so this issue is a stack that closes only once every bundle merges. Taking no action for $BRANCH."
            exit 0
          fi

          # Prefer the task file when both exist; it also carries the review id.
          # Anchor the prefix rather than matching /tasks/ anywhere: grep -r
          # descends into dot-directories, so a repo left holding a nested
          # .fathom/.workbench/tasks/ from a botched rename would otherwise sort
          # ahead of the live record and select the stale copy.
          # Every grep above that can legitimately match nothing ends in
          # || true. Actions' default shell is bash -e with pipefail OFF, but a
          # consumer who adds shell: bash or a defaults.run block gets pipefail,
          # and there a no-match grep would abort the job instead of taking the
          # skip path: a red check that closes nothing.
          FILE=$(printf '%s\n' "$MATCHES" | grep '^\.fathom/tasks/' | head -n 1 || true)
          [ -n "$FILE" ] || FILE=$(printf '%s\n' "$MATCHES" | grep '^\.fathom/plans/' | head -n 1 || true)
          [ -n "$FILE" ] || FILE=$(printf '%s\n' "$MATCHES" | head -n 1)
          # fathom:discovery-block end

          # Only a labeled line is trusted. Matching any uppercase-dash-digits
          # token anywhere would also match RFC-7231, ISO-8601, SHA-1 and the
          # like, which appear legitimately in a plan document.
          KEY=$(grep -iE '^[[:space:]]*[-*]?[[:space:]]*(\*\*)?(tracker|issue|ref)(\*\*)?[[:space:]]*[:-]' "$FILE" \
            | grep -oE '[A-Z][A-Z0-9]+-[0-9]+' | head -n 1 || true)

          if [ -z "$KEY" ]; then
            echo "No labeled Tracker, Issue, or Ref line carrying a Linear key in $FILE, skipping."
            exit 0
          fi

          RESPONSE=$(curl -sf https://api.linear.app/graphql \
            -H "Authorization: $LINEAR_API_KEY" \
            -H 'Content-Type: application/json' \
            -d "{\"query\":\"mutation { issueUpdate(id: \\\"$KEY\\\", input: { stateId: \\\"$DONE_STATE_ID\\\" }) { success } }\"}") \
            || { echo "Linear API call failed for $KEY"; exit 1; }

          # A GraphQL error arrives with HTTP 200, so -f alone is not enough;
          # parse the JSON instead of pattern-matching the raw text, which
          # would misread payloads that merely contain those substrings.
          if ! printf '%s' "$RESPONSE" | jq -e . >/dev/null 2>&1; then
            echo "Unexpected (non-JSON) Linear response for $KEY: $RESPONSE"
            exit 1
          fi
          if printf '%s' "$RESPONSE" | jq -e '(.errors // []) | length > 0' >/dev/null; then
            echo "Linear returned an error for $KEY: $RESPONSE"
            exit 1
          fi
          if [ "$(printf '%s' "$RESPONSE" | jq -r '.data.issueUpdate.success // false')" = "true" ]; then
            echo "Closed $KEY."
          else
            echo "Unexpected Linear response for $KEY: $RESPONSE"
            exit 1
          fi
```

## Asana template

```yaml
name: fathom-close

on:
  pull_request:
    types: [closed]

jobs:
  close-asana-task:
    if: github.event.pull_request.merged == true
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0

      - name: Close Asana task for merged branch
        env:
          ASANA_TOKEN: ${{ secrets.ASANA_TOKEN }}
          # Pass the branch through env, never into the script text: branch
          # names may contain shell metacharacters, which would run as code.
          BRANCH: ${{ github.event.pull_request.head.ref }}
        run: |
          if [ -z "$ASANA_TOKEN" ]; then
            echo "No ASANA_TOKEN secret set, skipping."
            exit 0
          fi

          # fathom:discovery-block start
          # This block matches the other template in Fathom's merge-closer.md.
          # A branch must map to exactly one record; closing a task picked
          # arbitrarily from several matches could complete the wrong issue.
          # Only a labeled Branch line is trusted, and it must equal the branch
          # exactly. An unanchored search also hits the branch name quoted in
          # another issue's prose, and a bare substring makes feat/tes-5 match
          # feat/tes-50; either one yields a false multi-match that refuses to
          # close anything, or picks the wrong record.
          BRANCH_RE=$(printf '%s' "$BRANCH" | sed 's/[][\^$.*+?(){}|]/\\&/g')
          LABELED='^[[:space:]]*[-*]?[[:space:]]*(\*\*)?[Bb]ranch(\*\*)?[[:space:]]*[:-][[:space:]]*`?'
          MATCHES=$(grep -rlE "${LABELED}${BRANCH_RE}\`?[[:space:]]*$" .fathom/ 2>/dev/null | sort || true)
          MATCH_COUNT=$(printf '%s' "$MATCHES" | grep -c . || true)

          # Records written before the labeled Branch line was required still
          # resolve through a token-bounded search of the whole record, so upgrading does
          # not silently stop closing issues that were already in flight.
          if [ "$MATCH_COUNT" -eq 0 ]; then
            MATCHES=$(grep -rlE "(^|[^[:alnum:]/_.-])${BRANCH_RE}([^[:alnum:]/_.-]|$)" .fathom/ 2>/dev/null | sort || true)
            MATCH_COUNT=$(printf '%s' "$MATCHES" | grep -c . || true)
            if [ "$MATCH_COUNT" -gt 0 ]; then
              echo "No labeled Branch line matched $BRANCH; using the legacy unanchored search over:"
              echo "$MATCHES"
              # The legacy search matches the branch name as a whole token, so
              # feat/tes-5 no longer matches a record for feat/tes-50.
            fi
          fi

          if [ "$MATCH_COUNT" -eq 0 ]; then
            echo "No file under .fathom/ references branch $BRANCH, skipping."
            exit 0
          fi

          # One issue legitimately has two records: the plan document under
          # plans/ and, in checklist mode, the task file under tasks/. Both are
          # named <ISSUE-REF>.md, so collapse on the file name before judging
          # ambiguity. Counting files instead would refuse every checklist-mode
          # merge, since both records carry the same labeled Branch line.
          STEMS=$(printf '%s\n' "$MATCHES" | sed 's#.*/##' | sort -u)
          STEM_COUNT=$(printf '%s' "$STEMS" | grep -c . || true)
          if [ "$STEM_COUNT" -gt 1 ]; then
            echo "Files under .fathom/ for branch $BRANCH name different issues; refusing to guess:"
            echo "$MATCHES"
            exit 1
          fi

          # A stacked issue records one branch per bundle, so any one bundle's
          # merge reaches this Action while the rest of the work is still open.
          # Such an issue records a suppression marker and is closed by fathom's
          # own sweep once every bundle reports merged. Check every matching
          # record rather than the one selected below: in checklist mode the
          # marker lives in the plan document while the task file is preferred.
          # Read the list the same way everything above does, through
          # printf and a quoted read: an unquoted for loop word-splits and
          # glob-expands the path, so one record named with a space or a
          # bracket would silently fail the grep and close a stacked issue.
          SUPPRESSED=$(printf '%s\n' "$MATCHES" | while IFS= read -r RECORD; do
            [ -n "$RECORD" ] || continue
            if grep -qE '^[[:space:]]*[-*]?[[:space:]]*(\*\*)?[Mm]erge-closer(\*\*)?[[:space:]]*[:-][[:space:]]*(\*\*)?[Ss]uppressed' "$RECORD"; then
              printf '%s\n' "$RECORD"
              break
            fi
          done) || true
          if [ -n "$SUPPRESSED" ]; then
            echo "$SUPPRESSED records merge-closer: suppressed, so this issue is a stack that closes only once every bundle merges. Taking no action for $BRANCH."
            exit 0
          fi

          # Prefer the task file when both exist; it also carries the review id.
          # Anchor the prefix rather than matching /tasks/ anywhere: grep -r
          # descends into dot-directories, so a repo left holding a nested
          # .fathom/.workbench/tasks/ from a botched rename would otherwise sort
          # ahead of the live record and select the stale copy.
          # Every grep above that can legitimately match nothing ends in
          # || true. Actions' default shell is bash -e with pipefail OFF, but a
          # consumer who adds shell: bash or a defaults.run block gets pipefail,
          # and there a no-match grep would abort the job instead of taking the
          # skip path: a red check that closes nothing.
          TASK_FILE=$(printf '%s\n' "$MATCHES" | grep '^\.fathom/tasks/' | head -n 1 || true)
          [ -n "$TASK_FILE" ] || TASK_FILE=$(printf '%s\n' "$MATCHES" | grep '^\.fathom/plans/' | head -n 1 || true)
          [ -n "$TASK_FILE" ] || TASK_FILE=$(printf '%s\n' "$MATCHES" | head -n 1)
          # fathom:discovery-block end

          # Only a labeled line is trusted, so a URL sitting in prose cannot
          # make this close the wrong task. Matches "- Ref: <url>" and
          # "- **Issue** - <url>" style lines alike.
          TASK_URL=$(grep -iE '^[[:space:]]*[-*]?[[:space:]]*(\*\*)?(tracker|issue|ref)(\*\*)?[[:space:]]*[:-]' "$TASK_FILE" \
            | grep -oE 'https://app\.asana\.com/[^ )>]+' | head -n 1 || true)

          if [ -z "$TASK_URL" ]; then
            echo "No labeled Tracker, Issue, or Ref line carrying an Asana URL in $TASK_FILE, skipping."
            exit 0
          fi

          # Anchor on the task segment: copy-link and focus URLs end in /f or
          # ?focus=true, so matching trailing digits alone finds nothing.
          TASK_GID=$(printf '%s' "$TASK_URL" | sed -nE 's#.*/task/([0-9]+).*#\1#p')
          if [ -z "$TASK_GID" ]; then
            TASK_GID=$(printf '%s' "$TASK_URL" | sed -nE 's#.*/([0-9]+)/?(f/?)?(\?.*)?$#\1#p')
          fi

          if [ -z "$TASK_GID" ]; then
            echo "Could not extract a task GID from $TASK_URL, skipping."
            exit 0
          fi

          # -f so an auth or not-found error fails the job, instead of the job
          # going green while the task stays open.
          curl -sf -X PUT "https://app.asana.com/api/1.0/tasks/$TASK_GID" \
            -H "Authorization: Bearer $ASANA_TOKEN" \
            -H "Content-Type: application/json" \
            -d '{"data":{"completed":true}}' \
            || { echo "Asana API call failed for GID $TASK_GID"; exit 1; }
```

The Asana Action only sets the completed flag on merge, and section moves at other phases still go through `updateState`.
