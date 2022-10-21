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
        maxStreak = 1
        for surface in keys(roundsOnSurface_t)
            streak = 1
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