# SPDX-FileCopyrightText: 2023 Christian Willberg <christian.willberg@dlr.de>, Jan-Timo Hesse <jan-timo.hesse@dlr.de>
#
# SPDX-License-Identifier: BSD-3-Clause

module Material
include("../../Core/Module_inclusion/set_Modules.jl")
include("material_basis.jl")
using .Set_modules

global module_list = Set_modules.find_module_files(@__DIR__, "material_name")
Set_modules.include_files(module_list)

export compute_forces

function compute_forces(datamanager::Module, nodes::Union{SubArray,Vector{Int64}}, model_param::Dict, time::Float64, dt::Float64)
    specifics = Dict{String,String}("Call Function" => "compute_forces", "Name" => "material_name")
    material_models = split(model_param["Material Model"], "+")

    for material_model in material_models
        datamanager = Set_modules.create_module_specifics(material_model, module_list, specifics, (datamanager, nodes, model_param, time, dt))
        if isnothing(datamanager)
            @error "No material of name " * model_name * " exists."
        end
    end
    return datamanager
end
function determine_isotropic_parameter(prop)
    return get_all_elastic_moduli(prop)
end

function distribute_force_densities(datamanager::Module, nodes::Union{SubArray,Vector{Int64}})
    nlist = datamanager.get_nlist()
    bond_force = datamanager.get_field("Bond Forces")
    force_densities = datamanager.get_field("Force Densities", "NP1")
    volume = datamanager.get_field("Volume")
    force_densities = distribute_forces(nodes, nlist, bond_force, volume, force_densities)
    return datamanager
end

end
