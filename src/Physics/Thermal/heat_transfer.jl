# SPDX-FileCopyrightText: 2023 Christian Willberg <christian.willberg@dlr.de>, Jan-Timo Hesse <jan-timo.hesse@dlr.de>
#
# SPDX-License-Identifier: BSD-3-Clause

module Heat_transfer
export compute_thermal_model
export thermal_model_name
"""
   thermal_flow_name()

   Gives the flow name. It is needed for comparison with the yaml input deck.

   Parameters:

   Returns:
   - `name::String`: The name of the thermal flow model.

   Example:
   ```julia
   println(flow_name())
   "Thermal Template"
   ```
   """
function thermal_model_name()
  return "Heat Transfer"
end
"""
   compute_force(datamanager, nodes, flow_parameter, time, dt)

   Calculates the thermal behavior of the material. This template has to be copied, the file renamed and edited by the user to create a new flow. Additional files can be called from here using include and `import .any_module` or `using .any_module`. Make sure that you return the datamanager.

   Parameters:
        - `datamanager::Data_manager`: Datamanager.
        - `nodes::Union{SubArray,Vector{Int64}}`: List of block nodes.
        - `flow parameter::Dict(String, Any)`: Dictionary with flow parameter.
        - `time::Float64`: The current time.
        - `dt::Float64`: The current time step.
   Returns:
        - - `datamanager::Data_manager`: Datamanager.
   Example:
   ```julia
     ```
   """
function compute_thermal_model(datamanager::Module, nodes::Union{SubArray,Vector{Int64}}, flow_parameter::Dict, time::Float64, dt::Float64)
  dof = datamanager.get_dof()
  volume = datamanager.get_field("Volume")

  numNeighbors = datamanager.get_field("Number of Neighbors")
  alpha = flow_parameter["Alpha"]
  Tenv = flow_parameter["Environment Temperature"]
  heatFlowState = datamanager.get_field("Heat Flow State")
  temperature = datamanager.get_field("Temperature", "NP1")
  dx::Float32 = 0.0
  area::Float32 = 1.0
  for iID in nodes
    if dof == 2
      dx = sqrt(volume[iID])
    else
      dx = volume[iID]^1 / 3
    end
    heatFlowState[iID] += (alpha * (temperature[iID] - Tenv)) / dx * area
  end

  return datamanager
end

end