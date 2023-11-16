# SPDX-FileCopyrightText: 2023 Christian Willberg <christian.willberg@dlr.de>, Jan-Timo Hesse <jan-timo.hesse@dlr.de>
#
# SPDX-License-Identifier: BSD-3-Clause

module Data_manager
using MPI

export check_properties
export create_bond_field
export create_constant_bond_field
export create_constant_node_field
export create_node_field
export get_all_field_keys
export get_block_list
export get_crit_values_matrix
export get_comm
export get_field
export get_field_type
export get_local_nodes
export get_nlist
export get_nnsets
export get_nsets
export get_nnodes
export get_physics_options
export get_properties
export get_property
export get_rank
export get_num_responder
export get_max_rank
export init_property
export set_block_list
export set_crit_values_matrix
export set_glob_to_loc
export set_num_controller
export set_nset
export set_num_responder
export set_physics_options
export set_property
export set_rank
export set_max_rank
export switch_NP1_to_N
export synch_manager
##########################
# Variables
##########################
global nnodes::Int64 = 0
global num_controller::Int64 = 0
global num_responder::Int64 = 0
global nnsets::Int64 = 0
global dof::Int64 = 1
global block_list::Vector{Int64} = []
global distribution::Vector{Int64}
global crit_values_matrix::Array{Float64,3}
global properties::Dict{Int64,Dict{String,Any}} = Dict()
global glob_to_loc::Dict{Int64,Int64}
global fields::Dict{DataType,Dict{String,Any}} = Dict(Int64 => Dict(), Float64 => Dict(), Bool => Dict())
global field_array_type::Dict{String,Dict{String,Any}} = Dict()
global field_types::Dict{String,DataType} = Dict()
global fields_to_synch::Dict{String,Any} = Dict()
global nsets::Dict{String,Vector{Int}} = Dict()
global overlap_map::Dict{Int64,Any}
global physics_options::Dict{String,Bool} = Dict("Deformed Bond Geometry" => true,
    "Deformation Gradient" => false,
    "Shape Tensor" => false,
    "Bond Associated Shape Tensor" => false,
    "Bond Associated Deformation Gradient" => false)
global rank::Int64 = 0
global commMPi::Any

function get_comm()
    global commMPi
    return commMPi
end
function set_comm(comm::MPI.Comm)
    global commMPi = comm
end
##########################
# Material information
##########################
global material_type::Dict{String,Bool} = Dict("Bond-Based" => false, "Ordinary" => false, "Correspondence" => true, "Bond-Associated" => false)
##########################

function check_property(block_id::Int64, property::String)
    global properties

    if haskey(properties[block_id], property)
        return length(properties[block_id][property]) > 0
    end
    return false
end

"""
   create_bond_field(name::String, type::Type, dof::Int64)

   Creates a bond field with the given name, data type, and degree of freedom.

   Parameters:
    - `name::String`: The name of the bond field.
    - `vartype::Type`: The data type of the bond field.
    - `dof::Int64`: The degrees of freedom per bond.
    - `VectorOrArray::String` (optional) - Vector or Materix; Default is vector

   Returns:
   - `bond_field::Field`: The created bond field for the current time step.
   - `bond_field_np1::Field`: The created bond field for the next time step.

   Example:
   ```julia
   create_bond_field("stress", Float64, 6)  # creates a stress bond field with 6 degrees of freedom
   ```
   """

function create_bond_field(name::String, type::Type, dof::Int64, default_value::Union{Int64,Float64,Bool}=0)

    return create_field(name * "N", type, "Bond_Field", dof, default_value), create_field(name * "NP1", type, "Bond_Field", dof, default_value)
end

function create_bond_field(name::String, type::Type, VectorOrArray::String, dof::Int64, default_value::Union{Int64,Float64,Bool}=0)

    return create_field(name * "N", type, "Bond_Field", VectorOrArray, dof, default_value), create_field(name * "NP1", type, "Bond_Field", VectorOrArray, dof, default_value)
end

"""
   create_constant_bond_field(name::String, type::Type, dof::Int64, default_value::Union{Int64,Float64,Bool}=0))

   Creates a constant bond field with the given name, data type, and degree of freedom.

   Parameters:
    - `name::String`: The name of the bond field.
    - `vartype::Type`: The data type of the bond field.
    - `dof::Int64`: The degrees of freedom per bond.
    -  default_value::Union{Int64,Float64,Bool}=0) (optional) - filled with zero or false

   Returns:
   - `constant_bond_field::Field`: The created constant bond field.

   Example:
   ```julia
   create_constant_bond_field("density", Float64, 1)  # creates a density constant bond field
   ```
   """
