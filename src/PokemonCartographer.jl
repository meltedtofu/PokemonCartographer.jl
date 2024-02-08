module PokemonCartographer

using GameBoy
using PokemonObserver

using FileIO
using Images
using ProgressMeter
using Random
using MetaGraphsNext: labels
using Distributed

include("Nav.jl")
using .Nav

struct Job
    romname::String
    savename::String
    duration::Int
    emulator0::Emulator
    imageprefix::Union{String, Nothing}

    Job(romname, savename, duration, emulator0, imageprefix) = new(romname, savename, duration, emulator0, imageprefix)
end

function dojob(job::Job)::Navmesh
    nav = Navmesh()
    statenum = 1
    lastpos = GameState().position
    button = nothing

    gb = deepcopy(job.emulator0)

    # TODO: Enable debug_mode (set bit 1 of 0xd732)
    # TODO: Ensure that B is constantly pressed (set buttonstate arg to false)
    # TODO: Check if any of the saves end up with a battle (run it and look at the screenshots)
    # TODO: That didn't work. Do I need to start a new game for this to take effect? This is doing something, but now I'm stuck in the intro dialog...

    for i in 1:job.duration
        gb.mmu.workram.bytes[0xd732 - 0xc000] |= 0x01
        pixels = doframe!(gb)
        game = GameState(gb, pixels)
        buttonstate!(gb, ButtonA,     true)
        #buttonstate!(gb, ButtonB,     true)
        buttonstate!(gb, ButtonUp,    true)
        buttonstate!(gb, ButtonDown,  true)
        buttonstate!(gb, ButtonLeft,  true)
        buttonstate!(gb, ButtonRight, true)

        if statenum == 1 # Haven't loaded the game yet keep smashing A
            if isnothing(game.menu)
                buttonstate!(gb, ButtonA, i%2 == 0)
            else
                statenum = 2
            end
        elseif statenum == 2 ## Select new game
            if isnothing(game.menu)
                statenum = 3
            elseif ("NEW GAME", 1) in game.menu
                buttonstate!(gb, ButtonUp, i%2 == 0)
            elseif ("CONTINUE", 1) in game.menu
                buttonstate!(gb, ButtonA, i%2 == 0)
            elseif ("OPTIONS", 1) in game.menu
                buttonstate!(gb, ButtonUp, i%2 == 0)
            end
        elseif statenum == 3 # Unclear why this delay is needed. Just going with it for now.
            if i < 2*60*60
                buttonstate!(gb, ButtonA, i%2 == 0)
            else
                statenum = 4
            end
        elseif statenum == 4
            buttonstate!(gb, ButtonB, false)
            if i%3 == 0
                button = rand([ButtonUp, ButtonDown, ButtonLeft, ButtonRight])
                buttonstate!(gb, button, false)
            elseif lastpos != game.position &&!isnothing(button)
                Navmesh!(nav, Position(lastpos), Position(game.position), asdirection(button))
                lastpos = game.position
            end
        end
    end

    if !isnothing(job.imageprefix)
        pixels = doframe!(gb)
        save(File{format"PNG"}(joinpath("screens", "$(job.imageprefix).end.png")), reinterpret(BGRA{N0f8}, pixels))
    end

    nav
end

"""
Generate a batch of jobs to run
"""
function genbatch(roms::Vector{String}, saves::Vector{String}, duration::Int, counter::Int; copies::Int=1)::Vector{Job}
    # TODO: Make this more functional instead of manually pushing to a vector
    jobs = []
    for _ in 1:copies
        for r in roms
            for s in saves[2:10]
                gb = Emulator(r)
                sav = Vector{UInt8}(undef, 2^15)
                open(s) do io
                    readbytes!(io, sav)
                end
                ram!(gb, sav)

                push!(jobs, Job(r, s, duration, gb, "$counter"))
                counter += 1
            end
        end
    end
    jobs
end

"""
Create a Navmesh by playing the game.

Starting with a list of roms and save states, spawn a worker for each pair and merge the resulting navmeshes.
"""
function explore()::Navmesh
#    roms = ["POKEMON BLUE.gb", "POKEMON RED.gb"] .|> r -> joinpath(@__DIR__, "..", "roms", r)
    roms = ["BLUEMONS.gb"] .|> r -> joinpath(@__DIR__, "..", "roms", r)

    saves = walkdir(joinpath(@__DIR__, "..", "saves")) .|>
            (listing -> map(f -> joinpath(first(listing), f), last(listing))) |>
            Base.Fix1(reduce, vcat) |>
            Base.Fix1(filter, f -> !contains(f, "DS_Store"))

    duration = 10*60*60

    jobcounter = 1
    batchcounter = 1
    globe = Navmesh()

    target = 2000

    prog = ProgressThresh(0.1; desc="Exploring...", color=:blue)
    update!(prog, target)

    while length(labels(globe)) < target
        jobs = genbatch(roms, saves, duration, jobcounter; copies=2)
        jobcounter += length(jobs)
        globe0 = @showprogress desc="Batch $batchcounter ($(length(jobs)) jobs)" color=:blue offset=1 @distributed (Navmesh) for j in jobs
            dojob(j)
        end
        globe = Navmesh(globe, globe0)
        batchcounter += 1
        update!(prog, target - length(labels(globe)))  #?? How to map percent complete towards target into a threshold value?
    end

    println("")

    @info "Found $(length(labels(globe))) locations"

    globe
end

function checkkeylocations(globe::Navmesh)
    locs = [(:GameSpawn, Position(0x26, 4, 7)),
            (:Brock, Position(0x36, 5, 3)),
            (:Misty, Position(0x41, 5, 3)),
            # TODO: Surge
            # TODO: Erika
            # TODO: Koga
            (:Sabrina, Position(0xb2, 10, 9)),
            # TODO: Blaine
            # TODO: Giovanni
           ]

    # Are the important loctions found?
    found = (locs .|> l -> (first(l), last(l) in labels(globe)))

    # Are the important locations connected?
    # Do I just build a matrix and check every pair?
    connectivity = (Iterators.product(locs, locs) .|> p -> connected(globe, last(first(p)), last(last(p))) > 0)

    @info "Found $found"

    @info "Connectivity"
    display(connectivity)
end



export explore, checkkeylocations

end # module PokemonCartographer
