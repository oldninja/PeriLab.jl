# SPDX-FileCopyrightText: 2023 Christian Willberg <christian.willberg@dlr.de>, Jan-Timo Hesse <jan-timo.hesse@dlr.de>
#
# SPDX-License-Identifier: BSD-3-Clause

module Thermal_Flow
using LinearAlgebra
export compute_thermal_model
export thermal_model_name
export init_thermal_model
"""
    thermal_model_name()

Gives the model name. It is needed for comparison with the yaml input deck.

# Arguments

# Returns
- `name::String`: "Thermal Flow"
"""
function thermal_model_name()
  return "Thermal Flow"
end


"""
    init_thermal_model(datamanager, nodes, thermal_parameter)

Inits the thermal model. This template has to be copied, the file renamed and edited by the user to create a new thermal. Additional files can be called from here using include and `import .any_module` or `using .any_module`. Make sure that you return the datamanager.

# Arguments
- `datamanager::Data_manager`: Datamanager.
- `nodes::Union{SubArray,Vector{Int64}}`: List of block nodes.
- `thermal parameter::Dict(String, Any)`: Dictionary with thermal parameter.
- `block::Int64`: The current block.
# Returns
- `datamanager::Data_manager`: Datamanager.

"""
function init_thermal_model(datamanager::Module, nodes::Union{SubArray,Vector{Int64}}, thermal_parameter::Dict)

  return datamanager
end

"""
    compute_thermal_model(datamanager, nodes, thermal_parameter, time, dt)

Calculates the thermal behavior of the material. This template has to be copied, the file renamed and edited by the user to create a new flow. Additional files can be called from here using include and `import .any_module` or `using .any_module`. Make sure that you return the datamanager.

# Arguments
- `datamanager::Data_manager`: Datamanager.
- `nodes::Union{SubArray,Vector{Int64}}`: List of block nodes.
- `flow parameter::Dict(String, Any)`: Dictionary with flow parameter.
- `time::Float64`: The current time.
- `dt::Float64`: The current time step.
# Returns
- `datamanager::Data_manager`: Datamanager.
Example:
```julia
```
"""
function compute_thermal_model(datamanager::Module, nodes::Union{SubArray,Vector{Int64}}, thermal_parameter::Dict, time::Float64, dt::Float64)

  if !haskey(thermal_parameter, "Type")
    @error "No model type has beed defined; ''Type'': ''Bond based'' or Type: ''Correspondence''"
    return datamanager
  end
  dof = datamanager.get_dof()
  nlist = datamanager.get_nlist()
  coordinates = datamanager.get_field("Coordinates")
  bond_damage = datamanager.get_field("Bond Damage", "NP1")
  bond_heat_flow = datamanager.get_field("Bond Heat Flow")
  undeformed_bond = datamanager.get_field("Bond Geometry")
  volume = datamanager.get_field("Volume")
  temperature = datamanager.get_field("Temperature", "NP1")
  if !haskey(thermal_parameter, "Thermal Conductivity")
    @error "Thermal Conductivity not defined."
    return nothing
  end
  lambda = thermal_parameter["Thermal Conductivity"]
  apply_print_bed = false
  t_bed = 0.0
  lambda_bed = 0.0
  if haskey(thermal_parameter, "Print Bed Temperature")
    if dof < 3
      @error "Print bed temperature can only be defined for 3D problems"
    end
    apply_print_bed = true
    t_bed = thermal_parameter["Print Bed Temperature"]
    lambda_bed = thermal_parameter["Thermal Conductivity Print Bed"]
  end

  if thermal_parameter["Type"] == "Bond based"
    horizon = datamanager.get_field("Horizon")
    if length(lambda) > 1
      lambda = lambda[1]
    end
    bond_heat_flow = compute_heat_flow_state_bond_based(nodes, dof, nlist, lambda, apply_print_bed, t_bed, lambda_bed, coordinates, bond_damage, undeformed_bond, horizon, temperature, bond_heat_flow)
    return datamanager

  elseif thermal_parameter["Type"] == "Correspondence"

    lambda_matrix = zeros(Float64, dof, dof)
    Kinv = datamanager.get_field("Inverse Shape Tensor")
    if length(lambda) == 1
      for i in 1:dof
        lambda_matrix[i, i] = lambda
      end
    else
      for i in 1:dof
        lambda_matrix[i, i] = lambda[i]
      end
    end

    bond_heat_flow = compute_heat_flow_state_correspondence(nodes, dof, nlist, lambda_matrix, bond_damage, undeformed_bond, Kinv, temperature, volume, bond_heat_flow)
  else
    @error "No model valid type has beed defined; ''Bond based'' or ''Correspondence''"
  end
  return datamanager
end


