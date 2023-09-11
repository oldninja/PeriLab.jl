
include("../material_basis.jl")
module PD_Solid_Elastic
include("./Ordinary.jl")
import .Ordinary
export compute_force
export material_name

function material_name()
    return "PD Solid Elastic"
end

function elastic(nodes, dof, bond_geometry, deformed_bond, bond_damage, theta, weighted_volume, omega, material, bond_force)
    for iID in nodes
        alpha = 15.0 * material["Shear Modulus"] / weighted_volume[iID]
        beta = 3.0 * material["Bulk Modulus"] / weighted_volume[iID]
        c1 = theta[iID] * (beta - alpha / 3.0)

        zeta = bond_geometry[iID][:, end]
        stretch = deformed_bond[iID][:, end] .- bond_geometry[iID][:, end]
        t = bond_damage[iID][:] .* omega[iID] .* (c1 .* zeta .+ alpha .* stretch)

        bond_force[iID] = t .* deformed_bond[iID][:, 1:dof] ./ deformed_bond[iID][:, end]
    end
    return bond_force
end

function compute_forces(datamanager, nodes, material, time, dt)
    dof = datamanager.get_dof()
    nlist = datamanager.get_nlist()
    force_densities = datamanager.get_field("Force Densities", "NP1")
    nneighbors = datamanager.get_field("Number of Neighbors")
    deformed_bond = datamanager.get_field("Deformed Bond Geometry", "NP1")
    bond_damage = datamanager.get_field("Bond Damage", "NP1")
    omega = datamanager.get_field("Influence Function")
    volume = datamanager.get_field("Volume")
    bond_geometry = datamanager.get_field("Bond Geometry")
    bond_force = datamanager.create_constant_bond_field("Bond Forces", Float32, dof)


    # optiming, because if no damage it has not to be updated

    weighted_volume = Ordinary.compute_weighted_volume(nodes, nneighbors, nlist, bond_geometry, bond_damage, omega, volume)
    theta = Ordinary.compute_dilatation(nodes, nneighbors, nlist, bond_geometry, deformed_bond, bond_damage, volume, weighted_volume, omega)
    bond_force = elastic(nodes, dof, bond_geometry, deformed_bond, bond_damage, theta, weighted_volume, omega, material, bond_force)

    force_densities[:] = distribute_forces(nodes, nlist, bond_force, volume, force_densities)
    return datamanager
end

end