function create_constant_bond_field(name::String, type::Type, dof::Int64, default_value::Union{Int64,Float64,Bool}=0)
    return create_field(name, type, "Bond_Field", dof, default_value)
end

function create_constant_bond_field(name::String, type::Type, VectorOrArray::String, dof::Int64, default_value::Union{Int64,Float64,Bool}=0)
    return create_field(name, type, "Bond_Field", VectorOrArray, dof, default_value)
end

"""
create_constant_node_field(name::String, type::Type, dof::Int64)

Creates a constant node field with the given name, data type, and degree of freedom.

Parameters:
- `name::String`: The name of the node field.
- `vartype::Type`: The data type of the node field.
- `dof::Int64`: The degrees of freedom per node.
- `VectorOrArray::String` (optional) - Vector or Materix; Default is vector

Returns:
- `constant_node_field::Field`: The created constant node field.

Example:
```julia
create_constant_node_field("temperature", Float64, 1)  # creates a temperature constant node field
```
"""
function create_constant_node_field(name::String, type::Type, dof::Int64, default_value::Union{Int64,Float64,Bool}=0)

    return create_field(name, type, "Node_Field", dof, default_value)
end
function create_constant_node_field(name::String, type::Type, VectorOrArray::String, dof::Int64, default_value::Union{Int64,Float64,Bool}=0)

    return create_field(name, type, "Node_Field", VectorOrArray, dof, default_value)
end
"""
create_field(name::String, vartype::Type, bondNode::String, dof::Int64, default_value::Any=0)

Create a field with the given `name` for the specified `vartype`. If the field already exists, return the existing field. If the field does not exist, create a new field with the specified characteristics.

# Arguments
- `name::String`: The name of the field.
- `vartype::Type`: The data type of the field.
- `dof::Int64`: The degrees of freedom per node.
- `default_value::Any`: The default value of the field.

# Returns
The field with the given `name` and specified characteristics.

"""

function create_field(name::String, vartype::Type, bondOrNode::String, dof::Int64, default_value::Union{Int64,Float64,Bool})
    create_field(name, vartype, bondOrNode, "Vector", dof, default_value)
end

function create_field(name::String, vartype::Type, bondOrNode::String, VectorOrArray::String, dof::Int64, default_value::Union{Int64,Float64,Bool})
    global nnodes
    global num_controller
    global fields
    global field_array_type
    global field_types

    field_dof = dof
    if haskey(fields, vartype) == false
        fields[vartype] = Dict{String,Any}()
    end
    if name in get_all_field_keys()
        return get_field(name)
    end
    if VectorOrArray == "Matrix"
        field_dof *= dof
    end
    if bondOrNode == "Node_Field"
        if dof == 1
            fields[vartype][name] = fill(vartype(default_value), nnodes)
        else
            fields[vartype][name] = fill(vartype(default_value), nnodes, field_dof)
        end
    elseif bondOrNode == "Bond_Field"
        nBonds = get_field("Number of Neighbors")
        if dof == 1
            fields[vartype][name] = Vector{vartype}[]
        else
            fields[vartype][name] = Matrix{vartype}[]
        end
        for i in 1:num_controller+num_responder
            if dof == 1
                append!(fields[vartype][name], [Vector{vartype}(undef, nBonds[i])])
                fill!(fields[vartype][name][end], vartype(default_value))
            else
                append!(fields[vartype][name], [Matrix{vartype}(undef, nBonds[i], field_dof)])
                fill!(fields[vartype][name][end], vartype(default_value))
            end
        end
    end
    field_types[name] = vartype
    field_array_type[name] = Dict("Type" => VectorOrArray, "Dof" => dof)

    return get_field(name)
end
"""
   create_node_field(name::String, type::Type, dof::Int64)

   Creates a node field with the given name, data type, and degree of freedom.

   Parameters:
   - `name::String`: The name of the node field.
   - `type::Type`: The data type of the node field.
   - `dof::Int64`: The degree of freedom of each node.
   - `VectorOrArray::String` (optional) - Vector or Materix; Default is vector
   Returns:
   - `node_field::Field`: The created node field for the current time step.
   - `node_field_np1::Field`: The created node field for the next time step.

   Example:
   ```julia
   create_node_field("displacement", Float64, 3)  # creates a displacement node field with 3 degrees of freedom
   ```
"""
function create_node_field(name::String, type::Type, dof::Int64, default_value::Any=0)

    return create_field(name * "N", type, "Node_Field", dof, default_value), create_field(name * "NP1", type, "Node_Field", dof, default_value)
