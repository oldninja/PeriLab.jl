include("../parameter_handling.jl")
using Test
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

#@testset "ut_get_output_filenames" begin
params = Dict()
filenames = get_output_filenames(params)
@test filenames == []
params = Dict("Output" => Dict("Output1" => Dict("Output Filename" => "1.e"), "Output2" => Dict("Output Filename" => "2.e")))
filenames = get_output_filenames(params)
@test filenames[1] == "1.e"
@test filenames[2] == "2.e"
#end