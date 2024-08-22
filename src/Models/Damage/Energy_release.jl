# SPDX-FileCopyrightText: 2023 Christian Willberg <christian.willberg@dlr.de>, Jan-Timo Hesse <jan-timo.hesse@dlr.de>
#
# SPDX-License-Identifier: BSD-3-Clause

module Critical_Energy_Model
include("../Material/Material_Factory.jl")
include("../../Support/geometry.jl")
include("../Pre_calculation/Pre_Calculation_Factory.jl")
include("../../Support/helpers.jl")
using .Material
using .Geometry
using .Pre_calculation
using .Helpers: rotate
using LinearAlgebra
using StaticArrays
export compute_model
export compute_damage_pre_calculation
export damage_name
export init_model
export synch_field
"""
    damage_name()

Gives the damage name. It is needed for comparison with the yaml input deck.

# Returns
- `name::String`: The name of the damage.

Example:
```julia
println(damage_name())
"Critical Energy"
```
"""
function damage_name()
    return "Critical Energy"
end

"""
    compute_model(datamanager, nodes, damage_parameter, block, time, dt)

Calculates the elastic energy of each bond and compares it to a critical one. If it is exceeded, the bond damage value is set to zero.
[WillbergC2019](@cite), [FosterJT2011](@cite)

# Arguments
- `datamanager::Data_manager`: Datamanager.
- `nodes::Union{SubArray,Vector{Int64}}`: List of block nodes.
- `damage_parameter::Dict(String, Any)`: Dictionary with material parameter.
- `block::Int64`: Block number.
- `time::Float64`: The current time.
- `dt::Float64`: The current time step.
# Returns
- `datamanager::Data_manager`: Datamanager.
Example:
```julia
```
"""
function compute_model(
    datamanager::Module,
    nodes::Union{SubArray,Vector{Int64}},
    damage_parameter::Dict,
    block::Int64,
    time::Float64,
    dt::Float64,
)
    dof::Int64 = datamanager.get_dof()
    nlist = datamanager.get_nlist()
    block_list = datamanager.get_block_list()
    block_ids = datamanager.get_field("Block_Id")
    update_list = datamanager.get_field("Update List")
    horizon = datamanager.get_field("Horizon")
    bond_damage = datamanager.get_bond_damage("NP1")
    aniso_damage::Bool = haskey(damage_parameter, "Anisotropic Damage")

    undeformed_bond = datamanager.get_field("Bond Geometry")
    undeformed_bond_length = datamanager.get_field("Bond Length")
    bond_forces = datamanager.get_field("Bond Forces")
    deformed_bond = datamanager.get_field("Deformed Bond Geometry", "NP1")
    deformed_bond_length = datamanager.get_field("Deformed Bond Length", "NP1")
    critical_field = datamanager.has_key("Critical_Value")
    critical_energy =
        critical_field ? datamanager.get_field("Critical_Value") :
        damage_parameter["Critical Value"]
    quad_horizon = datamanager.get_field("Quad Horizon")
    inverse_nlist = datamanager.get_inverse_nlist()
    dependend_value::Bool = false
    if haskey(damage_parameter, "Temperature dependend")
        if !datamanager.has_key(damage_parameter["Temperature dependend"]["Field key"])
            @error "Critical Value key " *
                   damage_parameter["Temperature dependend"]["Field key"] *
                   " does not exist for value interpolation in damage model."
            return nothing
        end
        field = datamanager.get_field(damage_parameter["Critical Value"]["Field key"])
        dependend_value = true
    end

    # for anisotropic damage models
    rotation::Bool = datamanager.get_rotation()

    tension::Bool = get(damage_parameter, "Only Tension", true)
    inter_block_damage::Bool = haskey(damage_parameter, "Interblock Damage")
    if inter_block_damage
        inter_critical_energy::Array{Float64,3} = datamanager.get_crit_values_matrix()
    end

    if aniso_damage
        aniso_crit_values = datamanager.get_aniso_crit_values()
        bond_damage_aniso = datamanager.get_field("Bond Damage Anisotropic", "NP1")
        bond_norm::Float64 = 0.0
        rotation_tensor = datamanager.get_field("Rotation Tensor", "NP1")
    end

    bond_energy::Float64 = 0.0
    norm_displacement::Float64 = 0.0
    x_vector::Vector{Float64} = @SVector zeros(Float64, dof)
    x_vector[1] = 1.0

    neighbor_bond_force::Vector{Float64} = @SVector zeros(Float64, dof)
    projected_force::Vector{Float64} = @SVector zeros(Float64, dof)

    for iID in nodes
        @views relative_displacement_vector = deformed_bond[iID] .- undeformed_bond[iID]

        for (jID, neighborID) in enumerate(nlist[iID])
            @views relative_displacement = relative_displacement_vector[jID, :]
            norm_displacement = norm(relative_displacement)

            if norm_displacement == 0 || (
                tension &&
                deformed_bond_length[iID][jID] - undeformed_bond_length[iID][jID] < 0
            )
                continue
            end

            # check if the bond also exist at other node, due to different horizons
            try
                @views neighbor_bond_force .=
                    bond_forces[neighborID][inverse_nlist[neighborID][iID], :]
            catch e
                # Handle the case when the key doesn't exist
            end

            @views projected_force .=
                dot(bond_forces[iID][jID, :] - neighbor_bond_force, relative_displacement) /
                (norm_displacement * norm_displacement) .* relative_displacement

            @views bond_energy =
                0.25 * dot(abs.(projected_force), abs.(relative_displacement))

            if dependend_value
                critical_energy =
                    interpol_data(field[iID], damage_parameter["Temperature dependend"])
            end

            @views crit_energy =
                critical_field ? critical_energy[iID] :
                inter_block_damage ?
                inter_critical_energy[block_ids[iID], block_ids[neighborID], block] :
                critical_energy

            if aniso_damage
                #TODO Fix bug herem rotation_tensor is zero
                @info rotation_tensor[iID, :, :]'
                @views rotated_bond =
                    rotation_tensor[iID, :, :]' * deformed_bond[iID][jID, :]
                # Compute bond_norm for all components at once
                @views bond_norm_all = abs.(rotated_bond) ./ deformed_bond_length[iID][jID]

                # Compute the condition for all components at once
                @views condition =
                    bond_energy / quad_horizon[iID] * bond_norm_all .>
                    aniso_crit_values[block_ids[iID]]

                # Update bond_damage, bond_damage_aniso, and update_list in a vectorized manner
                @views bond_damage[iID][jID] -= sum(bond_norm_all .* condition)
                @views bond_damage[iID][jID] = max.(bond_damage[iID][jID], 0) # Ensure non-negative
                @views bond_damage_aniso[iID][jID, :] .= 0 .+ condition
                update_list[iID] = any(condition)

                ###################################################################################################

                # x = abs(bond_norm_all[1]) / sum(abs.(bond_norm_all))
                # crit_energy = 6.41640733892757 + 43.447538762292922x - 48.899767470904678x^2 + 18.972581432264228x^3
                # # crit_energy = eval(Meta.parse(aniso_crit_values[block_ids[iID]]))
                # if (bond_energy / quad_horizon[iID]) > crit_energy
                #     bond_damage[iID][jID] = 0.0
                #     update_list[iID] = true
                # end

                ###################################################################################################
                # for i in 1:dof
                #     if bond_damage_aniso[iID][jID, i] == 0 || rotated_bond[i] == 0
                #         continue
                #     end
                #     bond_norm = abs(rotated_bond[i]) / deformed_bond_length[iID][jID]
                #     # @info "Norm: " * string(bond_norm)
                #     # @info "bond_energy: " * string(bond_energy / quad_horizon[iID] * bond_norm)
                #     # @info "aniso_crit_values: " * string(aniso_crit_values[block_ids[iID]][i])
                #     if bond_energy / quad_horizon[iID] * bond_norm > aniso_crit_values[block_ids[iID]][i]
                #         bond_damage[iID][jID] -= bond_norm # TODO: check if this is correct
                #         bond_damage[iID][jID] = max(bond_damage[iID][jID], 0) # Ensure non-negative
                #         bond_damage_aniso[iID][jID, i] = 0
                #         update_list[iID] = true
                #     end
                # end

            else
                if (bond_energy / quad_horizon[iID]) > crit_energy
                    bond_damage[iID][jID] = 0.0
                    update_list[iID] = true
                end
            end
        end
    end
    return datamanager
