# SPDX-FileCopyrightText: 2023 Christian Willberg <christian.willberg@dlr.de>, Jan-Timo Hesse <jan-timo.hesse@dlr.de>
#
# SPDX-License-Identifier: BSD-3-Clause

module Ordinary

export compute_dilatation
export compute_weighted_volume
"""
taken from Peridigm -> but adding the bond_damage; this is missing in Peridigm, but should be there
"""
function compute_weighted_volume(nodes::Union{SubArray,Vector{Int64}}, nlist::SubArray, undeformed_bond::SubArray, bond_damage::SubArray, omega::SubArray, volume::SubArray)

    if length(nodes) == 0
        return Float64[]
    end
    weighted_volume::Vector{Float64} = zeros(Float64, maximum(nodes))

    for iID in nodes
        # in Peridigm the weighted volume is for some reason independend from damages
        @inbounds weighted_volume[iID] = sum(omega[iID][:] .* bond_damage[iID][:] .* undeformed_bond[iID][:, end] .* undeformed_bond[iID][:, end] .* volume[nlist[iID][:]])

    end
    # @. weighted_volume[nodes] = sum(omega[nodes][:] .* bond_damage[nodes][:] .* undeformed_bond[nodes][:, end] .* bond_damage[nodes][:] .* undeformed_bond[nodes][:, end] .* volume[nlist[nodes][:]], dims=2)
    return weighted_volume
end


"""
    calculate_symmetry_params(symmetry::String, shear_modulus::Float64, bulk_modulus::Float64)

Calculate the shear modulus, bulk modulus and three bulk modulus for the given symmetry.

# Arguments
- symmetry: symmetry of the material
- shear_modulus: shear modulus
- bulk_modulus: bulk modulus

# Returns
- alpha: alpha
- gamma: gamma
- kappa: kappa
"""
function calculate_symmetry_params(symmetry::String, shear_modulus::Float64, bulk_modulus::Float64)
    three_bulk_modulus = 3 * bulk_modulus
    # from Peridigm damage model. to be checked with literature
    if symmetry == "plane stress"
        return 8 * shear_modulus, 4.0 * shear_modulus / (three_bulk_modulus + 4.0 * shear_modulus), 4.0 * bulk_modulus * shear_modulus / (three_bulk_modulus + 4.0 * shear_modulus)
    elseif symmetry == "plane strain"
        return 8 * shear_modulus, 2 / 3, (12.0 * bulk_modulus - 4.0 * shear_modulus) / 9
    else
        return 15 * shear_modulus, 1, three_bulk_modulus
    end
end

"""
    compute_dilatation(nodes::Union{SubArray,Vector{Int64}}, nneighbors::SubArray, nlist::SubArray, undeformed_bond::SubArray, deformed_bond::SubArray, bond_damage::SubArray, volume::SubArray, weighted_volume::Vector{Float64}, omega::SubArray, theta::SubArray)

Calculate the dilatation for each node.

# Arguments
- `nodes::Union{SubArray,Vector{Int64}}`: Nodes.
- `nneighbors::SubArray`: Number of neighbors.
- `nlist::SubArray`: Neighbor list.
- `undeformed_bond::SubArray`: Bond geometry.
- `deformed_bond::SubArray`: Deformed bond geometry.
- `bond_damage::SubArray`: Bond damage.
- `volume::SubArray`: Volume.
- `weighted_volume::SubArray`: Weighted volume.
- `omega::SubArray`: Influence function.
- `theta::SubArray`: Dilatation.
# Returns
- `theta::Vector{Float64}`: Dilatation.
"""
function compute_dilatation(nodes::Union{SubArray,Vector{Int64}}, nneighbors::SubArray, nlist::SubArray, undeformed_bond::SubArray, deformed_bond::SubArray, bond_damage::SubArray, volume::SubArray, weighted_volume::Vector{Float64}, omega::SubArray)
    # not optimal, because of many zeros, but simpler, because it avoids reorganization. Part of potential optimization
    if length(nodes) == 0
        return Float64[]
    end
    theta::Vector{Float64} = zeros(Float64, maximum(nodes))
    for iID in nodes
        if weighted_volume[iID] == 0
            # @warn "Weighted volume is zero for local point ID: $iID"
            theta[iID] = 0
            continue
        end
        @inbounds theta[iID] = 3.0 * sum(omega[iID][jID] *
                                         bond_damage[iID][jID] * undeformed_bond[iID][jID, end] *
                                         (deformed_bond[iID][jID, end] - undeformed_bond[iID][jID, end]) *
                                         volume[nlist[iID][jID]] / weighted_volume[iID]
                                         for jID in 1:nneighbors[iID])
    end
    return theta
end
# function compute_dilatation(nodes::Union{SubArray,Vector{Int64}}, nneighbors::SubArray, nlist::SubArray, undeformed_bond::SubArray, deformed_bond::SubArray, bond_damage::SubArray, volume::SubArray, weighted_volume::SubArray, omega::SubArray, theta::SubArray)
#     # not optimal, because of many zeros, but simpler, because it avoids reorganization. Part of potential optimization
#     @. begin
#         if weighted_volume[nodes] == 0
#             @warn "Weighted volume is zero for local point ID: $nodes"
#             theta[nodes] = 0
#         else
#             theta[nodes] = 3.0 * sum(omega[nodes, :] .* bond_damage[nodes, :] .* undeformed_bond[nodes, :, end] .* (deformed_bond[nodes, :, end] - undeformed_bond[nodes, :, end]) .* volume[nlist[nodes, :]] / weighted_volume[nodes], dims=2)
#         end
#     end
#     return theta
# end



end