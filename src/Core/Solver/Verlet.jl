# SPDX-FileCopyrightText: 2023 Christian Willberg <christian.willberg@dlr.de>, Jan-Timo Hesse <jan-timo.hesse@dlr.de>
#
# SPDX-License-Identifier: BSD-3-Clause


module Verlet
using LinearAlgebra
using TimerOutputs

include("../../Support/helpers.jl")
include("../../Support/tools.jl")
include("../../MPI_communication/MPI_communication.jl")
include("../../Support/Parameters/parameter_handling.jl")
include("../BC_manager.jl")

include("../../Physics/Physics_Factory.jl")
using .Physics
using .Boundary_conditions

export init_solver
export run_solver

"""
   compute_thermodynamic_critical_time_step(nodes::Union{SubArray,Vector{Int64}}, datamanager::Module, lambda::Float64, Cv::Float64)

Calculate the critical time step for a thermodynamic simulation based on  [Oterkus2014](@cite).

This function iterates over a collection of nodes and computes the critical time step for each node using provided input data and parameters.

## Arguments
- `nodes::Union{SubArray, Vector{Int64}}`: The collection of nodes to calculate the critical time step for.
- `datamanager::Module`: The data manager module that provides access to required data fields.
- `lambda::Float64`: The material parameter used in the calculations.
- `Cv::Float64`: The heat capacity at constant volume used in the calculations.

## Returns
- `Float64`: The calculated critical time step for the thermodynamic simulation.

## Dependencies
This function depends on the following data fields from the `datamanager` module:
- `get_dof()`: Returns the degree of freedom.
- `get_nlist()`: Returns the neighbor list.
- `get_field("Density")`: Returns the density field.
- `get_field("Bond Geometry")`: Returns the bond geometry field.
- `get_field("Volume")`: Returns the volume field.
- `get_field("Number of Neighbors")`: Returns the number of neighbors field.

"""

function compute_thermodynamic_critical_time_step(nodes::Union{SubArray,Vector{Int64}}, datamanager::Module, lambda::Union{Float64,Int64}, Cv::Union{Float64,Int64})

    criticalTimeStep::Float64 = 1.0e50
    dof = datamanager.get_dof()
    nlist = datamanager.get_nlist()
    density = datamanager.get_field("Density")
    bondgeometry = datamanager.get_field("Bond Geometry")
    volume = datamanager.get_field("Volume")
    nneighbors = datamanager.get_field("Number of Neighbors")

    lambda = matrix_style(lambda)
    eigLam = maximum(eigvals(lambda))

    for iID in nodes
        denominator = get_cs_denominator(volume[nlist[iID]], bondgeometry[iID][:, dof+1])
        t = density[iID] * Cv / (eigLam * denominator)
        criticalTimeStep = test_timestep(t, criticalTimeStep)
    end
    return sqrt(criticalTimeStep)
end
function get_cs_denominator(volume::Union{SubArray,Vector{Float64},Vector{Int64}}, bondgeometry::Union{SubArray,Vector{Float64},Vector{Int64}})
    return sum(volume ./ bondgeometry)
end

"""
    compute_mechanical_critical_time_step(nodes::Union{SubArray,Vector{Int64}}, datamanager::Module, bulkModulus::Float64)

Calculate the critical time step for a mechanical simulation using a bond-based approximation [LittlewoodDJ2013](@cite).

This function iterates over a collection of nodes and computes the critical time step for each node based on the given input data and parameters.

## Arguments
- `nodes::Union{SubArray, Vector{Int64}}`: The collection of nodes to calculate the critical time step for.
- `datamanager::Module`: The data manager module that provides access to required data fields.
- `bulkModulus::Float64`: The bulk modulus used in the calculations.

## Returns
- `Float64`: The calculated critical time step for the mechanical simulation.

## Dependencies
This function depends on the following data fields from the `datamanager` module:
- `get_nlist()`: Returns the neighbor list.
- `get_field("Density")`: Returns the density field.
- `get_field("Bond Geometry")`: Returns the bond geometry field.
- `get_field("Volume")`: Returns the volume field.
- `get_field("Horizon")`: Returns the horizon field.

"""

function compute_mechanical_critical_time_step(nodes::Union{SubArray,Vector{Int64}}, datamanager::Module, bulkModulus::Union{Float64,Int64})
    criticalTimeStep::Float64 = 1.0e50
    nlist = datamanager.get_nlist()
    density = datamanager.get_field("Density")
    bondgeometry = datamanager.get_field("Bond Geometry")
    volume = datamanager.get_field("Volume")
    horizon = datamanager.get_field("Horizon")

    for iID in nodes
        denominator = get_cs_denominator(volume[nlist[iID]], bondgeometry[iID][:, end])

        springConstant = 18.0 * bulkModulus / (pi * horizon[iID] * horizon[iID] * horizon[iID] * horizon[iID])

        t = density[iID] / (denominator * springConstant)
        criticalTimeStep = test_timestep(t, criticalTimeStep)
    end
    return sqrt(2 * criticalTimeStep)