end

"""
    compute_damage_pre_calculation(datamanager::Module, nodes::Union{SubArray,Vector{Int64}}, block::Int64, synchronise_field, time::Float64, dt::Float64)

Compute the pre calculation for the damage.

# Arguments
- `datamanager::Data_manager`: Datamanager.
- `nodes::Union{SubArray,Vector{Int64}}`: List of block nodes.
- `block::Int64`: Block number
- `synchronise_field`: Synchronise function to distribute parameter through cores.
- `time::Float64`: The current time.
- `dt::Float64`: The current time step.
# Returns
- `datamanager::Data_manager`: Datamanager.
"""
function compute_damage_pre_calculation(
    datamanager::Module,
    nodes::Union{SubArray,Vector{Int64}},
    block::Int64,
    time::Float64,
    dt::Float64,
)
    return datamanager
end

"""
    fields_for_local_synchronization()

Returns a user developer defined local synchronization. This happens before each model.

The structure of the Dict must because

    synchfield = Dict(
        "Field name" =>
            Dict("upload_to_cores" => true, "dof" => datamanager.get_dof()),
    )

or

    synchfield = Dict(
        "Field name" =>
            Dict("download_from_cores" => true, "dof" => datamanager.get_dof()),
    )

# Arguments

"""
function fields_for_local_synchronization()
    synchfield = Dict(
        "Bond Forces" =>
            Dict("upload_to_cores" => true, "dof" => datamanager.get_dof()),
    )
    return Dict()
end

"""
    get_quad_horizon(horizon::Float64, dof::Int64)

Get the quadric of the horizon.

# Arguments
- `horizon::Float64`: The horizon of the block.
- `dof::Int64`: The degree of freedom.
- `thickness::Float64`: The thickness of the block.
# Returns
- `quad_horizon::Float64`: The quadric of the horizon.
"""
function get_quad_horizon(horizon::Float64, dof::Int64, thickness::Float64)
    if dof == 2
        return Float64(3 / (pi * horizon^3 * thickness))
    end
    return Float64(4 / (pi * horizon^4))
end
function init_model(
    datamanager::Module,
    nodes::Union{SubArray,Vector{Int64}},
    damage_parameter::Dict,
    block::Int64,
)

    quad_horizon = datamanager.create_constant_node_field("Quad Horizon", Float64, 1)
    horizon = datamanager.get_field("Horizon")
    dof = datamanager.get_dof()
    thickness::Float64 = get(damage_parameter, "Thickness", 1)
    for iID in nodes
        quad_horizon[iID] = get_quad_horizon(horizon[iID], dof, thickness)
    end

    if haskey(damage_parameter, "Anisotropic Damage")
        rotation::Bool, angles = datamanager.rotation_data()
        if !rotation
            # TODO is this necassary? If you have no angles, you can use the global ones.
            @error "Anisotropic damage requires Angles field"
            return nothing
        end
    end

    return datamanager
end
end
