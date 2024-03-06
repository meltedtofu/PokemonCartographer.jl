module PokemonCartographer

using GameBoy
using PokemonObserver

using FileIO
using Images
using ProgressMeter
using Random
using MetaGraphsNext: labels, code_for, outdegree
using Distributed
using Luxor

include("Nav.jl")
using .Nav

struct Job
    romname::String
    duration::Int
    emulator0::Emulator
    imageprefix::Union{String,Nothing}
    globe::Navmesh

    Job(romname, duration, emulator0, imageprefix, globe) = new(romname, duration, emulator0, imageprefix, globe)
end

struct Placement
    position::Position
    orientation::Direction
end

const Journey = Vector{Placement}

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

function dojob(job::Job)::JobResult
    nav = job.globe
    statenum = 1
    lastpos = GameState().position
    button = nothing
    lastpress = 0
    wasfacingmovementdir = false

    gotohere = randomincomplete(nav)
    journey = Journey()

    gb = deepcopy(job.emulator0)

    for i in 1:job.duration
        gb.mmu.workram.bytes[0xd732-0xc000] |= 0x02 # Enable Debug Mode
        gb.mmu.workram.bytes[0xd747-0xc000] |= 0x01 # Followed Oak in to lab
        gb.mmu.workram.bytes[0xd74b-0xc000] |= 0xff # Complete most of the intro (following oak, pokedex, ...)
        facingdir = asdirection(gb.mmu.workram.bytes[0xc109-0xc000])

        pixels = doframe!(gb)
        game = GameState(gb, pixels)

        buttonstate!(gb, ButtonA, true)
        buttonstate!(gb, ButtonUp, true)
        buttonstate!(gb, ButtonDown, true)
        buttonstate!(gb, ButtonLeft, true)
        buttonstate!(gb, ButtonRight, true)

        if statenum >= 4
            push!(journey, Placement(Position(game.position), facingdir))
        end

        if statenum == 1 # Haven't loaded the game yet keep smashing Select to open the Fight/Debug menu
            if isnothing(game.menu)
                buttonstate!(gb, ButtonSelect, i % 2 == 0)
            else
                statenum = 2
            end
        elseif statenum == 2 ## Select new game
            if isnothing(game.menu)
                statenum = 3
            elseif ("FIGHT", 1) in game.menu
                buttonstate!(gb, ButtonDown, i % 2 == 0)
            elseif ("DEBUG", 1) in game.menu
                buttonstate!(gb, ButtonA, i % 2 == 0)
            end
        elseif statenum == 3 # Get through all of the dialog. Crude approximation to avoid deeper coupling into the emulator.
            if i < 1 * 60 * 60
                buttonstate!(gb, ButtonB, i % 2 == 0)
            else
                statenum = 4
            end
        elseif statenum == 4 # Go to target
            if isnothing(gotohere) || Position(game.position) == gotohere
                statenum = 5
            else
                r = route(nav, Position(game.position), gotohere)
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
                                nowhere = nowhereup
                                if button == ButtonUp    
                                    nowhere = nowhereup
                                elseif button == ButtonDown
                                    nowhere = nowheredown
                                elseif button == ButtonLeft
                                    nowhere = nowhereleft
                                elseif button == ButtonRight
                                    nowhere = nowhereright
                                end
                                Navmesh!(nav, Position(lastpos), nowhere, asdirection(button))
                            end
                        else
                            if lastpos != (0x00, 0x00, 0x00)
                                Navmesh!(nav, Position(lastpos), Position(game.position), asdirection(button))
                            end
                        end
                        lastpos = game.position
                    end
                end

                button = rand([ButtonUp, ButtonDown, ButtonLeft, ButtonRight])
                buttonstate!(gb, button, false)
                wasfacingmovementdir = asbutton(facingdir) == button
                lastpress = i
            end

            if i % 5_000 == 0
                gotohere = randomincomplete(nav) 
                lastpress = i
                statenum = 4
            end
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
    renderingbb = BoundingBox(7200, 7200, 0, 0)
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
        renderingbb = render(jrs.journeys, globe, batchcounter, animdir, renderingbb)

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