end

"""
    test_timestep(t::Float64, criticalTimeStep::Float64)

Compare a time step `t` with a critical time step `criticalTimeStep` and update `criticalTimeStep` if `t` is smaller.

## Arguments
- `t::Float64`: The time step to compare with `criticalTimeStep`.
- `criticalTimeStep::Float64`: The current critical time step.

## Returns
- `criticalTimeStep::Float64`: The updated critical time step, which is either the original `criticalTimeStep` or `t`, whichever is smaller.

"""

function test_timestep(t::Float64, criticalTimeStep::Float64)
    if t < criticalTimeStep
        criticalTimeStep = t
    end
    return criticalTimeStep
end

"""
    compute_crititical_time_step(datamanager::Module, blockNodes::Dict{Int64,Vector{Int64}}, mechanical::Bool, thermo::Bool)

Calculate the critical time step for a simulation considering both mechanical and thermodynamic aspects.

This function computes the critical time step by considering mechanical and thermodynamic properties of different blocks. The resulting critical time step is based on the smallest critical time step found among the blocks.

## Arguments
- `datamanager::Module`: The data manager module that provides access to required data fields and properties.
- `blockNodes::Dict{Int64, Vector{Int64}}`: A dictionary mapping block IDs to collections of nodes.
- `mechanical::Bool`: If `true`, mechanical properties are considered in the calculation.
- `thermo::Bool`: If `true`, thermodynamic properties are considered in the calculation.

## Returns
- `Float64`: The calculated critical time step based on the smallest critical time step found among the blocks.

## Dependencies
This function may depend on the following functions:
- `compute_thermodynamic_critical_time_step`: Used if `thermo` is `true` to calculate thermodynamic critical time steps.
- `compute_mechanical_critical_time_step`: Used if `mechanical` is `true` to calculate mechanical critical time steps.
- The availability of specific properties from the data manager module.

## Errors
- If required properties are not available in the data manager, it may raise an error message.

"""

function compute_crititical_time_step(datamanager::Module, blockNodes::Dict{Int64,Vector{Int64}}, mechanical::Bool, thermo::Bool)
    criticalTimeStep::Float64 = 1.0e50
    for iblock in eachindex(blockNodes)
        if thermo
            lambda = datamanager.get_property(iblock, "Thermal Model", "Lambda")
            Cv = datamanager.get_property(iblock, "Thermal Model", "Specific Heat Capacity")
            # if Cv and lambda are not defined it is valid, because an analysis can take place, if material is still analysed
            if (lambda != Nothing) && (Cv != Nothing)
                t = compute_thermodynamic_critical_time_step(blockNodes[iblock], datamanager, lambda, Cv)
                criticalTimeStep = criticalTimeStep = test_timestep(t, criticalTimeStep)
            end
        end
        if mechanical
            bulkModulus = datamanager.get_property(iblock, "Material Model", "Bulk Modulus")
            if (bulkModulus != Nothing)
                t = compute_mechanical_critical_time_step(blockNodes[iblock], datamanager, bulkModulus)
                criticalTimeStep = criticalTimeStep = test_timestep(t, criticalTimeStep)
            else
                @error "No time step for material is determined because of missing properties."
            end

        end
    end
    return criticalTimeStep
end

"""
    init_solver(params::Dict, datamanager::Module, blockNodes::Dict{Int64,Vector{Int64}}, mechanical::Bool, thermo::Bool)

Initialize the Verlet solver for a simulation.

This function sets up the Verlet solver for a simulation by initializing various parameters and calculating the time step based on provided parameters or critical time step calculations.

## Arguments
- `params::Dict`: A dictionary containing simulation parameters.
- `datamanager::Module`: The data manager module that provides access to required data fields and properties.
- `blockNodes::Dict{Int64,Vector{Int64}}`: A dictionary mapping block IDs to collections of nodes.
- `mechanical::Bool`: If `true`, mechanical properties are considered in the calculation.
- `thermo::Bool`: If `true`, thermodynamic properties are considered in the calculation.

## Returns
A tuple `(initial_time, dt, nsteps, numerical_damping)` where:
- `initial_time::Float64`: The initial time for the simulation.
- `dt::Float64`: The time step for the simulation.
- `nsteps::Int64`: The number of time integration steps.
- `numerical_damping::Float64`: The numerical damping factor.

## Dependencies
This function may depend on the following functions:
- `get_initial_time`, `get_final_time`, `get_safety_factor`, `get_fixed_dt`: Used to retrieve simulation parameters.
- `compute_crititical_time_step`: Used to calculate the critical time step if `dt` is not fixed.
- `get_integration_steps`: Used to determine the number of integration steps and adjust the time step.
- `find_and_set_core_value_min` and `find_and_set_core_value_max`: Used to set core values in a distributed computing environment.

"""

