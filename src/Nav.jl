module Nav

using Graphs
using MetaGraphsNext
using GameBoy: Button, ButtonUp, ButtonRight, ButtonDown, ButtonLeft

struct Position
    location::UInt8
    x::UInt8
    y::UInt8

    Position(l, x, y) = new(l, x, y)
    Position(p) = new(p...)
end

const nowhereup = Position(0xff, 0xff, 0xff)
const nowheredown = Position(0xff, 0xff, 0xfe)
const nowhereleft = Position(0xff, 0xff, 0xfd)
const nowhereright = Position(0xff, 0xff, 0xfc)

@enum Direction Up Right Down Left

function asbutton(d::Direction)::Button
    if d == Up
        ButtonUp
    elseif d == Right
        ButtonRight
    elseif d == Down
        ButtonDown
    elseif d == Left
        ButtonLeft
    end
end

function asdirection(b::Button)::Direction
    if b == ButtonUp
        Up
    elseif b == ButtonRight
        Right
    elseif b == ButtonDown
        Down
    elseif b == ButtonLeft
        Left
    end
end

function asdirection(facing::UInt8)::Direction
    if facing == 0x00
        Down
    elseif facing == 0x04
        Up
    elseif facing == 0x08
        Left
    elseif facing == 0x0c
        Right
    else
        throw("unknown direction $facing")
    end
end

function asnowhere(b::Button)::Position
    if b == ButtonUp    
        nowhereup
    elseif b == ButtonDown
        nowheredown
    elseif b == ButtonLeft
        nowhereleft
    elseif b == ButtonRight
        nowhereright
    end
end

asnowhere(d::Direction)::Position = asnowhere(asbutton(d))

asbutton(facing::UInt8) = facing |> asdirection |> asbutton

export Up, Right, Down, Left, asbutton, asdirection, asnowhere


struct Placement
    position::Position
    orientation::Direction
end

const Journey = Vector{Placement}

# Using type parameters to elide the unimportant implementation details of MetaGraphNext.
# Vertex representation in DiGraph (aka "Code"), Weight Function, Weight.
const Navmesh{C, Wf, W} = MetaGraph{C, Graphs.SimpleGraphs.SimpleDiGraph{C}, Position, Nothing, Direction, Nothing, Wf, W}

function Navmesh()::Navmesh
    n = MetaGraph(DiGraph();
                  vertex_data_type=Nothing,
                  label_type=Position,
                  edge_data_type=Direction)

    n[nowhereup] = nothing
    n[nowheredown] = nothing
    n[nowhereleft] = nothing
    n[nowhereright] = nothing

    n
end

function Navmesh!(n::Navmesh, from::Position, to::Position, d::Direction)::Nothing
    n[from] = nothing
    n[to] = nothing
    n[from, to] = d

    nothing
end

function Navmesh(a::Navmesh, b::Navmesh)::Navmesh
    n = Navmesh()

    for x in [a, b]
        for l in labels(x)
            n[l] = nothing
        end

        for el in edge_labels(x)
            n[el...] = x[el...]
        end
    end

    only_one_location_per_direction!(n)

    n
end

function Navmesh!(a0::Navmesh, a::Navmesh)::Nothing
    for l in labels(a)
        a0[l] = nothing
    end

    for el in edge_labels(a)
        a0[el...] = a[el...]
    end

    only_one_location_per_direction!(a0)

    nothing
end

function only_one_location_per_direction!(n::Navmesh)::Nothing
    for l in labels(n)
        outls = outneighbor_labels(n, l) |> collect
        up = 0
        down = 0
        left = 0
        right = 0

        for outl ∈ outls
            d = n[l, outl]
            if d == Up
                up += 1
            elseif d == Down
                down += 1
            elseif d == Left
                left += 1
            elseif d == Right
                right += 1
            end
        end

        if up > 1
            rem_edge!(n, l, nowhereup)
        end

        if down > 1
            rem_edge!(n, l, nowheredown)
        end

        if left > 1
            rem_edge!(n, l, nowhereleft)
        end

        if right > 1
            rem_edge!(n, l, nowhereright)
        end
    end

    nothing
end

Graphs.rem_edge!(n::Navmesh, from::Position, to::Position) = rem_edge!(n, code_for(n, from), code_for(n, to))

function route(n::Navmesh, from::Position, to::Position)::Vector{Direction}
    try
        Graphs.a_star(n,
                      code_for(n, from),
                      code_for(n, to)) |>
                          Base.Fix1(map, e -> n[label_for(n, e.src), label_for(n, e.dst)])
    catch e
        if isa(e, KeyError)
            return []
        else
            rethrow(e)
        end
    end
end

connected(n::Navmesh, from::Position, to::Position)::Bool = from == to || route(n, from, to) |> length > 0

# TODO: Render Navmesh as Matrix
# TODO: Render Navmesh as Ascii

"""
Select a random, incomplete vertex in the navmesh.
Incomplete vertices have less than four outedges - e.g. Up, Down, Left, Right.
"""
function randomincomplete(n::Navmesh, nogolist::Vector{Position})::Union{Position, Nothing}
    # TODO: provide a list of positions to filter as an optional function argument. This way the caller can figure control the search process.
    threshold = (n |> Graphs.outdegree .|> d -> clamp(d, 0, 4)) |> minimum
    selected = randomincomplete(n, threshold, nogolist)
    if isnothing(selected) && threshold < 4
        randomincomplete(n, threshold + 1, nogolist)
    else
        selected
    end
end

function randomincomplete(n::Navmesh, threshold::Int, nogolist::Vector{Position}=[Position(0x00, 0x00, 0x00)])::Union{Position, Nothing}
    try
        (n |>
            Graphs.outdegree |>
            Base.Fix1(findall, deg -> deg <= threshold) .|>
            i-> label_for(n, i)) |>
        collect |>
        Base.Fix1(filter, p -> p ∉ nogolist && p.location != 0xff && p.location != 0x28) |>
        rand
    catch e
        nothing
    end
end

exploreddirections(n::Navmesh, p::Position)::Vector{Direction} = unique([n[p, l] for l in outneighbor_labels(n, p)])

function goesnowhere(n::Navmesh, p::Position, d::Direction)::Bool
    try
        has_vertex(n, code_for(n, p)) && has_edge(n, code_for(n, p), code_for(n, asnowhere(d)))
    catch e
        false
    end
end

goesnowhere(n::Navmesh, p::Position, b::Button) = goesnowhere(n, p, asdirection(b))

function goessomewhere(n::Navmesh, p::Position, d::Direction)::Bool
    try
        has_vertex(n, code_for(n, p)) && d ∈ exploreddirections(n, p) && !has_edge(n, code_for(n, p), code_for(n, asnowhere(asbutton(d))))
    catch e
        false
    end
end

goessomewhere(n::Navmesh, p::Position, b::Button) = goessomewhere(n, p, asdirection(b))


export Navmesh, Direction, Position, Journey, Placement, route, connected, Navmesh!, goesnowhere, goessomewhere, randomincomplete, exploreddirections

end # module Nav
