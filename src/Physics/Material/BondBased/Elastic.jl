module Elastic_bond_based


function calculate_bond_forces(datamanager)
    initial_bond_length = datamanager.get_field("Bond Geometry")
    deformed_bond_length = datamanager.get_field("Deformed Bond Geometry")
    t = datamanager.get_field("Bond Forces")
    nnodes = datamanager.get_nnodes()
    nlist = datamanager.get_nlist()
    dof = datamanager.get_dof()
    bondNumber = 0
    for iID in 1:nnodes
        nneighbors = length(nlist[iID])
        for jID in 1:nneighbors
            bondNumber += 1

            stretch = (deformed_bond_length[bondNumber] - initial_bond_length[bondNumber]) / deformed_bond_length[bondNumber]
            t[bondNumber] = 0.5 * (1 - bondDamageNP1[bondNumber]) * stretch * constant
        end
    end
    return datamanager
end
end