# SPDX-FileCopyrightText: 2023 Christian Willberg <christian.willberg@dlr.de>, Jan-Timo Hesse <jan-timo.hesse@dlr.de>
#
# SPDX-License-Identifier: BSD-3-Clause
using Test

include("../../../../src/Physics/Thermal/Thermal_Factory.jl")
using .Thermal
include("../../../../src/Support/data_manager.jl")

@testset "ut_distribute_heat_flows" begin

    nnodes = 2
    nodes = Vector{Int64}(1:nnodes)
    dof = 2
    testDatamanager = Data_manager
    testDatamanager.set_nmasters(2)
    nn = testDatamanager.create_constant_node_field("Number of Neighbors", Int64, 1)
    volume = testDatamanager.create_constant_node_field("Volume", Float64, 1)

    nn[1] = 1
    nn[2] = 1
    volume[1:2] .= 1

    nlist = testDatamanager.create_constant_bond_field("Neighborhoodlist", Int64, 1)
    nlist[1][1] = 2
    nlist[2][1] = 1

    (heat_flowN, heat_flowNP1) = testDatamanager.create_node_field("Heat Flow", Float64, 1)
    bond_heat_flow = testDatamanager.create_constant_bond_field("Bond Heat Flow", Float64, 1)
    bond_heat_flow[1][1] = 1
    bond_heat_flow[2][1] = 1

    testDatamanager = Thermal.distribute_heat_flows(testDatamanager, nodes)

    @test heat_flowNP1[1] == 0
    @test heat_flowNP1[2] == 0
    heat_flowNP1[1:2] .= 0
    bond_heat_flow[1][1] = 1
    bond_heat_flow[2][1] = -1

    testDatamanager = Thermal.distribute_heat_flows(testDatamanager, nodes)

    @test heat_flowNP1[1] == -2
    @test heat_flowNP1[2] == 2

    volume[2] = 0

    testDatamanager = Thermal.distribute_heat_flows(testDatamanager, nodes)

    @test heat_flowNP1[1] == -2
    @test heat_flowNP1[2] == 4
end
