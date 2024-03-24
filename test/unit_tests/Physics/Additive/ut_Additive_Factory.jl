# SPDX-FileCopyrightText: 2023 Christian Willberg <christian.willberg@dlr.de>, Jan-Timo Hesse <jan-timo.hesse@dlr.de>
#
# SPDX-License-Identifier: BSD-3-Clause

include("../../../../src/Physics/Additive/Additive_Factory.jl")
# include("../../../../src/Support/data_manager.jl")


using Test
using .Additive



@testset "init_additive_model_fields" begin
    test_Data_manager = PeriLab.Data_manager
    test_Data_manager.clear_data_manager()
    test_Data_manager.set_dof(3)
    test_Data_manager.set_num_controller(4)
    nn = test_Data_manager.create_constant_node_field("Number of Neighbors", Int64, 1)
    nn[1] = 2
    nn[2] = 3
    nn[3] = 1
    nn[4] = 2
    nlist = test_Data_manager.create_constant_bond_field("Neighborhoodlist", Int64, 1)
    nlist[1] = [2]
    nlist[2] = [1, 3]
    nlist[3] = [1]
    nlist[4] = [1, 3]
    test_Data_manager.create_bond_field("Bond Damage", Float64, 1)
    test_Data_manager = Additive.init_additive_model_fields(test_Data_manager)
    fieldkeys = test_Data_manager.get_all_field_keys()
    @test "Active" in fieldkeys
    active = test_Data_manager.get_field("Active")
    for iID in 1:4
        @test active[iID] == false
    end
end

@testset "init_additive" begin
    test_Data_manager = PeriLab.Data_manager
    test_Data_manager.properties[23] = Dict("Additive Model" => Dict("Additive Model" => "does not exist"))
    @test isnothing(Additive.init_additive_model(test_Data_manager, Vector{Int64}([1, 2, 3]), 23))
end