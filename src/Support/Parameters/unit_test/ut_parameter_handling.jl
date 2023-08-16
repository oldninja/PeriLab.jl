include("../parameter_handling.jl")
include("../../data_manager.jl")
using Test
import .Data_manager
using Random

@testset "ut_check_key_elements" begin
    params = Dict()
    @info "Error messages are tested and therefore okay."
    @test check_key_elements(params) == false
    params = Dict("Damage" => Dict())
    @test check_key_elements(params) == false
    params = Dict("Damage" => Dict(), "Materials" => Dict())
    @test check_key_elements(params) == false
    params = Dict("Damage" => Dict(), "Materials" => Dict(), "Discretization" => Dict())
    @test check_key_elements(params) == false
    params = Dict("Damage" => Dict(), "Materials" => Dict(), "Discretization" => Dict(), "Blocks" => Dict())
    @test check_key_elements(params) == false
    @info "No error messages are okay for this test until now."
    params = Dict("Damage" => Dict(), "Materials" => Dict(), "Discretization" => Dict(), "Blocks" => Dict(), "Solver" => Dict())
    @test check_key_elements(params) == true
end

@testset "ut_get_mesh_name" begin
    params = Dict("Discretization" => Dict())
    @test get_mesh_name(params) === nothing
    name = randstring(12)
    params = Dict("Discretization" => Dict("Input Mesh File" => name))
    @test get_mesh_name(params) == name
end

@testset "ut_search_for_duplicates" begin
    filenames = ["a", "b", "c"]
    newfilenames = search_for_duplicates(filenames)
    for i in 1:3
        @test filenames[i] == newfilenames[i]
    end
    filenames = ["a", "b", "b", "b", "a", "c"]
    newfilenames = search_for_duplicates(filenames)
    @test newfilenames[1] == "a_1"
    @test newfilenames[2] == "a_2"
    @test newfilenames[3] == "b_1"
    @test newfilenames[4] == "b_2"
    @test newfilenames[5] == "b_3"
    @test newfilenames[6] == "c"
end

@testset "ut_get_output_filenames" begin
    params = Dict()
    filenames = get_output_filenames(params)
    @test filenames == []
    params = Dict("Output" => Dict("Output1" => Dict("Output Filename" => "1.e"), "Output2" => Dict("Output Filename" => "2.e")))
    filenames = get_output_filenames(params)
    @test filenames[1] == "1.e"
    @test filenames[2] == "2.e"
end
@testset "ut_get_outputs" begin
    testDatamanager = Data_manager
    testDatamanager.set_nnodes(5)
    testDatamanager.create_constant_node_field("A", Float32, 1)
    testDatamanager.create_node_field("B", Bool, 1)
    testDatamanager.create_constant_node_field("C", Float32, 4)
    testDatamanager.create_node_field("D", Int64, 7)
    testDatamanager.create_node_field("F", Float32, 1)
    testDatamanager.create_constant_node_field("E", Float32, 4)
    testfield_keys = testDatamanager.get_all_field_keys()

    params = Dict("Output" => Dict("Output1" => Dict("Output Variables" => Dict("A" => true, "B" => false, "C" => true)), "Output2" => Dict("Output Variables" => Dict("A" => true, "B" => true, "D" => false, "E" => true))))

    outputs = get_outputs(params, testfield_keys)

    @test "A" in outputs["Output1"]
    @test ("B" in outputs["Output1"]) == false
    @test "C" in outputs["Output1"]
    @test "A" in outputs["Output2"]
    @test "B" in outputs["Output2"]
    @test ("D" in outputs["Output2"]) == false
    @test "E" in outputs["Output2"]
end
@testset "ut_node_sets" begin
    numbers = [11, 12, 13, 44, 125]
    lenNumbers = length(numbers)
    filename = "test.txt"
    file = open(filename, "w")
    for number in numbers
        println(file, number)
    end
    close(file)

    params = Dict("Discretization" => Dict("Node Sets" => Dict("Nset_1" => "1 2 3 4 5 6 7", "Nset_2" => filename)))
    nsets = get_node_sets(params)
    @test "Nset_1" in keys(nsets)
    @test "Nset_2" in keys(nsets)
    @test length(nsets["Nset_1"]) == 7
    for i in 1:7
        @test nsets["Nset_1"][i] == i
    end
    @test length(nsets["Nset_2"]) == lenNumbers
    for i in 1:lenNumbers
        @test nsets["Nset_2"][i] == numbers[i]
    end
    rm(filename)
end
@testset "ut_get_bc_definitions" begin
    params = Dict()
    bcs = get_bc_definitions(params)
    @test length(bcs) == 0
    params = Dict("Boundary Conditions" => Dict())
    bcs = get_bc_definitions(params)
    @test length(bcs) == 0
    params = Dict("Boundary Conditions" => Dict("BC_1" => Dict("Type" => "Force", "Node Set" => "Nset_1", "Coordinate" => "x", "Value" => "20*t"), "BC_2" => Dict("Type" => "Displacement", "Node Set" => "Nset_2", "Coordinate" => "y", "Value" => "0")))
    bcs = get_bc_definitions(params)
    @test length(bcs) == 2
    @test bcs["BC_1"] == Dict("Type" => "Force", "Node Set" => "Nset_1", "Coordinate" => "x", "Value" => "20*t")
    @test bcs["BC_2"] == Dict("Type" => "Displacement", "Node Set" => "Nset_2", "Coordinate" => "y", "Value" => "0")
end
#@testset "ut_get_solver_options" begin
params = Dict("Solver" => Dict("Material" => true, "Damage" => true, "Additive" => true, "Thermal" => true))
solver_options = get_solver_options(params)
@test solver_options["Additive"]
@test solver_options["Damage"]
@test solver_options["Material"]
@test solver_options["Thermal"]
params = Dict("Solver" => Dict())
solver_options = get_solver_options(params)
@test solver_options["Additive"] == false
@test solver_options["Damage"] == false
@test solver_options["Material"]
@test solver_options["Thermal"] == false

params = Dict("Solver" => Dict("Material" => false, "Damage" => true, "Thermal" => true))
solver_options = get_solver_options(params)
@test solver_options["Additive"] == false
@test solver_options["Damage"]
@test solver_options["Material"] == false
@test solver_options["Thermal"]
#end