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
    duration::Int
    emulator0::Emulator
    imageprefix::Union{String, Nothing}

    Job(romname, duration, emulator0, imageprefix) = new(romname, duration, emulator0, imageprefix)
end

function dojob(job::Job, globe::Navmesh)::Navmesh
    nav = Navmesh()
    statenum = 1
    lastpos = GameState().position
    button = nothing
    lastpress = 0
    wasfacingmovementdir = false

    gotohere = randomincomplete(globe)

    gb = deepcopy(job.emulator0)

    for i in 1:job.duration
        gb.mmu.workram.bytes[0xd732 - 0xc000] |= 0x02 # Enable Debug Mode
        gb.mmu.workram.bytes[0xd747 - 0xc000] |= 0x01 # Followed Oak in to lab
        gb.mmu.workram.bytes[0xd74b - 0xc000] |= 0xff # Complete most of the intro (following oak, pokedex, ...)
        facingdir = asdirection(gb.mmu.workram.bytes[0xc109 - 0xc000])
        pixels = doframe!(gb)
        game = GameState(gb, pixels)

        buttonstate!(gb, ButtonA,     true)
        buttonstate!(gb, ButtonUp,    true)
        buttonstate!(gb, ButtonDown,  true)
        buttonstate!(gb, ButtonLeft,  true)
        buttonstate!(gb, ButtonRight, true)

        if statenum == 1 # Haven't loaded the game yet keep smashing Select to open the Fight/Debug menu
            if isnothing(game.menu)
                buttonstate!(gb, ButtonSelect, i%2 == 0)
            else
                statenum = 2
            end
        elseif statenum == 2 ## Select new game
            if isnothing(game.menu)
                statenum = 3
            elseif ("FIGHT", 1) in game.menu
                buttonstate!(gb, ButtonDown, i%2 == 0)
            elseif ("DEBUG", 1) in game.menu
                buttonstate!(gb, ButtonA, i%2 == 0)
            end
        elseif statenum == 3 # Get through all of the dialog. Crude approximation to avoid deeper coupling into the emulator.
            if i < 1*60*60
                buttonstate!(gb, ButtonB, i%2 == 0)
            else
                statenum = 4
            end
        elseif statenum == 4 # Go to target
            if isnothing(gotohere) || Position(game.position) == gotohere
                statenum = 5
            else
                r = route(globe, Position(game.position), gotohere)
                if length(r) == 0
                    statenum = 5
                elseif i > lastpress + 64
                    lastpress = i
                    buttonstate!(gb,
                                 r |> first |> asbutton,
                                 false)
                end
            end
        elseif statenum == 5 # Random bouncing around
            buttonstate!(gb, ButtonB, false)
            if i > lastpress + 64
                if !isnothing(button)
                    if wasfacingmovementdir # Tried to move (instead of turning). Update navmesh.
                        if lastpos == game.position # boink!
                            if lastpos != (0x00, 0x00, 0x00)
                                Navmesh!(nav, Position(lastpos), nowhere, asdirection(button))
                            end
                        else
                            if lastpos != (0x00, 0x00, 0x00)
                                Navmesh!(nav, Position(lastpos), Position(game.position), asdirection(button))
                            end
                            lastpos = game.position
                        end
                    end
                end

                button = rand([ButtonUp, ButtonDown, ButtonLeft, ButtonRight])
                buttonstate!(gb, button, false)
                wasfacingmovementdir = asbutton(facingdir) == button
                lastpress = i
            end
        end
    end

    if !isnothing(job.imageprefix)
        pixels = doframe!(gb)
        Images.save(File{format"PNG"}(joinpath("screens", "$(job.imageprefix).end.png")), reinterpret(BGRA{N0f8}, pixels))
    end

    nav
end

"""
Generate a batch of jobs to run
"""
function genbatch(roms::Vector{String}, duration::Int, counter::Int; copies::Int=1)::Vector{Job}
    # TODO: Make this more functional instead of manually pushing to a vector
    jobs = []
    for _ in 1:copies
        for r in roms
            gb = Emulator(r)
            push!(jobs, Job(r, duration, gb, "$counter"))
            counter += 1
        end
    end
    jobs
end

"""
Create a Navmesh by playing the game.

Starting with a list of roms and save states, spawn a worker for each pair and merge the resulting navmeshes.
"""
function explore()::Navmesh
    roms = ["BLUEMONS.gb"] .|> r -> joinpath(@__DIR__, "..", "roms", r)

    duration = 5*60*60

    jobcounter = 1
    batchcounter = 1
    globe = Navmesh()

    target = 1000

    prog = ProgressThresh(0.1; desc="Exploring...", color=:blue)
    update!(prog, target)

    while length(labels(globe)) < target
        jobs = genbatch(roms, duration, jobcounter; copies=60)
        jobcounter += length(jobs)
        globe0 = @showprogress desc="Batch $batchcounter ($(length(jobs)) jobs)" color=:blue offset=batchcounter @distributed (Navmesh) for j in jobs
            dojob(j, deepcopy(globe))
        end

        globe = Navmesh(globe, globe0)
        update!(prog, target - length(labels(globe)))
        batchcounter += 1
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
    connectivity = (Iterators.product(locs, locs) .|> p -> connected(globe, last(first(p)), last(last(p))) > 0)

    @info "Found $found"

    @info "Connectivity"
    display(connectivity)
end



export explore, checkkeylocations

end # module PokemonCartographer
