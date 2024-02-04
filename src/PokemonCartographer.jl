module PokemonCartographer

using GameBoy
using PokemonObserver

using FileIO
using Images
using ProgressMeter
using Random
using MetaGraphsNext: labels

include("Nav.jl")
using .Nav

# using distributed pump out requests to run a rom with a save state for x frames and collect the results.
# Sticking with a single computer for now, but should be easy enough to go wider when we get there
# (local distributed for now) (figure out shared filesystem with something like sshfs)

function dothething()::Nothing
    # Given a library of roms
    # and a collection of save states
    # Produce a "job" to
    #   - run a rom
    #   - from a save state
    #   - for x frames
    #   - and send each back to a channel

    # This is essentially a map-reduce problem
    #   map a rom+save into a series of frames -> reduce series of frames into one stitched image per location.

    # Going one level deeper
    #   - array of roms + saves (static for now, eventually dynamically produced)
    #       - rom + save -> produce series of frames (every frame that is in the overworld)
    #       - group frames by "location" (n locations x m frames)
    #       - for each group of frames, stitch together a larger image (n locations x 1 image)
    #   - array of (location + image)
    #   - group by location again -> Dict{Location}{Vector{Image}}
    #       - stitch together all frames in a location
    #   - Dict{Location}{Image}

    # or in terms of types
    # Job = Struct{Rom, Save, Duration}
    #
    # Vector{Jobs} -> Vector{Dict{Location, Image}} -> Dict{Location, Vector{Image}} -> Dict{Location, Image}
    #              / \
    #         ----     --------------------------------------------------------------------------
    #        |                                                                                   |
    #        Job -> Vector{Tuple{Location, Image}} -> Dict{Location, Vector{Image}} -> Dict{Location, Image}

    # Maybe ignore the image idea for now. The navmesh is the thing I actually want.
    # Sure, render the navmesh as an image, but that is a rendering step not a data step.
    # It should be an identical type pipeline as above, just replace "image" with "navmesh".

    # The pipeline described above is one "batch" of work.
    # Additional batches should be created to continue exploring until "enough" of the world has been discovered.

    roms = ["POKEMON BLUE.gb", "POKEMON RED.gb"] .|> r -> joinpath(@__DIR__, "..", "roms", r)

    runduration = 10*60*60

    prog = Progress(length(roms) * duration; desc="Exploring...", color=:yellow)

    globe = Navmesh()

    for (i, r) in enumerate(roms)
        gb = Emulator(r)
        nav = Navmesh()

        sav = Vector{UInt8}(undef, 2^15)
        open("$r.sav") do io
            readbytes!(io, sav)
        end
        ram!(gb, sav)

        statenum = 1
        lastpos = GameState().position
        button = nothing
        for j in 1:duration
            pixels = doframe!(gb)
            game = GameState(gb, pixels)
            buttonstate!(gb, ButtonA,     true)
            buttonstate!(gb, ButtonB,     true)
            buttonstate!(gb, ButtonUp,    true)
            buttonstate!(gb, ButtonDown,  true)
            buttonstate!(gb, ButtonLeft,  true)
            buttonstate!(gb, ButtonRight, true)
            #save(File{format"PNG"}("asdf.$i.$(lpad(j, 4, '0')).png"), reinterpret(BGRA{N0f8}, pixels))

            if statenum == 1 # Haven't loaded the game yet keep smashing A
                if game.position == (0x00, 0x00, 0x00) || !isnothing(game.menu)
                    buttonstate!(gb, ButtonA, j%2 == 0)
                else
                    statenum = 2
                end
            elseif statenum == 2 # Unclear why this delay is needed. Just going with it for now.
                if j < 30*60
                    buttonstate!(gb, ButtonA, j%2 == 0)
                else
                    statenum = 3
                end
            elseif statenum == 3
                if j%3 == 0
                    button = rand([ButtonUp, ButtonDown, ButtonLeft, ButtonRight])
                    buttonstate!(gb, button, false)
                elseif lastpos != game.position &&!isnothing(button)
                    Navmesh!(nav, Position(lastpos), Position(game.position), asdirection(button))
                    lastpos = game.position
                end
            end

            next!(prog)
        end

        pixels = doframe!(gb)
        save(File{format"PNG"}("asdf.$i.end.png"), reinterpret(BGRA{N0f8}, pixels))
        globe = Navmesh(globe, nav)
    end

    @info length(labels(globe))

    nothing
end

end # module PokemonCartographer
