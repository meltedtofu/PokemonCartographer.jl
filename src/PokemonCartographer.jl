module PokemonCartographer

# using distributed pump out requests to run a rom with a save state for x frames and collect the results.
# Sticking with a single computer for now, but should be easy enough to go wider when we get there
# (local distributed for now) (figure out shared filesystem with something like sshfs)

function dothething()
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
end

end # module PokemonCartographer
