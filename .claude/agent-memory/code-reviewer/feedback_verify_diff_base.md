---
name: verify-diff-base
description: Before attributing any hunk in this repo, check `git log HEAD..main` — local main routinely sits ahead of a feature branch's base, which makes main's own commits show up inverted in `git diff main`
metadata:
  type: feedback
---

Never attribute a hunk from `git diff main` to the branch under review until you have run
`git log HEAD..main` (and `git log main..HEAD`) and confirmed the branch is actually based
on the current `main`.

**Why:** on a review of `feat/person-list-cards-and-portraits` the working tree was one
commit behind local `main`. `git diff main` therefore rendered main's own commit #40
("drop auto-injected Vorstand/Offiziere table") *inverted* — the deleted `people_for/1`
helper and the `person_table` call in `verein_page.html.heex` appeared as `+` lines, and I
was one step from filing findings against code the author never wrote. The author had to
correct the baseline mid-review.

**How to apply:** first two commands of any review here, before reading a single hunk:

    git log --oneline main..HEAD   # what the branch adds
    git log --oneline HEAD..main   # what the branch is MISSING — inverts in `git diff main`

If the second one is non-empty, either review `git diff $(git merge-base HEAD main)` /
plain `git diff` for uncommitted work, or ask the author to rebase before continuing. The
setup makes this likely rather than rare: per the repo's dev-container notes the author
works on a feature branch inside the main worktree (`./app`), so `main` gets fast-forwarded
underneath in-flight work. Related: [[public-site-redesign]].
