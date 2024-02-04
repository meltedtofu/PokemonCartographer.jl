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

    Job(romname, savename, duration, emulator0) = new(romname, savename, duration, emulator0)
end

function dojob(job::Job; imageprefix::Union{String,Nothing}=nothing)::Navmesh
    nav = Navmesh()
    statenum = 1
    lastpos = GameState().position
    button = nothing

    gb = deepcopy(job.emulator0)

    for i in 1:job.duration
        pixels = doframe!(gb)
        game = GameState(gb, pixels)
        buttonstate!(gb, ButtonA,     true)
        buttonstate!(gb, ButtonB,     true)
        buttonstate!(gb, ButtonUp,    true)
        buttonstate!(gb, ButtonDown,  true)
        buttonstate!(gb, ButtonLeft,  true)
        buttonstate!(gb, ButtonRight, true)

        if statenum == 1 # Haven't loaded the game yet keep smashing A
            if game.position == (0x00, 0x00, 0x00) || !isnothing(game.menu)
                buttonstate!(gb, ButtonA, i%2 == 0)
            else
                statenum = 2
            end
        elseif statenum == 2 # Unclear why this delay is needed. Just going with it for now.
            if i < 30*60
                buttonstate!(gb, ButtonA, i%2 == 0)
            else
                statenum = 3
            end
        elseif statenum == 3
            if i%3 == 0
                button = rand([ButtonUp, ButtonDown, ButtonLeft, ButtonRight])
                buttonstate!(gb, button, false)
            elseif lastpos != game.position &&!isnothing(button)
                Navmesh!(nav, Position(lastpos), Position(game.position), asdirection(button))
                lastpos = game.position
            end
        end
    end

    if !isnothing(imageprefix)
        pixels = doframe!(gb)
        save(File{format"PNG"}("$imageprefix.end.png"), reinterpret(BGRA{N0f8}, pixels))
    end

    nav
end

"""
Create a Navmesh by playing the game.

Starting with a list of roms and save states, spawn a worker for each pair and merge the resulting navmeshes.
"""
function dothething()::Navmesh
    roms = ["POKEMON BLUE.gb", "POKEMON RED.gb"] .|> r -> joinpath(@__DIR__, "..", "roms", r)

    saves = walkdir(joinpath(@__DIR__, "..", "saves")) .|>
            (listing -> map(f -> joinpath(first(listing), f), last(listing))) |>
            Base.Fix1(reduce, vcat) |>
            Base.Fix1(filter, f -> !contains(f, "DS_Store"))

    duration = 10*60*60

    prog = Progress(length(roms) * duration; desc="Exploring...", color=:yellow)

    jobs = []
    for r in roms
        for s in saves
            gb = Emulator(r)
            sav = Vector{UInt8}(undef, 2^15)
            open("$r.sav") do io
                readbytes!(io, sav)
            end
            ram!(gb, sav)

            push!(jobs, Job(r, s, duration, gb))
        end
    end

    globe = @showprogress desc="Exploring..." color=:blue @distributed (Navmesh) for j in jobs
        dojob(j)
    end

    @info length(labels(globe))

    globe
end

end # module PokemonCartographer
