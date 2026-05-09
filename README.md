## GEMM optimizations

GEMM (general matrix multiplication) in zig. With a nice plot to go alongside it.
Each implementation is given the dimensions and major of each matrix (including the desired major for C).
It should always take major into account for the best possible route (I don't want to implement two functions for each optimization).

## Implementations

1. Naive (single-threaded)
   * Just plays nice with the majors, but nothing else outside of it