function init_solver(params::Dict, datamanager::Module, blockNodes::Dict{Int64,Vector{Int64}}, mechanical::Bool, thermo::Bool)
    @info "======================="
    @info "==== Verlet Solver ===="
    @info "======================="

    initial_time = get_initial_time(params)
    final_time = get_final_time(params)
    safety_factor = get_safety_factor(params)
    dt = get_fixed_dt(params)
    @info "Initial time: " * string(initial_time) * " [s]"
    @info "Final time: " * string(final_time) * " [s]"
    if dt == true
        dt = compute_crititical_time_step(datamanager, blockNodes, mechanical, thermo)
        @info "Minimal time increment: " * string(dt) * " [s]"
    else
        @info "Fixed time increment: " * string(dt) * " [s]"
    end

    nsteps, dt = get_integration_steps(initial_time, final_time, safety_factor * dt)
    comm = datamanager.get_comm()
    dt = find_and_set_core_value_min(comm, dt)
    nsteps = find_and_set_core_value_max(comm, nsteps)

    @info "Safety Factor: " * string(safety_factor)
    @info "Time increment: " * string(dt) * " [s]"
    @info "Number of steps: " * string(nsteps)
    @info "Numerical Damping " * string(get_numerical_damping(params))
    return initial_time, dt, nsteps, get_numerical_damping(params)
end

"""
    get_integration_steps(initial_time::Float64, end_time::Float64, dt::Float64)

Calculate the number of integration steps and the adjusted time step for a numerical integration process.

## Arguments
- `initial_time::Float64`: The initial time for the integration.
- `end_time::Float64`: The final time for the integration.
- `dt::Float64`: The time step size.

## Returns
A tuple `(nsteps, dt)` where:
- `nsteps::Int64`: The number of integration steps required to cover the specified time range.
- `dt::Float64`: The adjusted time step size to evenly divide the time range.

## Errors
- Throws an error if the `dt` is less than or equal to zero.

"""

function get_integration_steps(initial_time::Float64, end_time::Float64, dt::Float64)
    if dt <= 0
        @error "Time step $dt [s] is not valid"
    end
    nsteps::Int64 = ceil((end_time - initial_time) / dt)
    dt = (end_time - initial_time) / nsteps
    return nsteps, dt
end

"""
    run_solver(
        solver_options::Dict{String,Any},
        blockNodes::Dict{Int64,Vector{Int64}},
        bcs::Dict{Any,Any},
        datamanager::Module,
        outputs::Dict{Int64,Dict{}},
        result_files::Vector{Any},
        synchronise_field,
        write_results,
        to::TimerOutputs.TimerOutput,
        silent::Bool
    )

Run the Verlet solver for a simulation based on the strategy provided in [BobaruF2016](@cite) and  [LittlewoodDJ2023](@cite).
    
This function performs the Verlet solver simulation, updating various data fields and properties over a specified number of time steps.

## Arguments
- `solver_options::Dict{String,Any}`: A dictionary containing solver options and parameters.
- `blockNodes::Dict{Int64,Vector{Int64}}`: A dictionary mapping block IDs to collections of nodes.
- `bcs::Dict{Any,Any}`: A dictionary containing boundary conditions.
- `datamanager::Module`: The data manager module that provides access to data fields and properties.
- `outputs::Dict{Int64,Dict{}}`: A dictionary for output settings.
- `result_files::Vector{Any}`: A vector of result files.
- `synchronise_field`: A function for synchronization.
- `write_results`: A function to write simulation results.
- `to::TimerOutputs.TimerOutput`: A timer output.
- `silent::Bool`: A boolean flag to suppress progress bars.

## Returns
- `result_files`: A vector of updated result files.

## Dependencies
This function depends on various data fields and properties from the `datamanager` module, as well as several helper functions. It also relies on solver options and boundary conditions provided in the input parameters.

## Function Workflow
1. Initialize simulation parameters and data fields.
2. Perform Verlet integration over a specified number of time steps.
3. Update data fields and properties based on the solver options.
4. Write simulation results using the `write_results` function.
5. Return the updated `result_files` vector.

"""

