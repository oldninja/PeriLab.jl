
using LinearAlgebra
using ProgressBars
include("../../Support/tools.jl")
include("../../MPI_communication/MPI_communication.jl")

function compute_thermodynamic_crititical_time_step(datamanager, lambda, Cv)
    """
    critical time step for a thermodynamic problem
    Selda Oterkus, Erdogan Madenci, and Abigail G. Agwai.  Fully coupled peridynamic thermomechanics
    """
    criticalTimeStep = 1.0e50
    dof = datamanager.get_dof()
    nlist = datamanager.get_nlist()
    nnodes = datamanager.get_nnodes()
    density = datamanager.get_field("Density")
    bondgeometry = datamanager.get_field("Bond Geometry")
    volume = datamanager.get_field("Volume")
    nneighbors = datamanager.get_field("Number of Neighbors")

    lambda = matrix_style(lambda)
    eigLam = maximum(eigvals(lambda))

    for iID in 1:nnodes
        denominator = get_cs_denominator(nneighbors[iID], volume[nlist[iID]], bondgeometry[iID][:, dof+1])
        t = density[iID] * Cv / (eigLam * denominator)
        criticalTimeStep = test_timestep(t, criticalTimeStep)
    end
    return sqrt(criticalTimeStep)
end
function get_cs_denominator(nneighbors, volume, bondgeometry)
    denominator = 0.0
    for jID in 1:nneighbors
        denominator += volume[jID] / bondgeometry[jID]
    end
    return denominator
end
function compute_mechanical_crititical_time_step(datamanager, bulkModulus)
    #https://www.osti.gov/servlets/purl/1140383
    # based on bond-based approximation
    criticalTimeStep = 1.0e50
    nnodes = datamanager.get_nnodes()
    dof = datamanager.get_dof()
    nneighbors = datamanager.get_field("Number of Neighbors")
    nlist = datamanager.get_nlist()
    density = datamanager.get_field("Density")
    bondgeometry = datamanager.get_field("Bond Geometry")
    volume = datamanager.get_field("Volume")
    horizon = datamanager.get_field("Horizon")

    for iID in 1:nnodes
        denominator = get_cs_denominator(nneighbors[iID], volume[nlist[iID]], bondgeometry[iID][:, dof+1])
        springConstant = 18.0 * bulkModulus / (pi * horizon[iID] * horizon[iID] * horizon[iID] * horizon[iID])
        t = density[iID] / (denominator * springConstant)
        criticalTimeStep = test_timestep(t, criticalTimeStep)
    end
    return sqrt(2 * criticalTimeStep)
end

function test_timestep(t, criticalTimeStep)
    if t < criticalTimeStep
        criticalTimeStep = t
    end
    return criticalTimeStep
end
function compute_crititical_time_step(datamanager, mechanical, thermo)
    criticalTimeStep = 1.0e50
    blocks = datamanager.get_block_list()
    for iblock in blocks
        if thermo
            lambda = datamanager.get_property(iblock, "Thermal Model", "Lambda")
            Cv = datamanager.get_property(iblock, "Thermal Model", "Specific Heat Capacity")
            if (lambda != Nothing) && (Cv != Nothing)
                t = compute_thermodynamic_crititical_time_step(datamanager, lambda, Cv)
                criticalTimeStep = criticalTimeStep = test_timestep(t, criticalTimeStep)
            end
        end
        if mechanical
            bulkModulus = datamanager.get_property(iblock, "Material Model", "Bulk Modulus")
            if (bulkModulus != Nothing)
                t = compute_mechanical_crititical_time_step(datamanager, bulkModulus)
                criticalTimeStep = criticalTimeStep = test_timestep(t, criticalTimeStep)
            end
        end
    end
    return criticalTimeStep
end


function init_Verlet(params, datamanager, mechanical, thermo)
    @info "======================="
    @info "==== Verlet Solver ===="
    @info "======================="

    initial_time = get_initial_time(params)
    final_time = get_final_time(params)
    safety_factor = get_safety_factor(params)
    dt = get_fixed_dt(params)
    @info "Initial time: " * string(initial_time) * " [s]"
    @info "Final time: " * string(final_time) * " [s]"
    if dt
        dt = compute_crititical_time_step(datamanager, mechanical, thermo)
        @info "Minimal time increment: " * string(dt) * " [s]"
    else
        @info "Fixed time increment: " * string(dt) * " [s]"
    end

    nsteps, dt = get_integration_steps(initial_time, final_time, safety_factor * dt)
    comm = datamanager.comm()
    dt = find_and_set_core_value_min(comm, dt)
    nsteps = find_and_set_core_value_max(comm, nsteps)

    @info "Safety Factor: " * string(safety_factor)
    @info "Time increment: " * string(dt) * " [s]"
    @info "Number of steps: " * string(nsteps)
    return initial_time, dt, nsteps
end
function get_integration_steps(initial_time, end_time, dt)
    if dt <= 0
        @error "Time step $dt [s] is not valid"
    end
    nsteps = ceil((end_time - initial_time) / dt)
    dt = (end_time - initial_time) / nsteps
    return Int64(nsteps), dt
end


function run_Verlet_solver(solver_options, blockNodes::Dict{Int64,Vector{Int64}}, bcs::Dict{Any,Any}, datamanager, outputs, exos::Vector{Any}, write_results)

    dof = datamanager.get_dof()
    forces = datamanager.get_field("Forces", "NP1")
    density = datamanager.get_field("Density")
    uN = datamanager.get_field("Displacements", "N")
    uNP1 = datamanager.get_field("Displacements", "NP1")
    vN = datamanager.get_field("Velocity", "N")
    vNP1 = datamanager.get_field("Velocity", "NP1")
    a = datamanager.get_field("Acceleration")
    dt = solver_options["dt"]

    time::Float32 = 0.0

    for idt in progress_bar(datamanager.get_rank(), nsteps)
        # one step more, because of init step (time = 0)
        uNP1 = 2 .* uN + vN .* dt + 0.5 * a .* (dt * dt)
        datamanager = Boundary_conditions.apply_bc(bcs, datamanager, time)
        # synch
        for block in eachindex(blockNodes)
            datamanager.set_filter(blockNodes[block])
            #forces = Physics.compute_model(datamanager, block, dt, time)
        end
        datamanager.reset_filter()
        # synch
        check_inf_or_nan(forces, "Forces")
        a = forces ./ density # element wise
        exos = write_results(exos, idt, time, outputs, datamanager)
        datamanager.switch_NP1_to_N()
        time += dt
    end
    return exos
end

"""
    progress_bar(rank::Int64, nsteps::Int64)

    Create a progress bar if the rank is 0. The progress bar ranges from 1 to nsteps + 1.

    Parameters:
    - rank (Int64): An integer to determine if the progress bar should be created.
    - nsteps (Int64): The total number of steps in the progress bar.

    Returns:
    - ProgressBar or UnitRange: If rank is 0, a ProgressBar object is returned. Otherwise, a range from 1 to nsteps + 1 is returned.
"""
function progress_bar(rank::Int64, nsteps::Int64)
    # Check if rank is equal to 0.
    if rank == 0
        # If rank is 0, create and return a ProgressBar from 1 to nsteps + 1.
        return ProgressBar(1:solver_options["nsteps"]+1)
    end

    # If rank is not 0, return a range from 1 to nsteps + 1.
    return 1:solver_options["nsteps"]+1
end