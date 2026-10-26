# A parallel run: tasks 1 and 2 are independent, task 3 waits for both. The text of the
# band cannot tell two yellow segments from one, so look at the bar too (see the README).
# Format: see chain.tl.
@title Bench run
@titles Create bench/a.txt; Create bench/b.txt; Create bench/c.txt
@deps 3=1,2
0::-::noplan::::fathom (starting|unavailable)
1::header::noplan::::no tasks yet
2::ooo::noplan::::3 tasks so far
3::ooo::plan::::next 1/3 ~~ [^0-9]0%
4::>>o::plan::::now 1/3 ~~ [^0-9]0%
5::x>o::plan::::now 2/3 ~~ 33%
6::xxo::plan::::next 3/3 ~~ 67%
7::xx>::plan::nohash::now 3/3 ~~ 67%
8::xxx::plan::::✓ 3/3 done ~~ 100%