function location_to_pixels(l::UInt8)::Point
    if l == 0x00
        Point(1504, 4526)
    elseif l == 0x01
        Point(1344, 3376)
    elseif l == 0x02
        Point(1344, 1648)
    elseif l == 0x03
        Point(4224, 1360)
    elseif l == 0x04
        Point(5824, 2536)
    elseif l == 0x05
        Point(4224, 3664)
    elseif l == 0x06
        Point(3104, 2512)
    elseif l == 0x07
        Point(3264, 5104)
    elseif l == 0x08
        Point(1504, 6256)
    elseif l == 0x09
        Point(704, 912)
    elseif l == 0x0A
        Point(4224, 2512)
    elseif l == 0x0B
        Point(0, 0)
    elseif l == 0x0C
        Point(1504, 3952)
    elseif l == 0x0D
        Point(1504, 2224)
    elseif l == 0x0E
        Point(1984, 1776)
    elseif l == 0x0F
        Point(2784, 1488)
    elseif l == 0x10
        Point(4384, 1936)
    elseif l == 0x11
        Point(4384, 3088)
    elseif l == 0x12
        Point(3904, 2640)
    elseif l == 0x13
        Point(4864, 2640)
    elseif l == 0x14
        Point(4864, 1488)
    elseif l == 0x15
        Point(5824, 1488)
    elseif l == 0x16
        Point(4864, 3792)
    elseif l == 0x17
        Point(5824, 2928)
    elseif l == 0x18
        Point(5184, 4656)
    elseif l == 0x19
        Point(4864, 4656)
    elseif l == 0x1A
        Point(3904, 5232)
    elseif l == 0x1B
        Point(2464, 2640)
    elseif l == 0x1C
        Point(2464, 2928)
    elseif l == 0x1D
        Point(2464, 5232)
    elseif l == 0x1E
        Point(3424, 5680)
    elseif l == 0x1F
        Point(1824, 6256)
    elseif l == 0x20
        Point(1504, 4816)
    elseif l == 0x21
        Point(704, 3504)
    elseif l == 0x22
        Point(704, 1200)
    elseif l == 0x23
        Point(4384, 784)
    elseif l == 0x24
        Point(4704, 784)
    elseif l == 0x25
        Point(1344, 4496)
    elseif l == 0x26
        Point(1184, 4496)
    elseif l == 0x27
        Point(1856, 4496)
    elseif l == 0x28
        Point(1856, 4656)
    elseif l == 0x29
        Point(2016, 3824)
    elseif l == 0x2A
        Point(2016, 3644)
    elseif l == 0x2B
        Point(0, 0)
    elseif l == 0x2C
        Point(1344, 3216)
    elseif l == 0x2D
        Point(2016, 3344)
    elseif l == 0x2E
        Point(1856, 2224)
    elseif l == 0x2F
        Point(1312, 2432)
    elseif l == 0x30
        Point(1856, 2384)
    elseif l == 0x31
        Point(1312, 2736)
    elseif l == 0x32
        Point(1312, 2896)
    elseif l == 0x33
        Point(1856, 2544)
    elseif l == 0x34
        Point(1408, 1488)
    elseif l == 0x35
        Point(1408, 1328)
    elseif l == 0x36
        Point(1152, 1712)
    elseif l == 0x37
        Point(1920, 1488)
    elseif l == 0x38
        Point(1769, 1488)
    elseif l == 0x39
        Point(1184, 2000)
    elseif l == 0x3A
        Point(1248, 2256)
    elseif l == 0x3B
        Point(2848, 880)
    elseif l == 0x3C
        Point(2368, 880)
    elseif l == 0x3D
        Point(1696, 880)
    elseif l == 0x3E
        Point(4736, 1200)
    elseif l == 0x3F
        Point(4224, 1184)
    elseif l == 0x40
        Point(4896, 1328)
    elseif l == 0x41
        Point(4896, 1808)
    elseif l == 0x42
        Point(4224, 1968)
    elseif l == 0x43
        Point(4736, 1968)
    elseif l == 0x44
        Point(2528, 1456)
    elseif l == 0x45
        Point(4736, 1200)
    elseif l == 0x46
        Point(4224, 2352)
    elseif l == 0x47
        Point(4064, 1936)
    elseif l == 0x48
        Point(4224, 2160)
    elseif l == 0x49
        Point(4736, 3120)
    elseif l == 0x4A
        Point(3744, 2352)
    elseif l == 0x4B
        Point(3744, 2352)
    elseif l == 0x4C
        Point(4096, 2960)
    elseif l == 0x4D
        Point(3936, 2960)
    elseif l == 0x4E
        Point(3936, 2960)
    elseif l == 0x4F
        Point(4896, 2960)
    elseif l == 0x50
        Point(5408, 3088)
    elseif l == 0x51
        Point(5568, 1808)
    elseif l == 0x52
        Point(6176, 1712)
    elseif l == 0x53
        Point(5696, 880)
    elseif l == 0x54
        Point(5632, 4112)
    elseif l == 0x55
        Point(4896, 3632)
    elseif l == 0x56
        Point(5472, 4144)
    elseif l == 0x57
        Point(6176, 3152)
    elseif l == 0x58
        Point(5376, 624)
    elseif l == 0x59
        Point(4128, 3504)
    elseif l == 0x5A
        Point(4064, 3761)
    elseif l == 0x5B
        Point(4736, 3504)
    elseif l == 0x5C
        Point(4032, 3920)
    elseif l == 0x5D
        Point(4896, 4112)
    elseif l == 0x5E
        Point(6176, 4368)
    elseif l == 0x5F
        Point(6206, 4670)
    elseif l == 0x60
        Point(6206, 5118)
    elseif l == 0x61
        Point(5824, 5264)
    elseif l == 0x62
        Point(6366, 5022)
    elseif l == 0x63
        Point(5472, 5200)
    elseif l == 0x64
        Point(5920, 4976)
    elseif l == 0x65
        Point(6848, 5040)
    elseif l == 0x66
        Point(6256, 4752)
    elseif l == 0x67
        Point(6256, 5136)
    elseif l == 0x68
        Point(6368, 4912)
    elseif l == 0x69
        Point(0, 0)
    elseif l == 0x6A
        Point(0, 0)
    elseif l == 0x6B
        Point(0, 0)
    elseif l == 0x6C
        Point(352, 1424)
    elseif l == 0x6D
        Point(0, 0)
    elseif l == 0x6E
        Point(0, 0)
    elseif l == 0x6F
        Point(0, 0)
    elseif l == 0x70
        Point(0, 0)
    elseif l == 0x71
        Point(288, 336)
    elseif l == 0x72
        Point(0, 0)
    elseif l == 0x73
        Point(0, 0)
    elseif l == 0x74
        Point(0, 0)
    elseif l == 0x75
        Point(0, 0)
    elseif l == 0x76
        Point(288, 24)
    elseif l == 0x77
        Point(3920, 1840)
    elseif l == 0x78
        Point(320, 176)
    elseif l == 0x79
        Point(4736, 3248)
    elseif l == 0x7A
        Point(3136, 2352)
    elseif l == 0x7B
        Point(3136, 2192)
    elseif l == 0x7C
        Point(3136, 2032)
    elseif l == 0x7D
        Point(3136, 1872)
    elseif l == 0x7E
        Point(2432, 2096)
    elseif l == 0x7F
        Point(3040, 2320)
    elseif l == 0x80
        Point(3488, 2288)
    elseif l == 0x81
        Point(3488, 2064)
    elseif l == 0x82
        Point(3488, 1840)
    elseif l == 0x83
        Point(3648, 1968)
    elseif l == 0x84
        Point(3776, 1808)
    elseif l == 0x85
        Point(3680, 2192)
    elseif l == 0x86
        Point(2912, 2960)
    elseif l == 0x87
        Point(3136, 3280)
    elseif l == 0x88
        Point(2784, 2096)
    elseif l == 0x89
        Point(3488, 3120)
    elseif l == 0x8A
        Point(3296, 3120)
    elseif l == 0x8B
        Point(3680, 3120)
    elseif l == 0x8C
        Point(3840, 3120)
    elseif l == 0x8D
        Point(5568, 2480)
    elseif l == 0x8E
        Point(6176, 2448)
    elseif l == 0x8F
        Point(6528, 2448)
    elseif l == 0x90
        Point(6528, 2768)
    elseif l == 0x91
        Point(6528, 3088)
    elseif l == 0x92
        Point(6528, 3408)
    elseif l == 0x93
        Point(6528, 3728)
    elseif l == 0x94
        Point(6528, 4048)
    elseif l == 0x95
        Point(6176, 2928)
    elseif l == 0x96
        Point(6176, 2768)
    elseif l == 0x97
        Point(5664, 2960)
    elseif l == 0x98
        Point(3296, 4944)
    elseif l == 0x99
        Point(3264, 5712)
    elseif l == 0x9A
        Point(3776, 5712)
    elseif l == 0x9B
        Point(3936, 5552)
    elseif l == 0x9C
        Point(4160, 7056)
    elseif l == 0x9D
        Point(3072, 5552)
    elseif l == 0x9E
        Point(3552, 4944)
    elseif l == 0x9F
        Point(2528, 6576)
    elseif l == 0xA0
        Point(2528, 6896)
    elseif l == 0xA1
        Point(2016, 6896)
    elseif l == 0xA2
        Point(2016, 6576)
    elseif l == 0xA3
        Point(3968, 3600)
    elseif l == 0xA4
        Point(4128, 5552)
    elseif l == 0xA5
        Point(992, 6032)
    elseif l == 0xA6
        Point(1856, 5936)
    elseif l == 0xA7
        Point(1152, 6576)
    elseif l == 0xA8
        Point(1088, 6736)
    elseif l == 0xA9
        Point(1280, 6736)
    elseif l == 0xAA
        Point(1504, 6736)
    elseif l == 0xAB
        Point(1504, 6576)
    elseif l == 0xAC
        Point(1760, 6576)
    elseif l == 0xAD
        Point(1760, 6576)
    elseif l == 0xAE
        Point(736, 688)
    elseif l == 0xAF
        Point(4064, 2320)
    elseif l == 0xB0
        Point(4064, 2160)
    elseif l == 0xB1
        Point(4736, 2288)
    elseif l == 0xB2
        Point(4928, 2288)
    elseif l == 0xB3
        Point(4064, 2480)
    elseif l == 0xB4
        Point(4736, 2128)
    elseif l == 0xB5
        Point(5024, 5552)
    elseif l == 0xB6
        Point(4128, 3120)
    elseif l == 0xB7
        Point(5024, 2960)
    elseif l == 0xB8
        Point(4000, 5040)
    elseif l == 0xB9
        Point(4160, 5072)
    elseif l == 0xBA
        Point(2720, 2384)
    elseif l == 0xBB
        Point(2880, 2480)
    elseif l == 0xBC
        Point(2528, 2480)
    elseif l == 0xBD
        Point(6176, 4048)
    elseif l == 0xBE
        Point(2976, 5040)
    elseif l == 0xBF
        Point(2816, 5056)
    elseif l == 0xC0
        Point(2528, 5936)
    elseif l == 0xC1
        Point(512, 3472)
    elseif l == 0xC2
        Point(192, 1744)
    elseif l == 0xC3
        Point(6368, 3152)
    elseif l == 0xC4
        Point(4224, 3345)
    elseif l == 0xC5
        Point(4192, 4272)
    elseif l == 0xC6
        Point(192, 2064)
    elseif l == 0xC7
        Point(2816, 3600)
    elseif l == 0xC8
        Point(3328, 3600)
    elseif l == 0xC9
        Point(3328, 4080)
    elseif l == 0xCA
        Point(2816, 4080)
    elseif l == 0xCB
        Point(3840, 3920)
    elseif l == 0xCC
        Point(0, 0)
    elseif l == 0xCD
        Point(0, 0)
    elseif l == 0xCE
        Point(0, 0)
    elseif l == 0xCF
        Point(5024, 5872)
    elseif l == 0xD0
        Point(5024, 6192)
    elseif l == 0xD1
        Point(5024, 6512)
    elseif l == 0xD2
        Point(5536, 6512)
    elseif l == 0xD3
        Point(5536, 6192)
    elseif l == 0xD4
        Point(5536, 5872)
    elseif l == 0xD5
        Point(5536, 5552)
    elseif l == 0xD6
        Point(992, 5552)
    elseif l == 0xD7
        Point(992, 5232)
    elseif l == 0xD8
        Point(480, 6032)
    elseif l == 0xD9
        Point(4480, 6416)
    elseif l == 0xDA
        Point(3808, 6000)
    elseif l == 0xDB
        Point(3456, 6608)
    elseif l == 0xDC
        Point(3968, 6600)
    elseif l == 0xDD
        Point(4480, 6896)
    elseif l == 0xDE
        Point(3296, 6576)
    elseif l == 0xDF
        Point(3296, 6736)
    elseif l == 0xE0
        Point(4832, 6256)
    elseif l == 0xE1
        Point(4320, 5840)
    elseif l == 0xE2
        Point(3552, 528)
    elseif l == 0xE3
        Point(3552, 1168)
    elseif l == 0xE4
        Point(3552, 848)
    elseif l == 0xE5
        Point(5664, 3120)
    elseif l == 0xE6
        Point(4064, 1328)
    elseif l == 0xE7
        Point(0, 0)
    elseif l == 0xE8
        Point(6368, 1104)
    elseif l == 0xE9
        Point(6048, 5872)
    elseif l == 0xEA
        Point(6048, 6192)
    elseif l == 0xEB
        Point(6048, 6512)
    elseif l == 0xEC
        Point(5328, 5456)
    elseif l == 0xED
        Point(0, 0)
    elseif l == 0xEE
        Point(0, 0)
    elseif l == 0xEF
        Point(0, 0)
    elseif l == 0xF0
        Point(0, 0)
    elseif l == 0xF1
        Point(0, 0)
    elseif l == 0xF2
        Point(0, 0)
    elseif l == 0xF3
        Point(0, 0)
    elseif l == 0xF4
        Point(0, 0)
    elseif l == 0xF5
        Point(800, 464)
    elseif l == 0xF6
        Point(800, 240)
    elseif l == 0xF7
        Point(800, 16)
    else
        throw("Unknown location")
    end
