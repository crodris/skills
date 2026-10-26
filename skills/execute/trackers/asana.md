# Asana adapter

This adapter runs on the Asana MCP.
Confirm the connected server's tool names before the first call, and when a name assumed below is missing, list the server's tools and map each operation to the closest match.
Create-task and create-subtask are usually separate tools.

## Operation mapping

| Contract operation | Asana MCP behavior |
| --- | --- |
| `getIssue(ref)` | Fetch the task by the GID in its URL with a get-task-style tool. With no URL or GID, use a name search and confirm the single best match with the user. Save its GID, permalink URL, completed flag, and memberships (project and section), and reuse the saved GID later. |
| `listSubIssues(ref)` | List the parent GID's subtasks, returning each one's GID, title, and completed flag. |
| `listDestinations()` | Resolve the viewer's teams with a teams-for-user-style tool, list each team's projects, and return each project's GID with its name. Use a workspace-wide project listing only as a fallback. |
| `resolveDestination(hint?)` | Match the hint, or the profile's default destination when there is none, against a project's name or GID. Return its GID, or null when the match is ambiguous. |
| `createIssue(title, description, type, destination)` | Create the task in the destination project. Return its GID and permalink URL. |
| `createSubIssue(parentRef, title, description)` | Create the task with the parent's GID as its parent and no project, since it inherits the parent's. Return its GID and permalink URL. |
| `updateState(ref, phase)` | On the main task only, take the phase's entry in the profile's state mapping and apply the first that works: (a) move the task to the mapped section with a section-move or add-to-section tool; (b) set the mapped status custom field with a task-update tool; (c) post a comment such as "Phase: In Review - <PR url>". When the profile records the phase as `unmapped`, skip the chain. For `done`, always set the completed flag too. Never hardcode a section or status name. |
| `comment(ref, body)` | Post a story (comment) on the task's GID. |
| `listComments(ref)` | List the task's stories with a list-stories-style tool, keep only comment-type stories, and return each text, newest first. When no such tool exists, report the operation as unavailable, since a task fetch does not carry comments. |

Builds differ.
A server with no section-move tool, such as the deprecated V1 server, falls through to the phase comment, which is expected and not an error.
When a listing call stalls instead of failing, stop waiting, tell the user which call stalled, and use the per-team path.
When an argument fails validation, retry with the other spelling, such as `user_gid` for `user_id`.

## Issue references

Asana has no issue key, so a run starts from a pasted task URL, or a name search confirmed with the user.
The ref in branch and file names is `asana-<last 6 digits of the task GID>`, and a branch adds a title slug, as in `feat/asana-482913-add-login`.
Record the full task URL in the checklist file, the tracker profile, and the PR body, so a resumed session can find the task.

## Subtask limitation

Subtasks do not appear in board sections, so the section and status-field mapping applies to the main task only.
A subtask's `inProgress` is a no-op, or at most a comment, and its `done` sets its completed flag.

## Done on merge

At review open, move the main task to `inReview` and post a comment saying what closes the task, as the Completion comment section of `merge-closer.md` says.
On the sweep's merged path, apply the mapped `done` state and set the completed flag.
On profile load, when the profile has no `merge-closer:` line or records `merge-closer: installed`, read `merge-closer.md` in this folder and follow it for Asana.

## Setup instructions

The preflight call is the workspace-list or current-user tool, and only an error-free response verifies the MCP.

When it does not verify, tell the user how to connect the V2 server, `https://mcp.asana.com/v2/mcp`, since the V1 server (`https://mcp.asana.com/sse`) shuts down on 2026-11-05.
V2 needs an app registered at `app.asana.com/0/my-apps`, which gives a client id and a client secret.

On Claude Code, register the redirect URL `http://localhost:8080/callback` in the app, then run:

```bash
claude mcp add --transport http --client-id YOUR_CLIENT_ID --client-secret --callback-port 8080 asana https://mcp.asana.com/v2/mcp
```

On Kiro, register the redirect URL `http://localhost:3334/oauth/callback` in the app, then add this entry to `~/.kiro/settings/mcp.json` (user level) or `.kiro/settings/mcp.json` (workspace level).
It runs the `mcp-remote` proxy, which is community software, not an official Asana or Anthropic package.

```json
{
  "mcpServers": {
    "asana": {
      "command": "npx",
      "args": [
        "-y",
        "mcp-remote@latest",
        "https://mcp.asana.com/v2/mcp",
        "3334",
        "--static-oauth-client-info",
        "{\"client_id\":\"YOUR_CLIENT_ID\",\"client_secret\":\"YOUR_CLIENT_SECRET\"}"
      ]
    }
  }
}
```

Either way, tell them to check an existing entry for a `disabled` flag first, since a disabled server looks the same as a missing one.
