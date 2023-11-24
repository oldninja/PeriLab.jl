# SPDX-FileCopyrightText: 2023 Christian Willberg <christian.willberg@dlr.de>, Jan-Timo Hesse <jan-timo.hesse@dlr.de>
#
# SPDX-License-Identifier: BSD-3-Clause
include("../../../../src/FEM/FEM_routines.jl")
include("../../../../src/FEM/Element_formulation/lagrange_element.jl")

using Test

@testset "ut_get_weights_and_integration_points" begin
    @test isnothing(define_lagarangian_grid_space(2, [0, 0]))
    @test isnothing(define_lagarangian_grid_space(3, [0, 0, 0]))
    @test isnothing(define_lagarangian_grid_space(3, [0, 1, 0]))
    @test isnothing(define_lagarangian_grid_space(3, [1, 1, 0]))
    @test define_lagarangian_grid_space(2, [1, 1]) == [-1.0 1.0; -1.0 1.0]
    @test define_lagarangian_grid_space(3, [1, 1, 1]) == [-1.0 1.0; -1.0 1.0; -1.0 1.0]
    @test define_lagarangian_grid_space(2, [1, 2]) == [-1.0 1.0 0.0; -1.0 0.0 1.0]
    @test define_lagarangian_grid_space(2, [1, 4]) == [-1.0 1.0 0.0 0.0 0.0; -1.0 -0.5 0.0 0.5 1.0]
    @test define_lagarangian_grid_space(3, [2, 2, 1]) == [-1.0 0.0 1.0; -1.0 0.0 1.0; -1.0 1.0 0.0]
    @test define_lagarangian_grid_space(3, [2, 1, 1]) == [-1.0 0.0 1.0; -1.0 1.0 0.0; -1.0 1.0 0.0]
    @test define_lagarangian_grid_space(3, [2, 1, 3]) == [-1.0 0.0 1.0 0.0; -1.0 1.0 0.0 0.0; -1.0 -0.33333333333333337 0.33333333333333326 1.0]
end
@testset "ut_get_recursive_lagrange_shape_functions" begin
    p = 1
    xi = define_lagarangian_grid_space(2, [p, p])
    @test get_recursive_lagrange_shape_functions(xi[1, :], 0.0, p) == [0.5, 0.5]
    weights, integration_points = get_weights_and_integration_points(2, [p, p])
    @test get_recursive_lagrange_shape_functions(xi[1, :], integration_points[1, 1], p) == [0.7886751345948129, 0.21132486540518708]
    @test get_recursive_lagrange_shape_functions(xi[1, :], integration_points[1, 2], p) == [0.21132486540518708, 0.7886751345948129]
    p = 2
    weights, integration_points = get_weights_and_integration_points(2, [p, p])
    xi = define_lagarangian_grid_space(2, [p, p])
    @test get_recursive_lagrange_shape_functions(xi[1, :], integration_points[1, 1], p) == [0.6872983346207417, 0.39999999999999997, -0.08729833462074169]
    @test get_recursive_lagrange_shape_functions(xi[1, :], integration_points[1, 2], p) == [0.0, 1.0, 0.0]
    @test get_recursive_lagrange_shape_functions(xi[1, :], integration_points[1, 3], p) == [-0.08729833462074169, 0.39999999999999997, 0.6872983346207417]
    p = 3
    weights, integration_points = get_weights_and_integration_points(2, [p, p])
    xi = define_lagarangian_grid_space(2, [p, p])
    @test get_recursive_lagrange_shape_functions(xi[1, :], integration_points[1, 1], p) == [0.6600056650728034, 0.5209376877117036, -0.23018790325073893, 0.04924455046623181]
    @test get_recursive_lagrange_shape_functions(xi[1, :], integration_points[1, 2], p) == [0.0033737364327725374, 1.0048858548256456, -0.009921353572324671, 0.0016617623139063968]
    @test get_recursive_lagrange_shape_functions(xi[1, :], integration_points[1, 3], p) == [0.0016617623139064258, -0.009921353572324838, 1.0048858548256463, 0.003373736432772594]
    @test get_recursive_lagrange_shape_functions(xi[1, :], integration_points[1, 4], p) == [0.04924455046623184, -0.23018790325073904, 0.5209376877117036, 0.6600056650728034]
end


@testset "ut_get_recursive_lagrange_shape_functions_derivative" begin
    p = 1
    xi = define_lagarangian_grid_space(2, [p, p])
    @test get_recursive_lagrange_shape_functions_derivative(xi[1, :], 0.0, p) == [-0.5, 0.5]
    weights, integration_points = get_weights_and_integration_points(2, [p, p])
    @test get_recursive_lagrange_shape_functions_derivative(xi[1, :], integration_points[1, 1], p) == [-0.5, 0.5]
    @test get_recursive_lagrange_shape_functions_derivative(xi[1, :], integration_points[1, 2], p) == [-0.5, 0.5]
    p = 2
    weights, integration_points = get_weights_and_integration_points(2, [p, p])
    xi = define_lagarangian_grid_space(2, [p, p])
    @test get_recursive_lagrange_shape_functions_derivative(xi[1, :], integration_points[1, 1], p) == [-1.2745966692414834, 1.5491933384829668, -0.2745966692414834]
    @test get_recursive_lagrange_shape_functions_derivative(xi[1, :], integration_points[1, 2], p) == [-0.5, 0.0, 0.5]
    @test get_recursive_lagrange_shape_functions_derivative(xi[1, :], integration_points[1, 3], p) == [0.2745966692414834, -1.5491933384829668, 1.2745966692414834]
    p = 3
    weights, integration_points = get_weights_and_integration_points(2, [p, p])
    xi = define_lagarangian_grid_space(2, [p, p])
    println()
    @test get_recursive_lagrange_shape_functions_derivative(xi[1, :], integration_points[1, 1], p) == [-2.157653673851862, 3.035404320468968, -1.0978476193823496, 0.22009697276524381]
    @test get_recursive_lagrange_shape_functions_derivative(xi[1, :], integration_points[1, 2], p) == [-0.5150319221529817, -0.7198615816069815, 1.484818929672908, -0.2499254259129448]
    @test get_recursive_lagrange_shape_functions_derivative(xi[1, :], integration_points[1, 3], p) == [0.249925425912945, -1.4848189296729082, 0.7198615816069811, 0.5150319221529819]
    @test get_recursive_lagrange_shape_functions_derivative(xi[1, :], integration_points[1, 4], p) == [-0.22009697276524398, 1.09784761938235, -3.035404320468968, 2.1576536738518617]
end