# A file at .fathom/tasks/<ref>.md that is not a checklist, then one that is. The band must
# say why it has nothing, never show zeros, and recover when the file becomes a checklist.
# Format: see chain.tl.
@title Bench run
@titles Create bench/a.txt; Create bench/b.txt; Create bench/c.txt
@deps 2=1 3=2
0::raw:hello::noplan::::unavailable.*not a Fathom checklist
1::raw:# {ref}: Bench run::noplan::::no tasks yet ~~ !unavailable
2::ooo::plan::::next 1/3 ~~ !unavailable
