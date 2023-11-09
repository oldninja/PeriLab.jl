# SPDX-FileCopyrightText: 2023 Christian Willberg <christian.willberg@dlr.de>, Jan-Timo Hesse <jan-timo.hesse@dlr.de>
#
# SPDX-License-Identifier: BSD-3-Clause

module Bond_Deformation
include("../../Support/geometry.jl")
using .Geometry
export compute

function compute(datamanager, nodes, time)
    dof = datamanager.get_dof()
    nlist = datamanager.get_nlist()
    deformed_coor = datamanager.get_field("Deformed Coordinates", "NP1")
    bond_defNP1 = datamanager.get_field("Deformed Bond Geometry", "NP1")
    bond_defNP1 = Geometry.bond_geometry(nodes, dof, nlist, deformed_coor, bond_defNP1)
    return datamanager
end


end