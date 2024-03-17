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

# "nowhere" are special locations which are not traversable and will never have out edges.
# The navmesh graph contains one edge per pair of locations.
# We need one "nowhere" for each possible direction from a location.
const nowhereup = Position(0xff, 0xff, 0xff)
const nowheredown = Position(0xff, 0xff, 0xfe)
const nowhereleft = Position(0xff, 0xff, 0xfd)
const nowhereright = Position(0xff, 0xff, 0xfc)

@enum Direction Up Right Down Left

"""
    asbutton(d::Direction)::Button

Convert directions to buttons.

# Examples
```jldoctest
asbutton(Up)

# output

ButtonUp::Button = 64
```
"""
function asbutton(d::Direction)::Button
    if d == Up
        ButtonUp
    elseif d == Right
        ButtonRight
    elseif d == Down
        ButtonDown
    elseif d == Left
        ButtonLeft
    else
        @assert false "Unknown direction $d"
    end
end

"""
    asdirection(b::Button)::Direction

Convert buttons to directions.

# Examples
```jldoctest
asdirection(ButtonUp)

# output

Up::Direction = 0
```
"""
function asdirection(b::Button)::Direction
    if b == ButtonUp
        Up
    elseif b == ButtonRight
        Right
    elseif b == ButtonDown
        Down
    elseif b == ButtonLeft
        Left
    else
        @assert false "Unknown button $b"
    end
end

"""
    asdirection(facing::UInt8)::Direction

convert facing byte to direction

# Examples
```jldoctest
asdirection(0x04)

# output

Up::Direction = 0
```
"""
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
        @assert false "Unknown facing $facing"
    end
end

"""
    asnowhere(b::Button)::Position

Find the correct nowhere location.
"""
function asnowhere(b::Button)::Position
    if b == ButtonUp    
        nowhereup
    elseif b == ButtonDown
        nowheredown
    elseif b == ButtonLeft
        nowhereleft
    elseif b == ButtonRight
        nowhereright
    else
        @assert false "Unknown button $b"
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

"""
    Navmesh()::Navmesh

Create a new Navmesh.

Includes the `nowhere`s as a fully connected graph.
This way the `nowhere`s always exist and are considered "fully explored"(.)
"""
function Navmesh()::Navmesh
    n = MetaGraph(DiGraph();
                  vertex_data_type=Nothing,
                  label_type=Position,
                  edge_data_type=Direction)

    n[nowhereup] = nothing
    n[nowheredown] = nothing
    n[nowhereleft] = nothing
    n[nowhereright] = nothing

    n[nowhereup, nowheredown]  = Up
    n[nowhereup, nowhereup]    = Up
    n[nowhereup, nowhereleft]  = Up
    n[nowhereup, nowhereright] = Up

    n[nowheredown, nowheredown]  = Down
    n[nowheredown, nowhereup]    = Down
    n[nowheredown, nowhereleft]  = Down
    n[nowheredown, nowhereright] = Down

    n[nowhereleft, nowheredown]  = Left
    n[nowhereleft, nowhereup]    = Left
    n[nowhereleft, nowhereleft]  = Left
    n[nowhereleft, nowhereright] = Left

    n[nowhereright, nowheredown]  = Right
    n[nowhereright, nowhereup]    = Right
    n[nowhereright, nowhereleft]  = Right
    n[nowhereright, nowhereright] = Right
    
    n
end

"""
    Navmesh!(n::Navmesh, from::Position, to::Position, d::Direction)::Nothing

Add an edge in `n` between `from` and `to` labeled as direction `d`.

`from` and `to` do not need to exist.

This will overwrite any previous edge between these two nodes.
"""
function Navmesh!(n::Navmesh, from::Position, to::Position, d::Direction)::Nothing
    n[from] = nothing
    n[to] = nothing
    n[from, to] = d

    nothing
end

"""
    Navmesh(a::Navmesh, b::Navmesh)::Navmesh

Merge two `Navmesh`es - `a` and `b` - into a new `Navmesh`.

Prioritizes edges to somewhere over edges to nowhere when resolving conflicts.
"""
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

"""
    Navmesh!(a0::Navmesh, a::Navmesh)::Nothing

Merge `a` into `a0` in place. See `Navmesh(a::Navmesh, b::Navmesh)::Navmesh` for more details.
"""
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

"""
    route(n::Navmesh, from::Position, to::Position)::Vector{Direction}

Find a route between `from` and `to` in the provided Navmesh, `n`.

If no route exists an empty Vector will be returned instead.

# Examples
```jldoctest
n = Navmesh()

p1 = Position(0x01, 0x01, 0x01)
p2 = Position(0x01, 0x01, 0x02)
p3 = Position(0x01, 0x02, 0x02)
Navmesh!(n, p1, p2, Down)
Navmesh!(n, p2, p3, Right)

route(n, p1, p3)

# output

2-element Vector{Direction}:
 Down::Direction = 2
 Right::Direction = 1
```
"""
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

"""
    connected(n::Navmesh, from::Position, to::Position)::Bool

Predicate to check if two nodes are connected.

# Examples
```jldoctest
n = Navmesh()
p1 = Position(0x01, 0x01, 0x01)
p2 = Position(0x01, 0x01, 0x02)
p3 = Position(0x01, 0x02, 0x02)
Navmesh!(n, p1, p2, Down)
Navmesh!(n, p2, p3, Right)

connected(n, p1, p3)

# output

true
```
"""
connected(n::Navmesh, from::Position, to::Position)::Bool = from == to || route(n, from, to) |> length > 0

"""
    randomincomplete(n::Navmesh, nogolist::Vector{Position})::Union{Position, Nothing}

Select a random, incomplete vertex in the navmesh.
Incomplete vertices have less than four outedges - e.g. Up, Down, Left, Right.
"""
function randomincomplete(n::Navmesh, nogolist::Vector{Position})::Union{Position, Nothing}
    threshold = (n |> Graphs.outdegree .|> d -> clamp(d, 0, 4)) |> minimum
    selected = nothing
    while true
        selected = randomincomplete(n, threshold, nogolist)
        if !isnothing(selected)
            break
        elseif threshold >= 4
            break
        else
            threshold += 1
        end
    end

    selected
end

function randomincomplete(n::Navmesh, threshold::Int, nogolist::Vector{Position}=[Position(0x00, 0x00, 0x00)])::Union{Position, Nothing}
    try
        (n |>
            Graphs.outdegree |>
            Base.Fix1(findall, deg -> deg <= threshold) .|>
            i-> label_for(n, i)) |>
        collect |>
        Base.Fix1(filter, p -> p ∉ nogolist && p.location != 0xff) |>
        rand
    catch e
        nothing
    end
end

exploreddirections(n::Navmesh, p::Position)::Vector{Direction} = unique([n[p, l] for l in outneighbor_labels(n, p)])

"""
    goesnowhere(n::Navmesh, p::Position, d::Direction)::Bool

Predicate to check if a direction goes to nowhere.
"""
function goesnowhere(n::Navmesh, p::Position, d::Direction)::Bool
    try
        has_vertex(n, code_for(n, p)) && has_edge(n, code_for(n, p), code_for(n, asnowhere(d)))
    catch e
        false
    end
end

goesnowhere(n::Navmesh, p::Position, b::Button) = goesnowhere(n, p, asdirection(b))

"""
    goessomewhere(n::Navmesh, p::Position, d::Direction)::Bool

Predicate to check if a direction exists goes to somewhere.
"""
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
