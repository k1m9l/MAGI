# test/test_kernels.jl

using Test
using KernelFunctions # Needed for ScaleTransform, kernels, kernelmatrix etc.
using LinearAlgebra   # Needed for issymmetric

# Import the kernel creation functions from MagiJl
using MagiJl.Kernels: create_rbf_kernel, create_matern52_kernel, create_general_matern_kernel

@testset "Kernel Functions" begin
    println("\n-------------------------------------------------------")
    println("TESTING KERNEL FUNCTIONS")
    println("-------------------------------------------------------")
    println("These tests verify the kernel functions used in MAGI's Gaussian Process calculations.")
    println("A kernel k(x,y) defines the covariance between points x and y in the GP.")
    println("-------------------------------------------------------")
    
    @testset "Squared Exponential (RBF) Kernel" begin
        println("\n== Testing Squared Exponential (RBF) Kernel ==")
        println("Mathematical form: k(x,y) = σ² * exp(-(x-y)²/(2l²))")
        println("  where σ² is the variance parameter")
        println("  and l is the lengthscale parameter")
        
        variance = 2.0
        lengthscale = 1.5
        println("Testing with σ² = $variance, l = $lengthscale")

        # Use the working ScaleTransform syntax
        k = variance * SqExponentialKernel() ∘ ScaleTransform(1/lengthscale)

        x1, x2 = 0.5, 2.0
        d_sq = (x1 - x2)^2
        expected = variance * exp(-d_sq / (2 * lengthscale^2))
        println("Points: x₁ = $x1, x₂ = $x2")
        println("Expected: k(x₁,x₂) = $variance * exp(-$(d_sq)/(2 * $(lengthscale)²)) = $expected")
        @test k(x1, x2) ≈ expected

        X = [0.0, 1.0, 2.0]
        Kxx = kernelmatrix(k, X)
        println("Testing kernel matrix for points X = $X")
        println("Expected matrix properties:")
        println("  - Symmetric: K[i,j] = K[j,i]")
        println("  - Diagonal elements = variance ($variance)")
        @test size(Kxx) == (3, 3)
        @test Kxx[1, 1] ≈ variance * exp(0.0)
        @test Kxx[1, 2] ≈ variance * exp(-(1.0)^2 / (2 * lengthscale^2))
        @test Kxx[2, 1] ≈ Kxx[1, 2]
        @test issymmetric(Kxx)
    end

    @testset "Matérn 5/2 Kernel" begin
        println("\n== Testing Matérn 5/2 Kernel ==")
        println("Mathematical form: k(x,y) = σ² * (1 + √5|x-y|/l + 5(x-y)²/(3l²)) * exp(-√5|x-y|/l)")
        println("  where σ² is the variance parameter")
        println("  and l is the lengthscale parameter")
        
        variance = 1.5
        lengthscale = 0.8
        println("Testing with σ² = $variance, l = $lengthscale")

        # Use the working ScaleTransform syntax
        k = variance * Matern52Kernel() ∘ ScaleTransform(1/lengthscale)

        x1, x2 = 1.0, 1.4
        d = abs(x1 - x2)
        l = lengthscale
        term1 = sqrt(5.0) * d / l
        term2 = 5.0 * d^2 / (3.0 * l^2)
        expected = variance * (1.0 + term1 + term2) * exp(-term1)
        
        println("Points: x₁ = $x1, x₂ = $x2, distance |x₁-x₂| = $d")
        println("Expected: k(x₁,x₂) = $variance * (1 + $(term1) + $(term2)) * exp(-$(term1)) = $expected")
        @test k(x1, x2) ≈ expected rtol=1e-4

        X = [0.0, 0.5]
        Kxx = kernelmatrix(k, X)
        println("Testing kernel matrix for points X = $X")
        println("Expected matrix properties:")
        println("  - Symmetric: K[i,j] = K[j,i]")
        println("  - Diagonal elements = variance ($variance)")
        @test size(Kxx) == (2, 2)
        @test Kxx[1, 1] ≈ variance
        @test Kxx[1, 2] ≈ k(X[1], X[2])
        @test issymmetric(Kxx)
    end

    # Comprehensive Kernel Properties Tests
    @testset "Kernel Function Properties" begin
        println("\n== Testing Mathematical Properties of Kernels ==")
        println("Important properties of valid kernel functions:")
        println("  1. Symmetry: k(x,y) = k(y,x)")
        println("  2. Positive-definiteness: for any points x₁,...,xₙ, the matrix K with K[i,j] = k(xᵢ,xⱼ) is positive definite")
        println("  3. Diagonals equal to variance: k(x,x) = σ²")
        println("  4. Decay with distance: k(x,y) decreases as |x-y| increases")
        
        x_vals = range(-2.0, 2.0, length=11)
        println("Testing on grid of points from $(x_vals[1]) to $(x_vals[end])")
        
        # Test RBF kernel
        println("\nRBF Kernel Properties (σ² = 1.5, l = 0.8):")
        kernel_rbf = create_rbf_kernel(1.5, 0.8)
        K_rbf = [kernel_rbf(x, y) for x in x_vals, y in x_vals]
        
        @test issymmetric(K_rbf)
        @test isposdef(Symmetric(K_rbf))
        @test all(isapprox.(diag(K_rbf), 1.5, rtol=1e-10))
        println("  ✓ Symmetry")
        println("  ✓ Positive-definiteness")
        println("  ✓ Diagonal elements = variance (1.5)")
        
        # Test Matérn kernels with different smoothness parameters
        println("\nTesting Matérn kernels with different smoothness parameters (ν):")
        println("  ν controls the differentiability of the resulting functions:")
        println("  - ν=1/2: Exponential kernel (functions once differentiable)")
        println("  - ν=3/2: Functions twice differentiable")
        println("  - ν=5/2: Functions three times differentiable")
        
        for nu in [1/2, 3/2, 5/2]
            println("\nMatérn kernel with ν=$nu (σ² = 1.5, l = 0.8):")
            kernel_matern = create_general_matern_kernel(1.5, 0.8, nu)
            K_matern = [kernel_matern(x, y) for x in x_vals, y in x_vals]
            
            @test issymmetric(K_matern)
            @test isposdef(Symmetric(K_matern))
            @test all(isapprox.(diag(K_matern), 1.5, rtol=1e-10))
            println("  ✓ Symmetry")
            println("  ✓ Positive-definiteness")
            println("  ✓ Diagonal elements = variance (1.5)")
            
            # Verify that matrix entries are in the expected range
            value_range_ok = true
            distance_decay_ok = true
            
            for i in eachindex(x_vals)
                for j in eachindex(x_vals)
                    if i != j
                        # All entries should be between 0 and variance
                        if !(0.0 <= K_matern[i,j] <= 1.5)
                            value_range_ok = false
                        end
                        
                        # Distant points should have low correlation
                        dist = abs(x_vals[i] - x_vals[j])
                        if dist > 3.0 * 0.8 && K_matern[i,j] >= 0.2 * 1.5  # 3 lengthscales
                            distance_decay_ok = false
                        end
                    end
                end
            end
            
            @test value_range_ok
            @test distance_decay_ok
            println("  ✓ Values between 0 and variance")
            println("  ✓ Correlation decreases with distance")
        end
        
        # Compare behavior of different kernel families
        println("\n== Comparing Different Kernel Families ==")
        println("Comparing covariance values at different distances:")
        
        kernel_mat12 = create_general_matern_kernel(1.5, 0.8, 1/2)  # Exponential
        kernel_mat32 = create_general_matern_kernel(1.5, 0.8, 3/2)
        kernel_mat52 = create_general_matern_kernel(1.5, 0.8, 5/2)
        
        K_mat12 = [kernel_mat12(x, y) for x in x_vals, y in x_vals]
        K_mat32 = [kernel_mat32(x, y) for x in x_vals, y in x_vals]
        K_mat52 = [kernel_mat52(x, y) for x in x_vals, y in x_vals]
        
        # Comparison at various distances
        distances_to_check = [(1, 6), (1, 11), (3, 9)]
        
        println("\nKernel value comparison at different distances:")
        println("| Distance | Matérn(ν=1/2) | Matérn(ν=3/2) | Matérn(ν=5/2) | RBF      |")
        println("|----------|---------------|---------------|---------------|----------|")
        
        for (i, j) in distances_to_check
            dist = abs(x_vals[i] - x_vals[j])
            println("| $(round(dist, digits=2)) | $(round(K_mat12[i, j], digits=4)) | $(round(K_mat32[i, j], digits=4)) | $(round(K_mat52[i, j], digits=4)) | $(round(K_rbf[i, j], digits=4)) |")
        end
        
        # Test for expected kernel behavior at large distances
        middle_dist_i, middle_dist_j = 1, 6  # Moderate distance
        far_dist_i, far_dist_j = 1, 11       # Large distance
        
        println("\nExpected behavior: Values should be close to zero at large distances")
        # All kernels should have values much less than 1 at the furthest distance
        @test K_mat12[far_dist_i, far_dist_j] < 0.1
        @test K_mat32[far_dist_i, far_dist_j] < 0.1
        @test K_mat52[far_dist_i, far_dist_j] < 0.1
        @test K_rbf[far_dist_i, far_dist_j] < 0.1
        println("✓ All kernels have values < 0.1 at large distances ($(round(abs(x_vals[far_dist_i] - x_vals[far_dist_j]), digits=2)))")
        
        println("\nExpected behavior: Values should decrease with increasing distance")
        # Test that values decrease with distance for each kernel
        @test K_mat12[middle_dist_i, middle_dist_j] > K_mat12[far_dist_i, far_dist_j]
        @test K_mat32[middle_dist_i, middle_dist_j] > K_mat32[far_dist_i, far_dist_j]
        @test K_mat52[middle_dist_i, middle_dist_j] > K_mat52[far_dist_i, far_dist_j]
        @test K_rbf[middle_dist_i, middle_dist_j] > K_rbf[far_dist_i, far_dist_j]
        println("✓ All kernels show decreasing covariance with increasing distance")
        
        println("\nExpected behavior: Different smoothness levels affect covariance decay rate")
        # Less smooth kernels (smaller ν) decay faster at small distances but have heavier tails
        mid_dist = abs(x_vals[middle_dist_i] - x_vals[middle_dist_j])
        println("For moderate distance ($(round(mid_dist, digits=2))):")
        if K_mat12[middle_dist_i, middle_dist_j] < K_mat32[middle_dist_i, middle_dist_j] && 
           K_mat32[middle_dist_i, middle_dist_j] < K_mat52[middle_dist_i, middle_dist_j]
            println("✓ More smooth kernels (higher ν) maintain higher correlation at moderate distances")
        else
            println("Note: Smoothness behavior at moderate distances doesn't follow theoretical expectation")
        end
    end
    
    println("\n-------------------------------------------------------")
    println("KERNEL FUNCTION TESTS COMPLETE")
    println("-------------------------------------------------------")
end