<!--
PR title: a conventional commit, used as the squash commit message and by release-please:
  <type>[(<scope>)][!]: <description>
  type: feat, fix, perf, revert (release), or docs, style, refactor, test, build, ci, chore (no release)
  scope (optional): api, federation-api, annotation-tool, bagel-cli, query-tool
  "!" marks a breaking change.

A PR that changes more than one package and should release several of them: use a
non-releasing title (chore:, ci:, ...), make one conventional commit per package (each
touching only that package), and merge with a MERGE COMMIT. See DEVELOPING.md. The
"release-preview" job summary shows what release-please would propose.
Never write the release-please override marker literally in this description; escape it as
BEGIN\_COMMIT\_OVERRIDE when you mention it.
-->

- Closes #

Changes proposed in this pull request:

-

## Checklist
_This section is for the PR reviewer_

- [ ] PR title is a conventional commit with the right type (it decides the release)
- [ ] Multi-package PR that releases: one conventional commit per package, non-releasing title, merge with a merge commit
- [ ] Packages stay self-contained and mirrorable (DEVELOPING.md, "Rules for the trial"); package workflows updated if the package's build or CI changed
- [ ] PR links to a GitHub issue with `Closes #XXXX`
- [ ] Tests pass
- [ ] Checks pass

For new features:
- [ ] Tests have been added

For bug fixes:
- [ ] There is at least one test that would fail under the original bug conditions.