"""
[BrighentiR2021](@cite)
is a prototype with some errors
"""
function compute_heat_flow_state_correspondence(nodes::Union{SubArray,Vector{Int64}}, dof::Int64, nlist::SubArray, lambda::Matrix{Float64}, bond_damage::SubArray, undeformed_bond::SubArray, Kinv::SubArray, temperature::SubArray, volume::SubArray, bond_heat_flow::SubArray)

  nablaT = zeros(Float64, dof)
  H = zeros(Float64, dof)
  for iID in nodes
    H .= 0
    for (jID, neighborID) in enumerate(nlist[iID])
      tempState = (temperature[neighborID] - temperature[iID]) * volume[neighborID] * bond_damage[iID][jID]
      H += tempState .* undeformed_bond[iID][jID, 1:dof]
    end
    nablaT = Kinv[iID, :, :] * H

    q = lambda * nablaT
    for jID in eachindex(nlist[iID])
      temp = Kinv[iID, :, :] * undeformed_bond[iID][jID, 1:dof]
      bond_heat_flow[iID][jID] += dot(temp, q)
    end
  end
  return bond_heat_flow

end

"""
    compute_heat_flow_state_bond_based(nodes::Union{SubArray,Vector{Int64}}, dof::Int64, nlist::SubArray,
      lambda::Union{Float64, Int64}, bond_damage::SubArray, undeformed_bond::SubArray, horizon::SubArray,
      temperature::SubArray, bond_heat_flow::SubArray)

Calculate heat flow based on a bond-based model for thermal analysis.

# Arguments
- `nodes::Union{SubArray,Vector{Int64}}`: An array of node indices for which heat flow should be computed.
- `dof::Int64`: The degree of freedom, either 2 or 3, indicating whether the analysis is 2D or 3D.
- `nlist::SubArray`: A SubArray representing the neighbor list for each node.
- `lambda::Union{Float64, Int64}`: The thermal conductivity.
- `apply_print_bed::Bool`: A boolean indicating whether the print bed should be applied to the thermal conductivity.
- `t_bed::Float64`: The thickness of the print bed.
- `lambda_bed::Float64`: The thermal conductivity of the print bed.
- `bond_damage::SubArray`: A SubArray representing the damage state of bonds between nodes.
- `undeformed_bond::SubArray`: A SubArray representing the geometry of the bonds.
- `horizon::SubArray`: A SubArray representing the horizon for each node.
- `temperature::SubArray`: A SubArray representing the temperature at each node.
- `bond_heat_flow::SubArray`: A SubArray where the computed bond heat flow values will be stored.

## Returns
- `bond_heat_flow`: updated bond heat flow values will be stored.

## Description
This function calculates the heat flow between neighboring nodes based on a bond-based model for thermal analysis [OterkusS2014b](@cite). It considers various parameters, including thermal conductivity, damage state of bonds, geometry of bonds, horizons, temperature, and volume. The calculated bond heat flow values are stored in the `bond_heat_flow` array.

"""
function compute_heat_flow_state_bond_based(nodes::Union{SubArray,Vector{Int64}}, dof::Int64, nlist::SubArray, lambda::Union{Float64,Int64}, apply_print_bed::Bool, t_bed::Float64, lambda_bed::Float64, coordinates::SubArray, bond_damage::SubArray, undeformed_bond::SubArray, horizon::SubArray, temperature::SubArray, bond_heat_flow::SubArray)
  kernel::Float64 = 0.0
  for iID in nodes
    if dof == 2
      kernel = 6.0 / (pi * horizon[iID] * horizon[iID] * horizon[iID])
    else
      kernel = 6.0 / (pi * horizon[iID] * horizon[iID] * horizon[iID] * horizon[iID])
    end

    for (jID, neighborID) in enumerate(nlist[iID])
      bond_heat_flow[iID][jID] = 0
      if apply_print_bed
        # check if node is near print bed and if the mirror neighbor is in a higher layer
        if coordinates[iID, 3] < horizon[iID] && undeformed_bond[iID][jID, 3] > 0
          # check if mirrored neighbor would be lower z=0
          if coordinates[iID, 3] - undeformed_bond[iID][jID, 3] <= 0
            tempState = t_bed - temperature[iID]
            if coordinates[iID, 3] == 0.0
              bond_heat_flow[iID][jID] += lambda_bed * kernel * tempState / undeformed_bond[iID][jID, end]
            else
              bond_heat_flow[iID][jID] += lambda_bed * kernel * tempState / coordinates[iID, 3]
            end
          end
        end
      end
      if bond_damage[iID][jID] == 0
        continue
      end
      tempState = bond_damage[iID][jID] * (temperature[neighborID] - temperature[iID])
      bond_heat_flow[iID][jID] += lambda * kernel * tempState / undeformed_bond[iID][jID, end]
    end
  end
  return bond_heat_flow
end
end