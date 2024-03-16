module PokemonCartographer

using GameBoy

using ProgressMeter
using Random
using MetaGraphsNext: labels
using Distributed

include("Nav.jl")
using .Nav

include("render/Render.jl")
include("Worker.jl")
using .Worker

"""
Generate a batch of jobs to run
"""
function genbatch(roms::Vector{String}, duration::Int, counter::Int, globe::Navmesh, nogo::Vector{Position}; copies::Int=1)::Vector{Job}
    # TODO: Make this more functional instead of manually pushing to a vector
    jobs = []
    for _ in 1:copies
        for r in roms
            gb = Emulator(r)
            push!(jobs, Job(r, duration, gb, nothing, deepcopy(globe), nogo))
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
    nogolist = [Position(0x00, 0x00, 0x00)]
    renderingbb = Render.BoundingBox(7200, 7200, 0, 0)
    duration = duration_min*60*60

    prog = ProgressThresh(0.1; desc="Exploring...", color=:blue)
    update!(prog, target)

    jobqueue = RemoteChannel(() -> Channel{Job}(50))
    resultqueue = RemoteChannel(() -> Channel{JobResult}(50))
    submit_job(j) = put!(jobqueue, j)

    foreach(pid -> remote_do(dojobs, pid, jobqueue, resultqueue), workers())

    scores = []

    while length(labels(globe)) < target
        jobs = genbatch(roms, duration, jobcounter, globe, nogolist; copies=copies)
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
        union!(nogolist, jrs.nogolist)
        renderingbb = Render.render(jrs.journeys, globe, batchcounter, animdir, renderingbb, nogolist)

        update!(prog, target - length(labels(globe)))

        push!(scores, length(labels(globe)))

        if batchcounter > 3 && diff(scores)[end-2:end] |> iszero 
            nogolist = [Position(0x00, 0x00, 0x00)] # Stuck. Try clearing the nogolist to revisit these nodes
            @warn "Stuck. Clearing the nogolist and trying again."
        end

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