end

function position_to_pixels(pos::Position)::Point
    # origin + offset + circle centering
    location_to_pixels(pos.location) + Point(pos.x*16, pos.y*16) + Point(8, 8)
end

struct BoundingBox
    top::Int
    left::Int
    bottom::Int
    right::Int
end

expand(bb::BoundingBox, p::Point, padding::Int=8)::BoundingBox = BoundingBox(min(bb.top, p.y-padding),
                                                                             min(bb.left, p.x-padding),
                                                                             max(bb.bottom, p.y+padding),
                                                                             max(bb.right, p.x+padding))

width(bb::BoundingBox) = bb.right - bb.left
height(bb::BoundingBox) = bb.bottom - bb.top

function render(js::Vector{Journey}, globe::Navmesh, batchnum::Int, basedir::String, bb::BoundingBox=BoundingBox(7200, 7200, 0, 0))::BoundingBox
    # map source: https://blog.vjeux.com/2023/project/pokemon-red-blue-map.html

    bg = readpng(joinpath(@__DIR__, "..", "map.png"))
    outdir = joinpath(basedir, "batch.$(lpad(batchnum, 3, '0'))")
    mkdir(outdir)

    @showprogress desc = "Rendering Frames" color=:blue  offset=1 for i in 1:200:maximum(length, js)
        for j in js
            i > length(j) && continue
            p = position_to_pixels(j[i].position)
            bb = expand(bb, p, 8)
        end

        relativeorigin = Point(-bb.left, -bb.top)
        Drawing(width(bb), height(bb), joinpath(outdir, "frame.$(lpad(i,8,'0')).png"))
        background("white")
        placeimage(bg, relativeorigin)
        setcolor("orange")
        for j in js
            i > length(j) && continue

            orientation = 0
            if j[i].orientation == Right
                orientation = 0
            elseif j[i].orientation == Down
                orientation = pi/2
            elseif j[i].orientation == Left
                orientation = 2pi
            elseif j[i].orientation == Up
                orientation = 3pi/2
            end

            ngon(position_to_pixels(j[i].position) + relativeorigin, 8, 3, orientation)
            do_action(:fill)
        end
        finish()
    end

    # Render Heatmap
    relativeorigin = Point(-bb.left, -bb.top)
    Drawing(width(bb), height(bb), joinpath(outdir, "heatmap.png"))
    background("white")
    placeimage(bg, relativeorigin)

    for l in labels(globe)
        o = outdegree(globe, code_for(globe, l))
        if o == 0
            setcolor("white")
        elseif o == 1
            setcolor("red")
        elseif o == 2
            setcolor("orange")
        elseif o == 3
            setcolor("yellow")
        elseif o == 4
            setcolor("green")
        elseif o == 5
            setcolor("blue")
        elseif o == 6
            setcolor("purple")
        else
            setcolor("black")
        end

        try
            ngon(position_to_pixels(l) + relativeorigin, 8, 8)
            do_action(:fill)
        catch
        end
    end
    finish()

    bb
end



export explore, checkkeylocations

end # module PokemonCartographer
