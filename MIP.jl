
randomSeed = 0

nt = 10 # number of teams
nr = 18 # number of rounds (ideally = (nt-1)/2)
nc = 5 # number of courts (right now this is restricted to equal nt/2)

courtNames = "Court " .* string.(2:6)
courtTypes = ["Hard", "Hard", "SynGrass", "SynGrass", "Court6"]
courtTypeRanges = [ 1:2, 3:4, 5:5 ]

ncourtTypes = length(courtTypeRanges)
desiredMatches = nr / nc .* length.(courtTypeRanges)

# How many rounds to wait to replay the same team
# e.g., play same team in rounds 1 and 10? That's a closeness of 9
# Optimal value is nt-1
replayCloseness = nt-1

# Have a T-round break from court 6 after you've played on it
# (this is application-specific)
T = 3

# Maximum of p rounds on a surface in any given q rounds
p = 1
q = 1


# Set already played rounds in stone
playedDraw = [
    [[2,1], [6,7], [4,9], [5,8], [3,10]]' ;
    [[10,4], [2,3], [8,6], [9, 5], [1, 7]]'
] .|> collect


##
if nr % (nt-1) == 0
    minHead2Heads = Int(nr // (nt-1))
    maxHead2Heads = minHead2Heads
else
    minHead2Heads = floor(nr / (nt-1))
    maxHead2Heads = ceil(nr / (nt-1))
end


##
using JuMP
using Cbc

model = Model(Cbc.Optimizer)


# x_ijkr is in {0,1}, indicates whether team i plays team j on court k in round r
@variable(model, 0 <= x[1:nt, 1:nt, 1:nc, 1:nr] <= 1, Int)


# Play exactly one team on one court
@constraint(model, [j=1:nt, r=1:nr], 
    sum(x[i,j,k,r] for i in 1:nt, k in 1:nc) == 1)
@constraint(model, [i=1:nt, r=1:nr], 
    sum(x[i,j,k,r] for j in 1:nt, k in 1:nc) == 1)


# i plays j === j plays i
@constraint(model, [i=1:nt, j=1:nt, k=1:nc, r=1:nr], x[i,j,k,r] == x[j,i,k,r])


# Don't play self
@constraint(model, [i=1:nt, k=1:nc, r=1:nr], x[i,i,k,r] == 0)


# Reasonable matchup distribution
@constraint(model, [i=1:nt, j=1:nt; i != j], 
    minHead2Heads ≤ sum(x[i,j,k,r] for k in 1:nc, r in 1:nr) ≤ maxHead2Heads)


# One match per court
@constraint(model, [k in 1:nc, r=1:nr], 
    sum(x[i,j,k,r] for i in 1:nt, j in 1:nt) == 2)
# (every match is counted twice!)


# No close replays
@constraint(model, [i in 1:nt, j in 1:nt, r in 1:nr-replayCloseness+1],
    sum(x[i,j,k,nextfewrounds] for k in 1:nc, nextfewrounds in r:r+replayCloseness-1) ≤ 1
)


# Respect draw as has already been played
for r in axes(playedDraw,1), k in axes(playedDraw,2)
    teams = playedDraw[r,k]
    @constraint(model, x[teams[1],teams[2],k,r]==1)
    @constraint(model, x[teams[2],teams[1],k,r]==1)
end


# Have a T-round break from court 6 after you've played on it
@constraint(model,
    [i in 1:nt, k = [5], R in 1:nr-T],
    sum( x[i,j,k,r] for j in 1:nt, r in R:R+T ) <= 1
)


# Maximum of p rounds on a surface in any given q rounds
for n in 1:ncourtTypes
    @constraint(model,
        [i in 1:nt, R in 1:nr-q+1],
        sum( x[i,j,k,r] for j in 1:nt, k = courtTypeRanges[n], r in R:R+q-1) <= p
    )
end


# Must play a reasonable number of matches on each surface
floorDesiredMatches = floor.(desiredMatches)
ceilDesiredMatches = ceil.(desiredMatches)
for n in 1:ncourtTypes
    @constraint(model, [i in 1:nt],
        floorDesiredMatches[n] ≤
        sum(x[i,j,k,r] for j in 1:nt, k=courtTypeRanges[n], r=1:nr) ≤
        ceilDesiredMatches[n]
    )
end


# Then minimise the additional number of matches played on each surface after that
@objective(model,
    Min,
    1.0
)


# Solve the dang thing
set_optimizer_attribute(model, "maxSolutions", 1)
set_optimizer_attribute(model, "randomSeed", randomSeed)
set_optimizer_attribute(model, "randomCbcSeed", randomSeed)
optimize!(model)
termination_status(model)


##
X = value.(x)
draw = [ [0,0] for r in 1:nr, c in 1:nc ]

for i in 1:nt, j in 1:nt, k in 1:nc, r in 1:nr
    if X[i,j,k,r] == 1 && draw[r,k][1] == 0
        draw[r,k][1] = i
        draw[r,k][2] = j
    end
end

include("analyseDraw.jl")

analysis = analyseDraw(draw, courtTypes)

println()
println("The draw: (rows are rounds, columns are courts)")
display(draw)

println()





##

using CSV
using DataFrames
Draw = DataFrame()

for c in 1:nc
    Draw[!, courtNames[c]] = [ "$(draw[r,c][1]) v $(draw[r,c][2])" for r in 1:nr ]
end

CSV.write("draw.csv", Draw)