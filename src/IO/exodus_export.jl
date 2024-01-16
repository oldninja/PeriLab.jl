# SPDX-FileCopyrightText: 2023 Christian Willberg <christian.willberg@dlr.de>, Jan-Timo Hesse <jan-timo.hesse@dlr.de>
#
# SPDX-License-Identifier: BSD-3-Clause

using Exodus
export get_paraview_coordinates
export create_result_file
export init_results_in_exodus
export merge_exodus_file

"""
    create_result_file(filename::Union{AbstractString,String}, num_nodes::Int64, num_dim::Int64, num_elem_blks::Int64, num_node_sets::Int64)

Creates a exodus file for the results

# Arguments
- `filename::Union{AbstractString,String}`: The name of the file to create
- `num_nodes::Int64`: The number of nodes
- `num_dim::Int64`: The number of dimensions
- `num_elem_blks::Int64`: The number of element blocks
- `num_node_sets::Int64`: The number of node sets
# Returns
- `result_file::Dict{String,Any}`: A dictionary containing the filename and the exodus file
"""
function create_result_file(filename::Union{AbstractString,String}, num_nodes::Int64, num_dim::Int64, num_elem_blks::Int64, num_node_sets::Int64)

    if isfile(filename)
        rm(filename)
    end
    maps_int_type = Int32
    ids_int_type = Int32
    bulk_int_type = Int32
    float_type = Float64
    num_elems = num_nodes
    num_side_sets = 0
    init = Initialization{bulk_int_type}(
        Int32(num_dim), Int32(num_nodes), Int32(num_elems),
        Int32(num_elem_blks), Int32(num_node_sets), Int32(num_side_sets)
    )
    @info "Create output " * filename
    exo_db = ExodusDatabase{maps_int_type,ids_int_type,bulk_int_type,float_type}(
        filename, "w", init)
    return Dict("filename" => filename, "file" => exo_db, "type" => "Exodus")
end

"""
    paraview_specifics(dof::Int64)

Returns the paraview specific dof

# Arguments
- `dof::Int64`: The degrees of freedom
# Returns
- `paraview_specifics::String`: The paraview specific dof
"""
function paraview_specifics(dof::Int64)
    convention = Dict(1 => "x", 2 => "y", 3 => "z")
    return convention[dof]
end

"""
    get_paraview_coordinates(dof::Int64, refDof::Int64)

Returns the paraview specific dof

# Arguments
- `dof::Int64`: The degrees of freedom
- `refDof::Int64`: The reference degrees of freedom
# Returns
- `paraview_specifics::String`: The paraview specific dof
"""
function get_paraview_coordinates(dof::Int64, refDof::Int64)
    if dof > refDof
        @warn "Reference dof are to small and set to used dof"
        refDof = dof
    end
    if refDof < 4
        return paraview_specifics(dof)
    end
    if refDof < 10
        return paraview_specifics(Int(ceil(dof / 3))) * paraview_specifics(dof - Int(ceil(dof / 3 - 1) * 3))
    end

    @error "not exportable yet as one variable"
    return nothing

end

"""
    get_block_nodes(block_Id::Union{SubArray,Vector{Int64}}, block::Int64)

Returns the nodes of a block

# Arguments
- `block_Id::Union{SubArray,Vector{Int64}}`: The block Id
- `block::Int64`: The block
# Returns
- `nodes::Vector{Int64}`: The nodes of the block
"""
function get_block_nodes(block_Id::Union{SubArray,Vector{Int64}}, block::Int64)
    conn = findall(x -> x == block, block_Id)
    return reshape(conn, 1, length(conn))
end

