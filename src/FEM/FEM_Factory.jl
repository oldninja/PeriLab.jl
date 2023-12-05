module FEM
include("../Core/Module_inclusion/set_Modules.jl")
include("./FEM_routines.jl")
# SPDX-FileCopyrightText: 2023 Christian Willberg <christian.willberg@dlr.de>, Jan-Timo Hesse <jan-timo.hesse@dlr.de>
#
# SPDX-License-Identifier: BSD-3-Clause

using .Set_modules
global module_list = Set_modules.find_module_files(@__DIR__, "element_name")
Set_modules.include_files(module_list)

function init_FEM(datamanager::Module, params::Dict)

    dof = datamanager.get_dof()
    nelements = datamanager.get_num_elements()
    elements::Vector{Int64} = 1:nelements
    p = get_polynomial_degree(params, dof)
    if isnothing(p)
        return p
    end
    if dof != 2 && dof != 3
        @error "Degree of freedom = $dof is not supported, only 2 and 3."
        return nothing
    end
    N = datamanager.create_constant_field("N Matrix", Float64, (prod(p .+ 1), prod(p .+ 1) * dof, dof))
    B = datamanager.create_constant_field("B Matrix", Float64, (prod(p .+ 1), prod(p .+ 1) * dof, 3 * dof - 3))

    if isnothing(N) || isnothing(B)
        return nothing
    end
    specifics = Dict{String,String}("Call Function" => "create_element_matrices", "Name" => "element_name")
    N[:], B[:] = create_element_matrices(dof, p, Set_modules.create_module_specifics(params["Element Type"], module_list, specifics))

    specifics = Dict{String,String}("Call Function" => "init_element", "Name" => "element_name")
    datamanager = Set_modules.create_module_specifics(params["Element Type"], module_list, specifics, (datamanager, elements, params, p))

    return datamanager

end



#datamanager = Set_modules.create_module_specifics(fem_model, module_list, specifics, (datamanager, nodes, model_param, time, dt))
#if isnothing(datamanager)
#    @error "No shape function of name " * fem_model * " exists."
#end


function get_polynomial_degree(params::Dict, dof::Int64)
    if !haskey(params, "Degree")
        @error "No element degree defined"
        return nothing
    end
    value = params["Degree"]
    if sum(typeof.(value) .!= Int64) != 0
        @warn "Degree was defined as Float and set to Int."
        value = Int64.(round.(value))
    end
    if length(value) == 1
        return_value::Vector{Int64} = zeros(dof)
        return_value[1:dof] .= value[1]
        return return_value
    elseif length(value) == dof
        return value[1:dof]
    else
        @error "Degree must be defined with length one or number of dof."
        return nothing
    end
end


end