end

function create_node_field(name::String, type::Type, VectorOrArray::String, dof::Int64, default_value::Any=0)
    return create_field(name * "N", type, "Node_Field", VectorOrArray, dof, default_value), create_field(name * "NP1", type, "Node_Field", VectorOrArray, dof, default_value)
end

function get_all_field_keys()
    global field_types
    return collect(keys(field_types))
end

function get_block_list()
    global block_list
    return block_list
end

function get_crit_values_matrix()
    global crit_values_matrix
    return crit_values_matrix
end
"""
get_dof()

Retrieves the degree of freedom (dof) value.

Returns:
- `dof` (integer): The current degree of freedom value.

Example:
```julia
get_dof()  # returns the current degree of freedom
```
"""
function get_dof()
    global dof
    return dof
end

function get_field(name::String, time::String)

    if time == "Constant" || time == "CONSTANT"
        return get_field(name)
    end
    return get_field(name * time)

end

function get_field(name::String)
    global fields
    global field_array_type
    global field_types

    # view() to get SubArray references
    # https://docs.julialang.org/en/v1/base/arrays/#Views-(SubArrays-and-other-view-types)
    if name in get_all_field_keys()
        if length(size(fields[field_types[name]][name])) > 1
            if field_array_type[name]["Type"] == "Matrix"
                field_dof = field_array_type[name]["Dof"]
                return view(reshape(fields[field_types[name]][name], (:, field_dof, field_dof)), :, :, :)
            end
            return view(fields[field_types[name]][name], :, :)
        end
        if field_array_type[name]["Type"] == "Matrix"
            field_dof = field_array_type[name]["Dof"]
            return view([reshape(field, (:, field_dof, field_dof)) for field in fields[field_types[name]][name]], :,)
        end
        return view(fields[field_types[name]][name], :,)
    end
    @error "Field ''" * name * "'' does not exist. Check if it is initialized as constant."
    return nothing
end

"""
    get_field_type()
    Get the type of a field

    Returns:
    - `get_field_type` (string): returns the type of a field

"""
function get_field_type(name::String)
    global field_types

    if !haskey(field_types, name)
        @error "Field ''" * name * "'' does not exist."
        return nothing
    end
    return field_types[name]
end

"""
    get_local_nodes()

    Determines the local node numbering.

    Returns:
    - `get_local_nodes` (array): returns local nodes.

    Example:
    ```julia
    get_local_nodes()  # returns local nodes or if they do not exist at the core an empty array
    ```
    """
function get_local_nodes(global_nodes)
    global glob_to_loc

    return [glob_to_loc[global_node] for global_node in global_nodes if global_node in keys(glob_to_loc)]

end

function get_material_type(key)
    return material_type[key]
end

function get_nlist()
    return get_field("Neighborhoodlist")
end
"""
get_nnodes()

Retrieves the number of nodes.

Returns:
- `num_controller::Int64` : The current number of nodes.

Example:
```julia
get_nnodes()  # returns the current number of nodes 
```
"""
function get_nnodes()
    global num_controller
    return num_controller
end



function get_NP1_to_N_Dict()
    NP1_to_N = Dict{String,String}()
    for key in get_all_field_keys()
        if occursin("NP1", key)
            NP1_to_N[key] = key[1:end-2]
        end
    end
    return NP1_to_N
end

"""
   get_nnsets()

   Get the number of node sets.

   Returns:
   - `nnsets::Int`: The number of node sets.

"""
function get_nnsets()
    global nnsets
    return nnsets
end

"""
get_nsets()

Get the node sets

Returns:
- `nsets::Dict{String,Vector{Int64}}`: The node sets dictionary.
"""

function get_nsets()
    global nsets
    return nsets
end

"""
get_num_responder()

Get the the number of responder nodes

Returns:
- `num_responder::Int64`: The number of responder nodes
"""

function get_num_responder()
    global num_responder
    return num_responder
end

function get_overlap_map()
    global overlap_map
    return overlap_map
end

function get_synch_fields()
    global fields_to_synch
    return fields_to_synch
end

function get_physics_options()
    global physics_options

    if physics_options["Deformation Gradient"]
        physics_options["Shape Tensor"] = true
        physics_options["Deformed Bond Geometry"] = true
    end
    if physics_options["Bond Associated Deformation Gradient"]
        physics_options["Deformation Gradient"] = true
        physics_options["Bond Associated Shape Tensor"] = true
        physics_options["Shape Tensor"] = true
        physics_options["Deformed Bond Geometry"] = true
    end
    return physics_options
