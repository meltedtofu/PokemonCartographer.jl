module Render

using Luxor
using ProgressMeter
using MetaGraphsNext: labels, code_for, outdegree, outneighbor_labels
using ..Nav

include("locations.jl")

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

function render(js::Vector{Journey}, globe::Navmesh, batchnum::Int, basedir::String, bb::BoundingBox=BoundingBox(7200, 7200, 0, 0), nogolist::Vector{Position}=[]; renderjourneys::Bool=false)::BoundingBox
    # map source: https://blog.vjeux.com/2023/project/pokemon-red-blue-map.html

    bg = readpng(joinpath(@__DIR__, "map.png"))
    outdir = joinpath(basedir, "batch.$(lpad(batchnum, 3, '0'))")
    mkpath(outdir)

    gap = 200
    #gap = 1
    @showprogress desc = "Rendering Frames" color=:blue  offset=1 for i in 1:gap:maximum(length, js)
        for j in js
            i > length(j) && continue
            p = position_to_pixels(j[i].position)
            bb = expand(bb, p, 8)
        end

        if renderjourneys
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
    end

    # Render Heatmap
    heatmapdir = joinpath(basedir, "heatmap")
    mkpath(heatmapdir)
    relativeorigin = Point(-bb.left, -bb.top)
    Drawing(width(bb), height(bb), joinpath(heatmapdir, "heatmap.$(lpad(batchnum,3,'0')).png"))
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

        if l ∈ nogolist
            setcolor("black")
        end

        try
            ngon(position_to_pixels(l) + relativeorigin, 8, 8)
            do_action(:fill)
        catch
        end
    end

    setcolor("black")
    for l in labels(globe)
        for o in outneighbor_labels(globe, l)
            try
                arrow(position_to_pixels(l) + relativeorigin, position_to_pixels(o) + relativeorigin; arrowheadlength=5)
            catch
            end
        end
    end
    finish()

    bb
end

export BoundingBox, render

end # module Render