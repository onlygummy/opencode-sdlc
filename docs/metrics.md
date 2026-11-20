# Metrics

This page records the delivery metrics for the repo and the rules for measuring
them.

## Baseline

Recorded on 2026-11-20 at commit `a15108a`.

| Metric | Value | Source |
| --- | --- | --- |
| Commits in the last 90 days | 81 | `git rev-list --count --since="90 days ago" HEAD` |
| Commits in the last 30 days | 79 | `git rev-list --count --since="30 days ago" HEAD` |
| Feature commits in the last 90 days | 40 | `git log --since="90 days ago" --grep="^feat" --oneline` |
| Revert commits in history | 1 | `git log --grep="revert" -i --oneline` |
| PR CI duration | not measured | no pull request workflow exists |
| Review rounds per change | not measured | no review report artifact exists |
| Lead time from plan to merge | not measured | no plan artifact or PR start timestamp exists |
| Escaped defects | not measured | commits do not link to an issue tracker |
| Time to fix review findings | not measured | no review report artifact exists |

The rows marked `not measured` are the ones the improvement plan creates: a PR
workflow gives PR CI duration, a review report artifact gives review rounds and
time to fix findings, the plan artifact gives the lead time start, and an issue
link gives escaped defects. Until those exist, the value stays `not measured`
rather than an estimate.

## Collection rules

- Count a change once, at the squash commit on the trunk.
- Measure lead time from the first plan timestamp to the squash commit.
- Count a review round each time `reviewwright` returns a verdict for the same
  change.
- Count a revert as a change whose squash commit is reverted within 30 days.
- Record the values on the first working day of each month.
- Keep the raw command output in the issue that records the monthly review.
