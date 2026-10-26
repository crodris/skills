# Linear adapter

This adapter runs on the Linear MCP.
Confirm the connected server's tool names before the first call, and when a name assumed below is missing, list the server's tools and map each operation to the closest match.
Create and update are often one save-style tool that updates when given an id and creates when not.

## Operation mapping

| Contract operation | Linear MCP behavior |
| --- | --- |
| `getIssue(ref)` | Fetch the issue by its key, such as `ONC-5`, with a get-issue-style tool. Save its UUID, URL, team id, project id when it has one, labels, and workflow state, and reuse the saved UUID later. When the response carries comments, save their bodies in order for `listComments`. |
| `listSubIssues(ref)` | List issues filtered by the parent's UUID or key, returning each child's id, title, and state. |
| `listDestinations()` | List the viewer's teams with the current-user tool, never a workspace-wide team list, and list a team's projects when a destination narrower than the team is needed. |
| `resolveDestination(hint?)` | Match the hint, or the profile's default destination when there is none, against a team's key or name, and validate any named project under that team. Return the team UUID and any project id together as one destination value, or null when the match is ambiguous. |
| `createIssue(title, description, type, destination)` | Create the issue with the destination's team UUID, plus its project when one was resolved. Return the new key and URL. |
| `createSubIssue(parentRef, title, description)` | Create the issue with the parent's id as its parent, and pass the parent's team id and project id, from `getIssue` or from the destination when this run created the parent. A missing team fails with "team is required", and a missing project drops the child off the project's board. Return the new key and URL. |
| `updateState(ref, phase)` | Set the state the profile's state mapping names for the phase. When the profile records the phase as `unmapped`, change nothing. Never hardcode a state name. |
| `comment(ref, body)` | Create a comment on the issue's id. |
| `listComments(ref)` | List the issue's comments with a list-comments-style tool, or read them from the saved `getIssue` response on builds that have none, and return each body, newest first. When neither exists, report the operation as unavailable. |

## Notes

A Linear ref is a key such as `ONC-5`, and branch names use it in lowercase.

On a merged review the sweep applies the mapped `done` state unless the issue is already done.
The native arrangement, Linear's GitHub integration, closes an issue when a pull request whose body says `Closes ONC-5` merges into the default branch.
It never moves an issue to `inProgress` or `inReview`, so `updateState` still does.
On profile load, when the profile has no `merge-closer:` line or records `merge-closer: installed`, read `merge-closer.md` in this folder and follow it for Linear.

## First-run profile for Linear

For the state mapping, list the team's workflow states with a list-issue-statuses-style tool.
Propose a state named or categorized as started for `inProgress`, one named like "In Review" for `inReview`, and one named "Done" or categorized as completed for `done`.

## Setup instructions

The preflight call is the current-user tool, and only an error-free response verifies the MCP.

When it does not verify, tell the user how to connect Linear's MCP, pointing them to Linear's official MCP documentation for the endpoint instead of naming one.
On Claude Code, they install the Linear MCP connector or plugin and authenticate through it.
On Kiro, they add a Linear MCP server entry to `mcp.json`, using the endpoint from Linear's documented setup for that agent.
Either way, tell them to check an existing entry for a `disabled` flag first, since a disabled server looks the same as a missing one.
