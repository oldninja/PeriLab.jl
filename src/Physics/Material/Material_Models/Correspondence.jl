# SPDX-FileCopyrightText: 2023 Christian Willberg <christian.willberg@dlr.de>, Jan-Timo Hesse <jan-timo.hesse@dlr.de>
#
# SPDX-License-Identifier: BSD-3-Clause

module Correspondence
using LinearAlgebra
using TensorOperations
include("Correspondence_Elastic.jl")
include("./Zero_Energy_Control/global_control.jl")
include("../material_basis.jl")
include("../../../Support/geometry.jl")
using .global_zero_energy_control
using .Correspondence_Elastic
#global module_list = Set_modules.find_module_files(@__DIR__, "material_name")
#Set_modules.include_files(module_list)
using .Geometry
export init_material_model
export material_name
export compute_force

"""
  init_material_model(datamanager::Module)

  Initializes the material model.

  Parameters:
    - `datamanager::Data_manager`: Datamanager.

  Returns:
    - `datamanager::Data_manager`: Datamanager.
"""
function init_material_model(datamanager::Module)
  # global dof
  # global rotation
  # global angles

  dof = datamanager.get_dof()
  nnodes = datamanager.get_nnodes()
  datamanager.create_node_field("Strain", Float64, "Matrix", dof)
  datamanager.create_node_field("Cauchy Stress", Float64, "Matrix", dof)

  rotation::Bool, angles = datamanager.rotation_data()
  if rotation
    orientations = datamanager.create_constant_node_field("Orientations", Float64, "Vector", dof)
    for iID in 1:nnodes
      rotation_tensor = Geometry.rotation_tensor(angles[iID, :])
      orientations[iID, :] = diag(rotation_tensor[1:dof, 1:dof])
    end
  end

  return datamanager
end
"""
   material_name()

   Gives the material name. It is needed for comparison with the yaml input deck.

   Parameters:

   Returns:
   - `name::String`: The name of the material.

   Example:
   ```julia
   println(material_name())
   "Material Template"
   ```
   """
function material_name()
  return Correspondence_Elastic.correspondence_name()
end
"""
   compute_force(datamanager, nodes, material_parameter, time, dt)

   Calculates the force densities of the material. This template has to be copied, the file renamed and edited by the user to create a new material. Additional files can be called from here using include and `import .any_module` or `using .any_module`. Make sure that you return the datamanager.

   Parameters:
        - `datamanager::Data_manager`: Datamanager.
        - `nodes::Union{SubArray, Vector{Int64}}`: List of block nodes.
        - `material_parameter::Dict(String, Any)`: Dictionary with material parameter.
        - `time::Float64`: The current time.
        - `dt::Float64`: The current time step.
   Returns:
        - - `datamanager::Data_manager`: Datamanager.
   Example:
   ```julia
     ```
   """