end

"""
    get_properties(block_id::Int64, property::String)

This function retrieves the value of a specified `property` for a given `block_id` if it exists in the properties dictionary.

# Arguments
- `block_id`::Int64: The identifier of the block for which to retrieve the property.
- `property`::String: The dictionary entrycontaining the properties for the blocks.

# Returns
- `property_value`::Any: The value associated with the specified `property` for the given `block_id`.
- `Dict()`: An empty dictionary if the specified `property` does not exist for the given `block_id`.

# Example
```julia
block_properties = Dict(
    1 => Dict("color" => "red", "size" => 10),
    2 => Dict("color" => "blue", "height" => 20)
)

# Retrieve the 'color' property for block 1
color_value = get_properties(1, "color")  # Returns "red"

# Try to retrieve a non-existent property for block 2
non_existent_value = get_properties(2, "width")  # Returns an empty dictionary
"""
function get_properties(block_id::Int64, property::String)
    global properties

    if check_property(block_id, property)
        return properties[block_id][property]
    end
    return Dict()
end
"""
    get_property(block_id::Int64, property::String, value_name::String)

This function retrieves a specific `value_name` associated with a specified `property` for a given `block_id` if it exists in the properties dictionary.

# Arguments
- `block_id`::Int64: The identifier of the block for which to retrieve the property.
- `property`::String: The String property type (e.g. Material model) for the blocks.
- `value_name`::String: The name of the value within the specified `property`.

# Returns
- `value`::Any: The value associated with the specified `value_name` within the `property` for the given `block_id`.
- `nothing`: If the specified `block_id`, `property`, or `value_name` does not exist in the dictionary.

# Example
```julia

"""
function get_property(block_id::Int64, property::String, value_name::String)
    global properties

    if check_property(block_id, property)
        if value_name in keys(properties[block_id][property])
            return properties[block_id][property][value_name]
        end
    end

    return nothing
end

"""
    get_rank()

This function returns the rank of the core.

# Returns
- `rank`::Any: The value of the `rank` variable.

# Example
```julia
current_rank = get_rank()
"""
function get_rank()
    global rank
    return rank
end
"""
    get_max_rank()

This function returns the maximal rank of MPI the `max_rank`.

# Returns
- `max_rank`::Number: The value of the `max_rank` variable.

# Example
```julia
rank = get_max_rank()
"""
function get_max_rank()
    return max_rank
end

function init_property()
    global properties

    for iblock in get_block_list()
        properties[iblock] = Dict{String,Dict}("Thermal Model" => Dict{String,Any}(), "Damage Model" => Dict{String,Any}(), "Material Model" => Dict{String,Any}(), "Additive Model" => Dict{String,Any}())
    end
    return collect(keys(properties[1]))
end

function set_block_list(blocks)
    global block_list = sort(unique(blocks))
end

function set_crit_values_matrix(crit_values)
    global crit_values_matrix = crit_values
end
"""
set_dof(n)

Sets the degree of freedom (dof) value globally.

Parameters:
- `n` (integer): The value to set as the degree of freedom.

Example:
```julia
set_dof(3)  # sets the degree of freedom to 3
```
"""
function set_dof(n)

    global dof = n
end
"""
set_glob_to_loc(dict)

Sets the global-to-local mapping dict globally.

Parameters:
- `dict` (array): The dict representing the global-to-local mapping.

Example:
```julia
set_glob_to_loc([1, 3, 5])  # sets the global-to-local mapping dict
```
"""
function set_glob_to_loc(dict::Dict)

    global glob_to_loc = dict
end

function set_distribution(values::Vector{Int64})

    global distribution = values
end

"""
loc_to_glob(range::UnitRange{Int64})

Converts the local index to the global index.

Parameters:
- `range::UnitRange{Int64}`: The range of the local index.

Example:
```julia
loc_to_glob(1:10)  # converts the local index to the global index
```
"""
function loc_to_glob(range::UnitRange{Int64})
    global distribution
    return distribution[range]
end

function set_material_type(key, value)
    if key in keys(material_type)
        global material_type[key] = value
    else
        @warn "Type " * key * " is not defined"
    end
end

"""
 set_nnodes()

 Sets the number all nodes of one core globally.

 Parameters:

 Example:
 ```
 """
function set_nnodes()
    global num_controller
    global num_responder
    global nnodes = num_controller + num_responder
end

"""
 set_num_controller(n::Int64)

 Sets the number of controller nodes globally. For one core the number of nodes is equal to the number of controller nodes.

 Parameters:
 - `n::Int64`: The value to set as the number of nodes.

 Example:
 ```julia
 set_num_controller(10)  # sets the number of nodes to 10
 ```
 """
