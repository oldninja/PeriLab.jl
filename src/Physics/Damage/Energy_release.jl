# SPDX-FileCopyrightText: 2023 Christian Willberg <christian.willberg@dlr.de>, Jan-Timo Hesse <jan-timo.hesse@dlr.de>
#
# SPDX-License-Identifier: BSD-3-Clause

module Critical_Energy_Model
include("../Material/Material_Factory.jl")
include("../Pre_calculation/Pre_Calculation_Factory.jl")
using .Material
using .Pre_calculation
using TimerOutputs
using LinearAlgebra
export compute_damage
export compute_damage_pre_calculation
export damage_name

"""
   damage_name()

   Gives the damage name. It is needed for comparison with the yaml input deck.

   Parameters:

   Returns:
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
   compute_damage(datamanager, nodes, damage_parameter, block, time, dt)

   Calculates the elastic energy of each bond and compares it to a critical one. If it is exceeded, the bond damage value is set to zero.
   [WillbergC2019](@cite), [FosterJT2011](@cite)

   Parameters:
        - `datamanager::Data_manager`: Datamanager.
        - `nodes::Union{SubArray,Vector{Int64}}`: List of block nodes.
        - `damage_parameter::Dict(String, Any)`: Dictionary with material parameter.
        - `block::Int64`: Block number.
        - `time::Float64`: The current time.
        - `dt::Float64`: The current time step.
   Returns:
        - - `datamanager::Data_manager`: Datamanager.
   Example:
   ```julia
     ```
   """
function compute_damage(datamanager::Module, nodes::Union{SubArray,Vector{Int64}}, damage_parameter::Dict, block::Int64, time::Float64, dt::Float64)
  dof::Int64 = datamanager.get_dof()
  nlist = datamanager.get_nlist()
  blockList = datamanager.get_block_list()
  block_ids = datamanager.get_field("Block_Id")
  update_list = datamanager.get_field("Update List")
  horizon = datamanager.get_field("Horizon")
  bond_damage = datamanager.get_field("Bond Damage", "NP1")
  bond_geometry = datamanager.get_field("Bond Geometry")
  bond_forces = datamanager.get_field("Bond Forces")
  deformed_bond = datamanager.get_field("Deformed Bond Geometry", "NP1")
  critical_energy = damage_parameter["Critical Value"]
  inverse_nlist = datamanager.get_inverse_nlist()
  # for anisotropic damage models
  rotation::Bool, angles = datamanager.rotation_data()

  tension::Bool = true
  interBlockDamage::Bool = false
  bond_energy::Float64 = 0.0
  dist::Float64 = 0.0

  projected_force = zeros(Float64, dof)
  if haskey(damage_parameter, "Only Tension")
    tension = damage_parameter["Only Tension"]
  end
  if haskey(damage_parameter, "Interblock Damage")
    interBlockDamage = damage_parameter["Interblock Damage"]
  end
  if interBlockDamage
    inter_critical_energy::Int64 = datamanager.get_crit_values_matrix()
  end

  nneighbors = datamanager.get_field("Number of Neighbors")
  norm_displacement::Float64 = 0
  relative_displacement_vector = zeros(Float64, dof)

  for iID in nodes
    for (jID, neighborID) in enumerate(nlist[iID])
      relative_displacement_vector = deformed_bond[iID][jID, 1:dof] - bond_geometry[iID][jID, 1:dof]
      norm_displacement = norm(relative_displacement_vector)
      if norm_displacement == 0
        continue
      end
      if tension
        if deformed_bond[iID][jID, end] - bond_geometry[iID][jID, end] < 0
          continue
        end
      end

      projected_force = dot(bond_forces[iID][jID, :] -
                            bond_forces[neighborID][inverse_nlist[neighborID][iID], :], relative_displacement_vector) / (norm_displacement * norm_displacement) .* relative_displacement_vector

      bond_energy = 0.25 * dot(abs.(projected_force), abs.(relative_displacement_vector))
      if bond_energy < 0
        @error "Bond energy smaller zero"
      end
      crit_energy = critical_energy
      if interBlockDamage
        crit_energy = inter_critical_energy[block_ids[iID], block_ids[neighborID], block]
      end
      #if time > 0.0004
      #  println(bond_energy / get_quad_horizon(horizon[iID], dof))
      #end
      if (bond_energy / get_quad_horizon(horizon[iID], dof)) > crit_energy
        bond_damage[iID][jID] = 0.0
        update_list[iID] = true
      end
    end
  end
  return datamanager
end

function compute_damage_pre_calculation(datamanager::Module, nodes::Union{SubArray,Vector{Int64}}, block::Int64, synchronise_field, time::Float64, dt::Float64)
  #synchronize_bond_vector(data_manager,synchronise_field,"Bond Forces")

  return datamanager
end

function get_quad_horizon(horizon::Float64, dof::Int64)
  if dof == 2
    thickness::Float64 = 1 # is a placeholder
    return Float64(3 / (pi * horizon^3 * thickness))
  end
  return Float64(4 / (pi * horizon^4))
end


end