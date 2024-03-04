# SPDX-FileCopyrightText: 2023 Christian Willberg <christian.willberg@dlr.de>, Jan-Timo Hesse <jan-timo.hesse@dlr.de>
#
# SPDX-License-Identifier: BSD-3-Clause

module Helpers

using Tensors
using Dierckx
using ProgressBars
export check_inf_or_nan
export find_active
export get_active_update_nodes
export find_indices
export find_inverse_bond_id
export find_files_with_ending
export matrix_style
export get_fourth_order
export interpolation
export interpol_data
export progress_bar

"""
    find_indices(vector, what)

Returns the indices of `vector` that are equal to `what`.

# Arguments
- `vector::Vector`: The vector to search in.
- `what`: The value to search for.
# Returns
- `indices::Vector`: The indices of `vector` that are equal to `what`.
"""
function find_indices(vector, what)
    return findall(item -> item == what, vector)
end

"""
    find_active(active::Vector{Bool})

Returns the indices of `active` that are true.

# Arguments
- `active::Vector{Bool}`: The vector to search in.
# Returns
- `indices::Vector`: The indices of `active` that are true.
"""
function find_active(active::Vector{Bool})
    return [i for (i, is_active) in enumerate(active) if is_active]
end

"""
    get_active_update_nodes(active::SubArray, update_list::SubArray, block_nodes::Dict{Int64,Vector{Int64}}, block::Int64)

Returns the active nodes and the update nodes.

# Arguments
- `active::SubArray`: The active vector.
- `update_list::SubArray`: The update vector.
- `block_nodes::Dict{Int64,Vector{Int64}}`: The vector to search in.
- `block::Int64`: The block_id.
# Returns
- `active_nodes::Vector{Int64}`: The nodes of `active` that are true.
- `update_nodes::Vector{Int64}`: The nodes of `update` that are true.
"""
function get_active_update_nodes(active::SubArray, update_list::SubArray, block_nodes::Dict{Int64,Vector{Int64}}, block::Int64)
    active_nodes::Vector{Int64} = []
    update_nodes::Vector{Int64} = []
    active_index = find_active(active[block_nodes[block]])

    if isempty(active_index)
        return active_nodes, update_nodes
    end
    active_nodes = view(block_nodes[block], active_index)
    update_index = find_active(update_list[active_nodes])
    if !isempty(update_index)
        update_nodes = active_nodes[update_index]
    end
    return active_nodes, update_nodes
end

"""
    find_files_with_ending(folder_path::AbstractString, file_ending::AbstractString)

Returns a list of files in `folder_path` that end with `file_ending`.

# Arguments
- `folder_path::AbstractString`: The path to the folder.
- `file_ending::AbstractString`: The ending of the files.
# Returns
- `file_list::Vector{String}`: The list of files that end with `file_ending`.
"""
function find_files_with_ending(folder_path::AbstractString, file_ending::AbstractString)
    file_list = filter(x -> isfile(joinpath(folder_path, x)) && endswith(x, file_ending), readdir(folder_path))
    return file_list
end

"""
    check_inf_or_nan(array, msg)

Checks if the sum of the array is finite. If not, an error is raised.

# Arguments
- `array`: The array to check.
- `msg`: The error message to raise.
# Returns
- `Bool`: `true` if the sum of the array is finite, `false` otherwise.
"""
function check_inf_or_nan(array, msg)
    if !isfinite(sum(array))
        @error msg * " is infinite."
        return true
    end
    return false
end

"""
    matrix_style(A)

Include a scalar or an array and reshape it to style needed for LinearAlgebra package

# Arguments
- `A`: The array or scalar to reshape
# Returns
- `Array`: The reshaped array
"""
function matrix_style(A)

    if length(size(A)) == 0
        A = [A]
    end
    dim = size(A)[1]
    return reshape(A, dim, dim)
end

"""
    get_fourth_order(CVoigt, dof)

Constructs a symmetric fourth-order tensor from a Voigt notation vector. It uses Tensors.jl package.

This function takes a Voigt notation vector `CVoigt` and the degree of freedom `dof` 
to create a symmetric fourth-order tensor. The `CVoigt` vector contains components 
that represent the tensor in Voigt notation, and `dof` specifies the dimension 
of the tensor.

# Arguments
- `CVoigt::Matrix{Float64}`: A vector containing components of the tensor in Voigt notation.
- `dof::Int64`: The dimension of the resulting symmetric fourth-order tensor.

# Returns
- `SymmetricFourthOrderTensor{dof}`: A symmetric fourth-order tensor of dimension `dof`.

# Example
```julia
CVoigt = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
dof = 3
result = get_fourth_order(CVoigt, dof)
"""
function get_fourth_order(CVoigt, dof::Int64)
    return fromvoigt(SymmetricTensor{4,dof}, CVoigt)
end

"""
    find_inverse_bond_id(nlist::SubArray)

Finds the inverse of the bond id in the nlist.

# Arguments
- `nlist::SubArray`: The nlist to find the inverse of.
# Returns
- `inverse_nlist::Vector{Dict{Int64,Int64}}`: The inverse nlist.
"""
function find_inverse_bond_id(nlist::SubArray)
    inverse_nlist = [Dict{Int64,Int64}() for _ in eachindex(nlist)]
    for iID in eachindex(nlist)
        neighbors = nlist[iID]
        for (jID, neighborID) in enumerate(neighbors)
            value = findfirst(isequal(iID), nlist[neighborID])
            # Check if neighbor ID is found in nlist, due to different horizons
            if isnothing(value)
                continue
            end

            inverse_nlist[neighborID][iID] = value
        end
    end
    return inverse_nlist
end

function interpolation(x::Union{Vector{Float64},Vector{Int64}}, y::Union{Vector{Float64},Vector{Int64}})
    k = 3
    if length(x) <= k
        k = length(x) - 1
    end
    return Dict("spl" => Spline1D(x, y, k=k), "min" => minimum(x), "max" => maximum(x))
end

function interpol_data(x::Union{Vector{Float64},Vector{Int64},Float64,Int64}, values::Dict{String,Any})
    if values["min"] > minimum(x)
        @warn "Interpolation value is below interpolation range. Using minimum value of dataset."
    end
    if values["max"] < maximum(x)
        @warn "Interpolation value is above interpolation range. Using maximum value of dataset."
    end
    return evaluate(values["spl"], x)
end


"""
    progress_bar(rank::Int64, nsteps::Int64, silent::Bool)

Create a progress bar if the rank is 0. The progress bar ranges from 1 to nsteps + 1.

# Arguments
- rank::Int64: An integer to determine if the progress bar should be created.
- nsteps::Int64: The total number of steps in the progress bar.
- silent::Bool: de/activates the progress bar
# Returns
- ProgressBar or UnitRange: If rank is 0, a ProgressBar object is returned. Otherwise, a range from 1 to nsteps + 1 is returned.
"""
function progress_bar(rank::Int64, nsteps::Int64, silent::Bool)
    # Check if rank is equal to 0.
    if rank == 0 && !silent
        # If rank is 0, create and return a ProgressBar from 1 to nsteps + 1.
        return ProgressBar(1:nsteps+1)
    end
    # If rank is not 0, return a range from 1 to nsteps + 1.
    return 1:nsteps+1
end
end