function run_solver(solver_options::Dict{String,Any}, blockNodes::Dict{Int64,Vector{Int64}}, bcs::Dict{Any,Any}, datamanager::Module, outputs::Dict{Int64,Dict{}}, result_files::Vector{Any}, synchronise_field, write_results, to::TimerOutputs.TimerOutput, silent::Bool)
    @info "Run Verlet Solver"
    dof = datamanager.get_dof()
    nnodes = datamanager.get_nnodes()
    volume = datamanager.get_field("Volume")
    density = datamanager.get_field("Density")
    coor = datamanager.get_field("Coordinates")
    uNP1 = datamanager.get_field("Displacements", "NP1")

    defCoorNP1 = datamanager.get_field("Deformed Coordinates", "NP1")
    if solver_options["Material Models"]
        forces = datamanager.get_field("Forces", "NP1")
        forces_density = datamanager.get_field("Force Densities", "NP1")
        uN = datamanager.get_field("Displacements", "N")
        vN = datamanager.get_field("Velocity", "N")
        vNP1 = datamanager.get_field("Velocity", "NP1")
        a = datamanager.get_field("Acceleration")
        coor = datamanager.get_field("Coordinates")
        defCoorN = datamanager.get_field("Deformed Coordinates", "N")
    end
    if solver_options["Thermal Models"]
        flowN = datamanager.get_field("Heat Flow", "N")
        flowNP1 = datamanager.get_field("Heat Flow", "NP1")
        temperatureN = datamanager.get_field("Temperature", "N")
        temperatureNP1 = datamanager.get_field("Temperature", "NP1")
        heatCapacity = datamanager.get_field("Heat Capacity")
        deltaT = datamanager.create_constant_node_field("Delta Temperature", Float64, 1)
    end
    active = datamanager.get_field("Active")
    update_list = datamanager.get_field("Update List")

    dt::Float64 = solver_options["dt"]
    nsteps::Int64 = solver_options["nsteps"]
    start_time::Float64 = solver_options["Initial Time"]
    step_time::Float64 = 0
    numericalDamping::Float64 = solver_options["Numerical Damping"]
    for idt in progress_bar(datamanager.get_rank(), nsteps, silent)
        @timeit to "Verlet" begin
            # one step more, because of init step (time = 0)
            if solver_options["Material Models"]
                vNP1[find_active(active[1:nnodes]), :] = (1 - numericalDamping) .* vN[find_active(active[1:nnodes]), :] + 0.5 * dt .* a[find_active(active[1:nnodes]), :]

                uNP1[find_active(active[1:nnodes]), :] = uN[find_active(active[1:nnodes]), :] + dt .* vNP1[find_active(active[1:nnodes]), :]
            end
            if solver_options["Thermal Models"]
                temperatureNP1[find_active(active[1:nnodes])] = temperatureN[find_active(active[1:nnodes])] + deltaT[find_active(active[1:nnodes])]
            end
            @timeit to "apply_bc" datamanager = Boundary_conditions.apply_bc(bcs, datamanager, step_time)
            #if solver_options["Material Models"]
            #needed because of optional defGrad, Deformed bonds, etc.
            defCoorNP1[find_active(active[1:nnodes]), :] = coor[find_active(active[1:nnodes]), :] + uNP1[find_active(active[1:nnodes]), :]
            #end
            datamanager.synch_manager(synchronise_field, "upload_to_cores")
            # synch
            for block in eachindex(blockNodes)
                bn = blockNodes[block]
                active_nodes = bn[find_active(active[bn])]
                @timeit to "compute_models" datamanager = Physics.compute_models(datamanager, active_nodes, block, dt, step_time, solver_options, synchronise_field, to)
            end
            datamanager.synch_manager(synchronise_field, "download_from_cores")
            # synch
            @timeit to "second apply_bc" datamanager = Boundary_conditions.apply_bc(bcs, datamanager, step_time)

            if solver_options["Material Models"]
                check_inf_or_nan(forces_density, "Forces")
                a[find_active(active[1:nnodes]), :] = forces_density[find_active(active[1:nnodes]), :] ./ density[find_active(active[1:nnodes])] # element wise
                forces[find_active(active[1:nnodes]), :] = forces_density[find_active(active[1:nnodes]), :] .* volume[find_active(active[1:nnodes])]
            end
            if solver_options["Thermal Models"]
                check_inf_or_nan(flowNP1, "Heat Flow")
                deltaT[find_active(active[1:nnodes])] = -flowNP1[find_active(active[1:nnodes])] .* dt ./ (density[find_active(active[1:nnodes])] .* heatCapacity[find_active(active[1:nnodes])])
            end
            result_files = write_results(result_files, start_time + step_time, outputs, datamanager)
            datamanager.switch_NP1_to_N()
            update_list .= true
            step_time += dt
            if idt < 10 || nsteps - idt < 10 || idt % ceil(nsteps / 10) == 0
                @info "Step: $idt / $(nsteps+1) [$step_time s]"
            end

        end
    end
    return result_files
end

end