function compute_forces(datamanager::Module, nodes::Union{SubArray,Vector{Int64}}, material_parameter::Dict, time::Float64, dt::Float64)
  # global dof
  # global rotation
  # global angles

  rotation::Bool, angles = datamanager.rotation_data()
  dof = datamanager.get_dof()
  deformation_gradient = datamanager.get_field("Deformation Gradient")
  bond_force = datamanager.get_field("Bond Forces")
  bond_damage = datamanager.get_field("Bond Damage", "NP1")

  bond_geometry = datamanager.get_field("Bond Geometry")
  inverse_shape_tensor = datamanager.get_field("Inverse Shape Tensor")

  strainN = datamanager.get_field("Strain", "N")
  strainNP1 = datamanager.get_field("Strain", "NP1")
  stressN = datamanager.get_field("Cauchy Stress", "N")
  stressNP1 = datamanager.get_field("Cauchy Stress", "NP1")

  strainNP1 = Geometry.strain(nodes, deformation_gradient, strainNP1)
  strainInc = strainNP1 - strainN


  if rotation
    stressN = rotate(nodes, dof, stressN, angles, false)
    strainInc = rotate(nodes, dof, strainInc, angles, false)
  end

  # in future this part must be changed -> using set Modules
  stressNP1, datamanager = Correspondence_Elastic.compute_stresses(datamanager, nodes, dof, material_parameter, time, dt, strainInc, stressN, stressNP1)

  #specifics = Dict{String,String}("Call Function" => "compute_stresses", "Name" => "material_name") -> tbd
  # material_model is missing
  #stressNP1, datamanager = Set_modules.create_module_specifics(material_model, module_list, specifics, (datamanager, nodes, dof, material_parameter, time, dt, strainInc, stressN, stressNP1))



  if rotation
    stressNP1 = rotate(nodes, dof, stressNP1, angles, true)
  end
  bond_force[:] = calculate_bond_force(nodes, deformation_gradient, bond_geometry, bond_damage, inverse_shape_tensor, stressNP1, bond_force)
  # general interface, because it might be a flexbile Set_modules interface in future
  datamanager = zero_energy_mode_compensation(datamanager, nodes, material_parameter, time, dt)

  return datamanager
end

"""
Global - J. Wan et al., "Improved method for zero-energy mode suppression in peridynamic correspondence model in Acta Mechanica Sinica https://doi.org/10.1007/s10409-019-00873-y
"""
function zero_energy_mode_compensation(datamanager::Module, nodes::Union{SubArray,Vector{Int64}}, material_parameter::Dict, time::Float64, dt::Float64)
  if !haskey(material_parameter, "Zero Energy Control")
    @warn "No zero energy control activated for corresponcence."
    return datamanager
  end
  if material_parameter["Zero Energy Control"] == global_zero_energy_control.control_name()
    datamanager = global_zero_energy_control.compute_control(datamanager, nodes, material_parameter, time, dt)
  end
  return datamanager
end



function calculate_bond_force(nodes::Union{SubArray,Vector{Int64}}, deformation_gradient::SubArray, bond_geometry::SubArray, bond_damage::SubArray, inverse_shape_tensor::SubArray, stressNP1::SubArray, bond_force::SubArray)
  for iID in nodes
    jacobian = det(deformation_gradient[iID, :, :])
    if jacobian <= 1e-8
      @error "Deformation Gradient is singular and cannot be inverted.\n - Check if your mesh is 3D, but has only one layer of nodes\n - Check number of damaged bonds."
    end
    # taken from corresponcence.cxx -> computeForcesAndStresses
    invdeformation_gradient::Matrix{Float64} = inv(deformation_gradient[iID, :, :])
    piolaStress::Matrix{Float64} = jacobian .* invdeformation_gradient * stressNP1[iID, :, :]
    temp::Matrix{Float64} = piolaStress * inverse_shape_tensor[iID, :, :]

    bond_force[iID][:, :] = (bond_damage[iID][:] .* bond_geometry[iID][:, 1:end-1]) * temp

  end
  return bond_force
end


function rotate(nodes::Union{SubArray,Vector{Int64}}, dof::Int64, matrix::Union{SubArray,Array{Float64,3}}, angles::SubArray, back::Bool)
  for iID in nodes
    matrix[iID, :, :] = rotate_second_order_tensor(angles[iID, :], matrix[iID, :, :], dof, back)
  end
  return matrix
end

function rotate_second_order_tensor(angles::Union{Vector{Float64},Vector{Int64}}, tensor::Matrix{Float64}, dof::Int64, back::Bool)
  rot = Geometry.rotation_tensor(angles)

  R = rot[1:dof, 1:dof]

  if back
    @tensor begin
      tensor[m, n] = tensor[i, j] * R[m, i] * R[n, j]
    end
  else
    @tensor begin
      tensor[m, n] = tensor[i, j] * R[i, m] * R[j, n]
    end
  end
end


end