# ship pipeline profile

This repository's resolved delivery pipeline, read by the `ship` skill before it
touches the working tree. Edit it directly; ship rewrites it only when one of
these commands stops resolving.

```markdown
verify: bin/test-watch.sh && bin/test-guard.sh && bin/test-resolve-verify.sh && bin/test-land.sh && bin/test-check-pipeline-skills.sh && bin/test-worktree-setup.sh && bin/test-scan-skills.sh && bin/scan-skills.sh && bin/test-sync-versions.sh && bin/sync-versions.sh && bin/test-check-dashes.sh && bin/check-dashes.sh && bin/test-check-frontmatter.sh && bin/check-frontmatter.sh && bin/test-check-skill-size.sh && bin/check-skill-size.sh && claude plugin validate --strict . && claude plugin validate --strict mods/fathom-progress && mods/fathom-progress/bin/sync-contract.sh && claude plugin test mods/fathom-progress   # asked
base: main
release: none
cross-review: cursor
post-merge: none
merge: yes
```
