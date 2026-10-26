# Before Fathom has written its checklist, in a repository with no .beads/ folder, bd fails on
# every read ("no beads database found", or no bd at all). That is the normal state there, so
# the band must wait on `starting` and must not say `unavailable`. Format: see chain.tl.
@title Bench run
0::-::noplan::::fathom starting ~~ !unavailable
1::header::noplan::::no tasks yet ~~ !unavailable
