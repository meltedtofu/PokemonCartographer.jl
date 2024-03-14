module PokemonCartographer

using GameBoy
using PokemonObserver

using FileIO
using Images
using ProgressMeter
using Random
using MetaGraphsNext: labels, rem_edge!
using Distributed

include("Nav.jl")
using .Nav

include("render/Render.jl")

struct Job
    romname::String
    duration::Int
    emulator0::Emulator
    imageprefix::Union{String,Nothing}
    globe::Navmesh

    Job(romname, duration, emulator0, imageprefix, globe) = new(romname, duration, emulator0, imageprefix, globe)
end

# TODO: Compute other metrics for optimizing subsequent job generation (new spaces found, number of locations found, "compactness" of route, ...)
struct JobResult
    nav::Navmesh
    journey::Journey
end

struct JobResults
    nav::Navmesh
    journeys::Vector{Journey}

    JobResults() = new(Navmesh(), [])
    JobResults(a::JobResult, b::JobResult)::JobResults = new(Navmesh(a.nav, b.nav), [a.journey, b.journey])
    JobResults(a::JobResults, b::JobResult)::JobResults = new(Navmesh(a.nav, b.nav), vcat(a.journeys, [b.journey]))
    JobResults(a::JobResults, b::JobResults)::JobResults = new(Navmesh(a.nav, b.nav), vcat(a.journeys, b.journeys))
end

@enum State FirstBoot OpenFightDebug NewGame DialogSkip GoToTarget RandomWander

mutable struct JobState
    state::State
    nav::Navmesh
    lastpos::Tuple{UInt8, UInt8, UInt8}
    button::Union{Nothing, Button}
    lastpress::Int
    wasfacingmovementdir::Bool
    facingdir::Direction
    boinktimer::Int
    randomstepsremaining::Int
    gotohere::Union{Nothing, Position}
    waiting::Bool

    JobState(globe::Navmesh) = new(FirstBoot,
                                   globe,
                                   GameState().position,
                                   nothing,
                                   0,
                                   false,
                                   Down,
                                   0,
                                   25,
                                   randomincomplete(globe),
                                   false,
                                  )
end

function open_fight_debug!(js::JobState, gb::Emulator, game::GameState, i::Int)::State
    if isnothing(game.menu)
        buttonstate!(gb, ButtonSelect, i % 2 == 0)
        js.state
    else
        NewGame
    end
end

function new_game!(js::JobState, gb::Emulator, game::GameState, i::Int)::State
    if isnothing(game.menu)
        DialogSkip
    elseif ("FIGHT", 1) in game.menu
        buttonstate!(gb, ButtonDown, i % 2 == 0)
        js.state
    elseif ("DEBUG", 1) in game.menu
        buttonstate!(gb, ButtonA, i % 2 == 0)
        js.state
    end
end

function dialog_skip!(js::JobState, gb::Emulator, game::GameState, i::Int)::State
    # Get through all of the dialog. Crude approximation to avoid deeper coupling into the emulator.

    if i < 1 * 60 * 60
        buttonstate!(gb, ButtonB, i % 2 == 0)
        js.state
    else
        GoToTarget
    end
end

function go_to_target!(js::JobState, gb::Emulator, game::GameState, i::Int)::State
    buttonstate!(gb, ButtonB, false)
    if isnothing(js.gotohere) || Position(game.position) == js.gotohere
        RandomWander
    else
        r = route(js.nav, Position(game.position), js.gotohere)
        if length(r) == 0
            return RandomWander
        elseif i > js.lastpress + 16
            js.lastpress = i
            buttonstate!(gb,
                r |> first |> asbutton,
                false)
        end
        js.state
    end
end

function random_wander!(js::JobState, gb::Emulator, game::GameState, i::Int)::State
    buttonstate!(gb, ButtonB, false)

    if js.waiting
        # Are we done waiting?
        buttonstate!(gb, js.button, false)
        if js.lastpos != game.position # We found somewhere new
            # TODO: Wait for tileset to settle?
            if js.lastpos != (0x00, 0x00, 0x00)
                # if lastpos[2] != game.position[2] && lastpos[3] != lastpos[3]
                #     @info "diagonal $(lastpos) -> $button -> $(game.position)"
                # end

                # if !(-2 < Int(lastpos[2]) - Int(game.position[2]) < 2) || !(-2 < Int(lastpos[3]) - Int(game.position[3]) < 2)
                #     @info "skip $(lastpos) -> $button -> $(game.position)"
                # end
                                        
                if goesnowhere(js.nav, Position(js.lastpos), js.button)
                    # @info "Removing edge to nowhere: $(lastpos), $(asnowhere(button))"
                    rem_edge!(js.nav, Position(js.lastpos), asnowhere(js.button))
                end

                Navmesh!(js.nav, Position(js.lastpos), Position(game.position), asdirection(js.button))
            end
            js.waiting = false
        elseif i > js.lastpress + 100 # We are not going anywhere -> boink!
            js.waiting = false
            if js.lastpos != (0x00, 0x00, 0x00)
                nowhere = asnowhere(js.button)

                # Only add if lastpos -> "somewhere" with button doesn't exist
                if !goessomewhere(js.nav, Position(js.lastpos), js.button)
                    Navmesh!(js.nav, Position(js.lastpos), nowhere, asdirection(js.button))
                # else
                #     @warn "Trying to add edge to nowhere when an edge already exists $lastpos -> $button -> $nowhere"
                end
            end
        end
    else
        # Time to press a button
        js.button = rand([ButtonUp, ButtonLeft, ButtonDown, ButtonRight])
        js.wasfacingmovementdir = asbutton(js.facingdir) == js.button
        js.waiting = true
        js.lastpress = i
        js.lastpos = game.position
        buttonstate!(gb, js.button, false)
    end

    js.state
