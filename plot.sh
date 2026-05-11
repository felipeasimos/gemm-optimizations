#!/usr/bin/env gnuplot

set datafile separator ","

TITLE = "GEMM Benchmark"
set xlabel "Matrix Size"
set ylabel "Time (ms)"


set terminal qt persist noenhanced noraise font "Sans,12" size 1000,600 title TITLE
set grid
set key autotitle columnheader
set autoscale fix

# Better readability
set border lw 1.5
set tics nomirror
set pointsize 1.2

# ------------------------------------------------------------
# Discover CSV files
# ------------------------------------------------------------
files = system("ls data/*.csv")
filename(n) = word(files, int(n))

# data/f32_async.csv -> f32_async
basename(n) = \
    substr( \
        filename(n), \
        6, \
        strlen(filename(n)) - 4 \
    )
# Split "f32_async" on the first underscore
datatype(n) = substr(basename(n), 1, strstrt(basename(n), "_") - 1)
method(n)   = substr(basename(n), strstrt(basename(n), "_") + 1, strlen(basename(n)))
# ------------------------------------------------------------
# Datatype info
# ------------------------------------------------------------
dtype_kind(n) = substr(datatype(n), 1, 1)
bitsize(n)    = int(substr(datatype(n), 2, strlen(datatype(n))))
# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
frac(x) = x - floor(x)
# ------------------------------------------------------------
# Float/int line style  (floats dashed, integers solid)
# ------------------------------------------------------------
dash(n) = (dtype_kind(n) eq "f") ? 2 : 1
# ------------------------------------------------------------
# Bitsize -> color
# ------------------------------------------------------------
hue(bits)   = frac(log(bits)/log(2) * 0.173)
color(bits) = hsv2rgb(hue(bits), 0.85, 0.95)
# ------------------------------------------------------------
# Method procedural styling
# ------------------------------------------------------------
imod(a, b) = a - floor(a/b) * b

charcode(c) = system("printf '%d' \"'" . method(1)[1:1] . "\"") + 0
method_hash(n) = sum [j=1:strlen(method(n))] charcode(method(n)[j:j])

point(n)     = 1 + imod(method_hash(n), 10)
width(n)     = 1 + imod(method_hash(n), 4)
pinterval(n) = 2 + imod(method_hash(n), 6)
# ------------------------------------------------------------
# Caching
# ------------------------------------------------------------
array bitsizes[words(files)]
array colors[words(files)]
array dashes[words(files)]
array points[words(files)]
array widths[words(files)]
array pintervals[words(files)]
array basenames[words(files)]
do for [i=1:words(files)] {
    bitsizes[i] = bitsize(i)
    colors[i] = color(bitsize(i))
    dashes[i] = dash(i)
    points[i] = point(i)
    # widths[i] = width(i)
    widths[i] = 1
    pintervals[i] = pinterval(i)
    basenames[i] = basename(i)
}
# ------------------------------------------------------------
# Plot
# ------------------------------------------------------------
plot for [i=1:words(files)] \
    filename(i) \
    using 1:2 \
    every ::1 \
    with linespoints \
    lc rgb color(bitsize(i)) \
    dt dashes[i] \
    lw widths[i] \
    pt points[i] \
    pi 1 \
    title basenames[i]

pause mouse close
