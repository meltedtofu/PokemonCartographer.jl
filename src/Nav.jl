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
        Down
    end
end

asbutton(facing::UInt8) = facing |> asdirection |> asbutton

export Up, Right, Down, Left, asbutton, asdirection

# Using type parameters to elide the unimportant implementation details of MetaGraphNext.
# Vertex representation in DiGraph (aka "Code"), Weight Function, Weight.
const Navmesh{C, Wf, W} = MetaGraph{C, Graphs.SimpleGraphs.SimpleDiGraph{C}, Position, Nothing, Direction, Nothing, Wf, W}

function Navmesh()::Navmesh
    MetaGraph(DiGraph();
              vertex_data_type=Nothing,
              label_type=Position,
              edge_data_type=Direction)
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

    n
end

function Navmesh!(a0::Navmesh, a::Navmesh)::Nothing
    for l in labels(a)
        a0[l] = nothing
    end

    for el in edge_labels(a)
        a0[el...] = a[el...]
    end

    nothing
end

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
function randomincomplete(n::Navmesh)::Union{Position, Nothing}
    try
        threshold = (n |> Graphs.outdegree .|> d -> clamp(d, 1, 3)) |> minimum
        (n |>
            Graphs.outdegree |>
            Base.Fix1(findall, deg -> deg <= threshold) .|>
            i-> label_for(n, i)) |>
        collect |>
        Base.Fix1(filter, p -> p != Position(0x00, 0x00, 0x00) && p.location != 0xff) |>
        rand
    catch e
        nothing
    end
end

export Navmesh, Direction, Position, route, connected, Navmesh!, nowhereup, nowheredown, nowhereleft, nowhereright, randomincomplete

end # module Nav
