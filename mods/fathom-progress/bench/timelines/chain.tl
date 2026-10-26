# One Fathom run in a line: three tasks, each behind the one before it.
#
# A step is: step :: tasks :: plan :: extras :: expectations   (fields end at "::")
#   tasks   - (no checklist file) | header (no task lines yet) | raw:<text> (the file's
#           exact text, {ref} filled in) | markers, one per task: o open, > in progress, x done
#   plan    plan | noplan (the plan document .fathom/plans/<ref>.md exists or not)
#   extras  comma list: nohash (the last done task has no commit hash yet), footer (a
#           trailing "- Closed:" line)
#   expectations
#           ERE patterns joined by " ~~ ", each matched against the screen. A leading !
#           means the pattern must NOT match.
# The expectations are the band's own words (draw.tsx), so they hold for the terminal band.
@title Bench run
@titles Create bench/a.txt; Create bench/b.txt; Create bench/c.txt
@deps 2=1 3=2
# With no file the band is on starting, or on unavailable when bd cannot be read.
0::-::noplan::::fathom (starting|unavailable)
1::header::noplan::::no tasks yet
2::ooo::noplan::::3 tasks so far
3::ooo::plan::::next 1/3 ~~ [^0-9]0% ~~ Bench run
4::>oo::plan::::now 1/3 ~~ !next 1/3
5::x>o::plan::::now 2/3 ~~ 33% ~~ !now 1/3
6::xx>::plan::nohash::now 3/3 ~~ 67%
7::xxx::plan::nohash::✓ 3/3 done ~~ 100%
8::xxx::plan::footer::✓ 3/3 done ~~ 100%