"""
    init_results_in_exodus(exo::ExodusDatabase, output::Dict{}, coords::Union{Matrix{Int64},Matrix{Float64}}, block_Id::Vector{Int64}, uniqueBlocks::Vector{Int64}, nsets::Dict{String,Vector{Int64}}, global_ids::Vector{Int64}, PERILAB_VERSION::String)

Initializes the results in exodus

# Arguments
- `exo::ExodusDatabase`: The exodus database
- `output::Dict{String,Any}`: The output
- `coords::Union{Matrix{Int64},Matrix{Float64}}`: The coordinates
- `block_Id::Vector{Int64}`: The block Id
- `uniqueBlocks::Vector{Int64}`: The unique blocks
- `nsets::Dict{String,Vector{Int64}}`: The node sets
- `global_ids::Vector{Int64}`: The global ids
# Returns
- `result_file::Dict{String,Any}`: The result file
"""
function init_results_in_exodus(exo::ExodusDatabase, output::Dict{}, coords::Union{Matrix{Int64},Matrix{Float64}}, block_Id::Vector{Int64}, uniqueBlocks::Vector{Int64}, nsets::Dict{String,Vector{Int64}}, global_ids::Vector{Int64}, PERILAB_VERSION::String)
    info = ["PeriLab Version $PERILAB_VERSION, under BSD License", "Copyright (c) 2023, Christian Willberg, Jan-Timo Hesse", "compiled with Julia Version " * string(VERSION)]

    write_info(exo, info)

    # check if type of coords is int or Float64
    if typeof(coords) in [Matrix{Int64}, Matrix{Float64}]
        coords = convert(Matrix{Float64}, coords)
    end

    write_coordinates(exo, coords)

    id::Int32 = 0
    # bloecke checken
    for name in eachindex(nsets)
        id += Int32(1)
        nsetExo = NodeSet(id, convert(Array{Int32}, nsets[name]))

        write_set(exo, nsetExo)
        write_name(exo, nsetExo, name)
    end

    for block in uniqueBlocks
        conn = get_block_nodes(block_Id, block)# virtual elements   
        write_block(exo, block, "SPHERE", conn)
        write_name(exo, Block, block, "Block_" * string(block))
    end

    # write element id map

    write_id_map(exo, NodeMap, Int32.(global_ids))
    write_id_map(exo, ElementMap, Int32.(global_ids))

    # output structure var_name -> [fieldname, exodus id, field dof]

    nodal_outputs = Dict(key => value for (key, value) in output["Fields"] if (!value["global_var"]))
    global_outputs = Dict(key => value for (key, value) in output["Fields"] if (value["global_var"]))
    nodal_output_names = collect(keys(sort(nodal_outputs)))
    global_output_names = collect(keys(sort(global_outputs)))
    # compute_names = collect(keys(sort(computes)))

    write_number_of_variables(exo, NodalVariable, length(nodal_output_names))
    write_names(exo, NodalVariable, nodal_output_names)
    nnodes = exo.init.num_nodes

    for varname in nodal_output_names
        # interface does not work with Int yet 28//08//2023
        write_values(exo, NodalVariable, 1, output["Fields"][varname]["result_id"], varname, zeros(Float64, nnodes))
    end
    if length(global_output_names) > 0
        write_number_of_variables(exo, GlobalVariable, length(global_output_names))
        write_names(exo, GlobalVariable, global_output_names)
        for varname in global_output_names
            write_values(exo, GlobalVariable, 1, output["Fields"][varname]["result_id"], varname, [Float64(0.0)])
        end
    end
    return exo
end

"""
    write_step_and_time(exo::ExodusDatabase, step::Int64, time::Float64)

Writes the step and time in the exodus file

# Arguments
- `exo::ExodusDatabase`: The exodus file
- `step::Int64`: The step
- `time::Float64`: The time
# Returns
- `exo::ExodusDatabase`: The exodus file
"""
function write_step_and_time(exo::ExodusDatabase, step::Int64, time::Float64)
    write_time(exo, step, Float64(time))
    return exo
end

"""
    write_nodal_results_in_exodus(exo::ExodusDatabase, step::Int64, output::Dict, datamanager::Module)

Writes the nodal results in the exodus file

# Arguments
- `exo::ExodusDatabase`: The exodus file
- `step::Int64`: The step
- `output::Dict`: The output
- `datamanager::Module`: The datamanager
# Returns
- `exo::ExodusDatabase`: The exodus file
"""
function write_nodal_results_in_exodus(exo::ExodusDatabase, step::Int64, output::Dict, datamanager::Module)
    #write_values
    nnodes = datamanager.get_nnodes()
    for varname in keys(output)
        field = datamanager.get_field(output[varname]["fieldname"])
        #exo, timestep::Integer, id::Integer, var_index::Integer,vector
        # =>https://github.com/cmhamel/Exodus.jl/blob/master/src/Variables.jl 
        if haskey(output[varname], "dof")
            var = convert(Array{Float64}, field[1:nnodes, output[varname]["dof"]])
        else
            var = convert(Array{Float64}, field[1:nnodes, output[varname]["i_dof"], output[varname]["j_dof"]])
        end
        # interface does not work with Int yet 28//08//2023
        write_values(exo, NodalVariable, step, output[varname]["result_id"], varname, var)
    end
    return exo
end

"""
    write_global_results_in_exodus(exo::ExodusDatabase, step::Int64, output::Dict, global_values)

Writes the global results in the exodus file

# Arguments
- `exo::ExodusDatabase`: The exodus file
- `step::Int64`: The step
- `output::Dict`: The output
- `global_values`: The global values
# Returns
- `exo::ExodusDatabase`: The exodus file
"""
function write_global_results_in_exodus(exo::ExodusDatabase, step::Int64, output::Dict, global_values)

    for (id, varname) in enumerate(keys(output))
        write_values(exo, GlobalVariable, step, output[varname]["result_id"], varname, [global_values[id]])
    end
    return exo
end

"""
    merge_exodus_file(file_name::Union{AbstractString,String})

Merges the exodus file

# Arguments
- `file_name::Union{AbstractString,String}`: The name of the file to merge
# Returns
- `exo::ExodusDatabase`: The exodus file
"""
function merge_exodus_file(file_name::Union{AbstractString,String})
    epu(file_name)
end
