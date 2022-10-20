
nt = 10
nr = 18
nc = 5

# How many rounds to wait to replay the same team
# e.g., play same team in rounds 1 and 10? That's a closeness of 9
replayCloseness = nt-1

# Have a T-round break from court 6 after you've played on it
T = 3

# Maximum of p rounds on a surface in any given q rounds
p = 1
q = 1

courtTypeRanges = [ 1:2, 3:4, 5:5 ]
ncourtTypes = length(courtTypeRanges)
desiredMatches = nr / nc .* length.(courtTypeRanges)

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
        [i in 1:nt, R in 1:nr-q],
        sum( x[i,j,k,r] for j in 1:nt, k = courtTypeRanges[n], r in R:R+q) <= p
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

function analyseDraw(draw, courtTypes)

    numRounds, numCourts = size(draw)
    numTeams = 2*numCourts
    
    homeCounts = zeros(Int, numTeams)
    head2headCounts = zeros(Int, numTeams, numTeams)
    head2headRounds = [ Int[] for i in 1:numTeams, j in 1:numTeams ]
    roundsOnSurface = [ Dict([c => Int[] for c in courtTypes]) for _ in 1:numTeams ]
    courtCounts = [ Dict([c => 0 for c in courtTypes]) for _ in 1:numTeams ]

    for roundNum in axes(draw, 1)
        for courtNum in axes(draw, 2)

            teams = draw[roundNum, courtNum]

            homeCounts[teams[1]] += 1

            head2headCounts[teams[1], teams[2]] += 1
            head2headCounts[teams[2], teams[1]] += 1

            push!(head2headRounds[teams[1], teams[2]], roundNum)
            push!(head2headRounds[teams[2], teams[1]], roundNum)

            courtCounts[teams[1]][courtTypes[courtNum]] += 1
            courtCounts[teams[2]][courtTypes[courtNum]] += 1

            push!(roundsOnSurface[teams[1]][courtTypes[courtNum]], roundNum)
            push!(roundsOnSurface[teams[2]][courtTypes[courtNum]], roundNum)

        end
    end

    maxConsecutiveSurfaces = zeros(Int, numTeams)
    for t in 1:numTeams

        roundsOnSurface_t = roundsOnSurface[t]
        streak = 1
        maxStreak = 1
        for surface in keys(roundsOnSurface_t)
            rounds = roundsOnSurface_t[surface]
            (length(rounds) == 1) && continue
            for i in 2:length(rounds)
                if (rounds[i] - rounds[i-1]) == 1
                    streak += 1
                    maxStreak = max(maxStreak, streak)
                else
                    streak = 1
                end
            end
        end
        maxConsecutiveSurfaces[t] = maxStreak

    end

    sort!.(head2headRounds)
    minReplayGaps = [ minimum(diff(head2headRounds[i,j]), init=Inf) for i in 1:numTeams, j in 1:numTeams ]
    minReplayGap = minimum(minReplayGaps)

    analysis = (
        homeCounts = homeCounts,
        head2headCounts = head2headCounts,
        minReplayGaps = minReplayGaps,
        minReplayGap = minReplayGap,
        courtCounts = courtCounts,
        roundsOnSurface = roundsOnSurface,
        maxConsecutiveSurfaces = maxConsecutiveSurfaces
    )

    println()
    println("How many times does each team play on each surface?")
    for t = 1:numTeams
        print("Team $t: ")
        println(courtCounts[t])
    end

    println()
    println("How many times does team i play team j?")
    display(head2headCounts)

    println()
    println("How many rounds does team i wait to replay team j?")
    display(minReplayGaps)
    println("Minimum: $minReplayGap rounds")

    println()
    println("Maximum number of consecutive rounds on any one surface:")
    display(maxConsecutiveSurfaces)
    println()
    println("Maximum: $(maximum(maxConsecutiveSurfaces)) consecutive rounds")

    return analysis

end

courtTypes = ["Hard", "Hard", "SynGrass", "SynGrass", "Court6"]

analysis = analyseDraw(draw, courtTypes)

println()
println("The draw: (rows are rounds, columns are courts 2 through 6)")
display(draw)

println()





##

courtNames = "Court " .* string.(2:6)

using CSV
using DataFrames
Draw = DataFrame()

for c in 1:nc
    Draw[!, courtNames[c]] = [ "$(draw[r,c][1]) v $(draw[r,c][2])" for r in 1:nr ]
end

CSV.write("draw.csv", Draw)