end

function dojob(job::Job)::JobResult
    nav = job.globe
    journey = Journey()

    s = JobState(nav)
    gb = deepcopy(job.emulator0)

    for i in 1:job.duration
        gb.mmu.workram.bytes[0xd732-0xc000] |= 0x02 # Enable Debug Mode
        gb.mmu.workram.bytes[0xd747-0xc000] |= 0x01 # Followed Oak in to lab
        gb.mmu.workram.bytes[0xd74b-0xc000] |= 0xff # Complete most of the intro (following oak, pokedex, ...)
        s.facingdir = asdirection(gb.mmu.workram.bytes[0xc109-0xc000])

        pixels = doframe!(gb)
        game = GameState(gb, pixels)

        buttonstate!(gb, ButtonA, true)
        buttonstate!(gb, ButtonUp, true)
        buttonstate!(gb, ButtonDown, true)
        buttonstate!(gb, ButtonLeft, true)
        buttonstate!(gb, ButtonRight, true)

        if s.state == GoToTarget || s.state == RandomWander
            push!(journey, Placement(Position(game.position), s.facingdir))
        end

        if s.state == FirstBoot
            s.state = OpenFightDebug
        elseif s.state == OpenFightDebug
            s.state = open_fight_debug!(s, gb, game, i)
        elseif s.state == NewGame
            s.state = new_game!(s, gb, game, i)
        elseif s.state == DialogSkip
            s.state = dialog_skip!(s, gb, game, i)
        elseif s.state == GoToTarget
            s.state = go_to_target!(s, gb, game, i)
        elseif s.state == RandomWander
            s.state = random_wander!(s, gb, game, i)
        end
    end

    if !isnothing(job.imageprefix)
        pixels = doframe!(gb)
        Images.save(File{format"PNG"}(joinpath("screens", "$(job.imageprefix).end.png")), reinterpret(BGRA{N0f8}, pixels))
    end

    JobResult(nav, journey)
end

function dojobs(jobs, results)::Nothing
    while true
        job = take!(jobs)
        put!(results, dojob(job))
    end
end

"""
Generate a batch of jobs to run
"""
function genbatch(roms::Vector{String}, duration::Int, counter::Int, globe::Navmesh; copies::Int=1)::Vector{Job}
    # TODO: Make this more functional instead of manually pushing to a vector
    jobs = []
    for _ in 1:copies
        for r in roms
            gb = Emulator(r)
            push!(jobs, Job(r, duration, gb, nothing, deepcopy(globe)))
            counter += 1
        end
    end
    jobs
end

"""
Create a Navmesh by playing the game.

Starting with a list of roms and save states, spawn a worker for each pair and merge the resulting navmeshes.
"""
function explore(;duration_min=15, copies=100, target=500)
    roms = ["BLUEMONS.gb"] .|> r -> joinpath(@__DIR__, "..", "roms", r)
    animdir = joinpath(@__DIR__, "..", "anim")
    rm(animdir, force=true, recursive=true)
    mkdir(animdir)

    jobcounter = 1
    batchcounter = 1
    globe = Navmesh()
    journeys = Vector{Vector{Journey}}()
    renderingbb = Render.BoundingBox(7200, 7200, 0, 0)
    duration = duration_min*60*60

    prog = ProgressThresh(0.1; desc="Exploring...", color=:blue)
    update!(prog, target)

    jobqueue = RemoteChannel(() -> Channel{Job}(50))
    resultqueue = RemoteChannel(() -> Channel{JobResult}(50))
    submit_job(j) = put!(jobqueue, j)

    foreach(pid -> remote_do(dojobs, pid, jobqueue, resultqueue), workers())

    while length(labels(globe)) < target
        jobs = genbatch(roms, duration, jobcounter, globe; copies=copies)
        bprog = Progress(length(jobs), "Batch $batchcounter ($(length(jobs))) jobs"; color = :blue, offset=batchcounter+1)
        
        @async foreach(submit_job, jobs)
        jobcounter += length(jobs)

        jrs = JobResults()

        for i in 1:length(jobs)
            jrs = JobResults(jrs, take!(resultqueue))
            next!(bprog)
        end

        globe = Navmesh(globe, jrs.nav)
        push!(journeys, jrs.journeys)
        renderingbb = Render.render(jrs.journeys, globe, batchcounter, animdir, renderingbb)

        update!(prog, target - length(labels(globe)))

        batchcounter += 1
    end

    println("")

    @info "Found $(length(labels(globe))) locations"

    (globe, journeys)
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