function set_num_controller(n::Int64)
    global num_controller = n
    set_nnodes()
end
"""
set_nnsets(n::Int64)

Set the number of node sets.

Parameters:
- `n::Int64`: The number of node sets to be set.

"""
function set_nnsets(n::Int64)

    global nnsets = n
end
"""
set_nset(name, nodes)
Set the nodes associated with a named node set.

Parameters:
- `name::String`: The name of the node set.
- `nodes::Vector{Int}`: The node indices associated with the node set.

"""
function set_nset(name::String, nodes::Vector{Int})
    global nsets

    if name in keys(nsets)
        @warn "Node set " * name * " already defined and it is overwritten"
    end
    nsets[name] = nodes
    # set the number of node sets
    set_nnsets(length(nsets))
end

"""
set_num_responder(n::Int64)

Sets the number of responder nodes globally. For one core the number of responder is zero. responder hold the information of the neighbors, of one node, but are not evaluated.

Parameters:
- `n::Int64`: The value to set as the number of nodes.

Example:
```julia
set_num_responder(10)  # sets the number of responder nodes to 10
```
"""
function set_num_responder(n)
    global num_responder = n
    set_nnodes()
end

function set_overlap_map(topo)
    global overlap_map = topo
end

function set_physics_options(values::Dict{String,Bool})
    global physics_options = values
end

function set_property(block_id, property, value_name, value)
    global properties

    properties[block_id][property][value_name] = value
end

function set_properties(block_id, property, values)
    global properties

    properties[block_id][property] = values
end

function set_rank(value::Int64)
    global rank = value
end

function set_max_rank(value::Int64)
    global max_rank = value
end

function set_synch(name, download_from_cores, upload_to_cores)
    global fields_to_synch

    if name in get_all_field_keys()
        field = get_field(name)
        fields_to_synch[name] = Dict{String,Any}("upload_to_cores" => upload_to_cores, "download_from_cores" => download_from_cores, "dof" => length(field[1, :]))
    elseif name * "NP1" in get_all_field_keys()
        field = get_field(name * "NP1")
        fields_to_synch[name*"NP1"] = Dict{String,Any}("upload_to_cores" => upload_to_cores, "download_from_cores" => download_from_cores, "dof" => length(field[1, :]))
    end

end

function set_fields_equal(name::String, NP1::String)
    set_fields_equal(name * NP1)
end

function set_fields_equal(NP1::String)
    global field_array_type

    NP1_to_N = get_NP1_to_N_Dict()
    if field_array_type[NP1]["Type"] == "Matrix"
        field_array_type[NP1]["Type"] = "Vector"
        field_NP1 = get_field(NP1)
        field_array_type[NP1]["Type"] = "Matrix"
        N = NP1_to_N[NP1]
        field_array_type[N]["Type"] = "Vector"
        field_N = get_field(N)
        field_array_type[N]["Type"] = "Matrix"
    else
        field_NP1 = get_field(NP1)
        N = NP1_to_N[NP1]
        field_N = get_field(N)
    end
    field_N[:] = field_NP1[:]
end

function switch_NP1_to_N()
    global field_types
    global field_array_type

    NP1_to_N = get_NP1_to_N_Dict()
    for NP1 in keys(NP1_to_N)
        if field_array_type[NP1]["Type"] == "Matrix"
            field_array_type[NP1]["Type"] = "Vector"
            field_NP1 = get_field(NP1)
            field_array_type[NP1]["Type"] = "Matrix"
            N = NP1_to_N[NP1]
            field_array_type[N]["Type"] = "Vector"
            field_N = get_field(N)
            field_array_type[N]["Type"] = "Matrix"
        else
            field_NP1 = get_field(NP1)
            N = NP1_to_N[NP1]
            field_N = get_field(N)
        end
        field_N[:] = field_NP1[:]
        if size(field_NP1[1]) == ()
            field_NP1[:] = fill(field_types[NP1](0), size(field_NP1))
        else
            value = 0
            if "Bond DamageNP1" == NP1
                value = 1
            end
            for fieldID in eachindex(field_NP1)
                field_NP1[fieldID] = fill(field_types[NP1](value), size(field_NP1[fieldID]))
            end
        end
    end
end
function synch_manager(synchronise_field, direction::String)
    global overlap_map

    synch_fields = get_synch_fields()
    for synch_field in keys(synch_fields)
        synchronise_field(get_comm(), synch_fields, overlap_map, get_field, synch_field, direction)
    end
end
end