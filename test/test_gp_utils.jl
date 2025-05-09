# test/test_gp_utils.jl

using Test
using MagiJl.GaussianProcess # Access mat2band (assuming it's exported or qualified)
using BandedMatrices
using LinearAlgebra

@testset "GP Utilities" begin
    println("\n==================================================================")
    println("GAUSSIAN PROCESS UTILITIES TESTS")
    println("==================================================================")
    println("Testing utility functions used in the Gaussian Process implementation,")
    println("focusing on banded matrix operations that improve computational efficiency.")
    println("==================================================================")

    @testset "mat2band Function" begin
        println("\n=== TESTING mat2band FUNCTION ===")
        println("The mat2band function converts a dense matrix to a banded representation.")
        println("A banded matrix with bandwidths (l,u) only stores elements within")
        println("distance l below and u above the main diagonal, setting others to zero.")
        println("This representation is more memory-efficient for matrices with limited bandwidth.")
        
        # Test case 1: Simple 4x4 matrix
        println("\n--- Test Case 1: Simple 4×4 Matrix with Bandwidths (1,1) ---")
        dense_mat = Float64[
            1 2 0 0;
            3 4 5 0;
            0 6 7 8;
            0 0 9 10
        ]
        l, u = 1, 1 # Bandwidths
        
        println("Original matrix:")
        show(stdout, "text/plain", dense_mat)
        println("\n\nBandwidths: lower = $l, upper = $u")
        println("These bandwidths mean we keep only the main diagonal,")
        println("one diagonal below, and one diagonal above.")
        
        # Explicitly qualify the function call
        banded_mat = MagiJl.GaussianProcess.mat2band(dense_mat, l, u)
        
        # Check type and properties
        @test banded_mat isa BandedMatrix
        @test BandedMatrices.bandwidths(banded_mat) == (l, u)
        @test size(banded_mat) == size(dense_mat)
        
        println("\nVerifying banded matrix properties:")
        println("✓ Result is a BandedMatrix with bandwidths ($l,$u)")
        println("✓ Matrix dimensions are preserved: $(size(banded_mat))")
        
        # Print explicit visualization of band structure
        println("\nBand structure visualization (elements that are kept):")
        for i in 1:size(dense_mat, 1)
            for j in 1:size(dense_mat, 2)
                if j-i <= u && i-j <= l
                    print(" ◉  ") # Elements within band
                else
                    print(" ○  ") # Elements outside band
                end
            end
            println()
        end
        
        # Check elements within the band
        println("\nVerifying elements within the band are preserved:")
        band_elements = [
            (1,1,1.0), (1,2,2.0),
            (2,1,3.0), (2,2,4.0), (2,3,5.0),
            (3,2,6.0), (3,3,7.0), (3,4,8.0),
            (4,3,9.0), (4,4,10.0)
        ]
        
        for (i, j, val) in band_elements
            @test banded_mat[i, j] == val
            println("✓ Element ($i,$j) = $(banded_mat[i,j]) (expected $val)")
        end
        
        # Check elements outside the band are zero
        println("\nVerifying elements outside the band are set to zero:")
        outside_band_elements = [
            (1,3), (1,4), (2,4), (3,1), (4,1), (4,2)
        ]
        
        for (i, j) in outside_band_elements
            @test banded_mat[i, j] == 0.0
            println("✓ Element ($i,$j) = $(banded_mat[i,j]) (expected 0.0)")
        end
        
        # Test case 2: Wider bands
        println("\n--- Test Case 2: Matrix with Asymmetric Bandwidths (2,1) ---")
        println("Testing with a larger lower bandwidth (l=2) than upper bandwidth (u=1).")
        println("This represents matrices where we need to store more sub-diagonals than super-diagonals.")
        
        dense_mat2 = reshape(collect(1.0:16.0), 4, 4)
        l2, u2 = 2, 1
        
        println("\nOriginal matrix:")
        show(stdout, "text/plain", dense_mat2)
        println("\n\nBandwidths: lower = $l2, upper = $u2")
        
        banded_mat2 = MagiJl.GaussianProcess.mat2band(dense_mat2, l2, u2)
        @test BandedMatrices.bandwidths(banded_mat2) == (l2, u2)
        
        println("\nVisualizing band structure for (l=$l2, u=$u2):")
        for i in 1:size(dense_mat2, 1)
            for j in 1:size(dense_mat2, 2)
                if j-i <= u2 && i-j <= l2
                    print(" ◉  ") # Elements within band
                else
                    print(" ○  ") # Elements outside band
                end
            end
            println()
        end
        
        # Check specific elements within different parts of the band
        @test banded_mat2[3, 1] == dense_mat2[3, 1] # Within lower band (l=2)
        @test banded_mat2[4, 1] == 0.0              # Outside lower band
        @test banded_mat2[1, 2] == dense_mat2[1, 2] # Within upper band (u=1)
        @test banded_mat2[1, 3] == 0.0              # Outside upper band
        
        println("\nVerifying specific boundary cases:")
        println("✓ Element (3,1) = $(banded_mat2[3,1]) - Within lower band (l=2)")
        println("✓ Element (4,1) = $(banded_mat2[4,1]) - Outside lower band → zero")
        println("✓ Element (1,2) = $(banded_mat2[1,2]) - Within upper band (u=1)")
        println("✓ Element (1,3) = $(banded_mat2[1,3]) - Outside upper band → zero")
        
        # Test case 3: Full bandwidth (no compression)
        println("\n--- Test Case 3: Full Bandwidth (No Compression) ---")
        println("When bandwidths are ≥ size-1, the banded matrix should match the original matrix completely.")
        
        l3, u3 = 3, 3
        banded_mat3 = MagiJl.GaussianProcess.mat2band(dense_mat2, l3, u3)
        @test BandedMatrices.bandwidths(banded_mat3) == (l3, u3)
        
        # Check that all elements are preserved
        all_preserved = banded_mat3 == dense_mat2
        @test all_preserved
        max_diff = maximum(abs.(banded_mat3 - dense_mat2))
        
        println("\nBandwidths: lower = $l3, upper = $u3 (≥ matrix size-1)")
        println("✓ All elements preserved: difference = $max_diff")
        
        # Mathematical significance
        println("\nMathematical Significance:")
        println("In MAGI, banded matrices are crucial for computational efficiency:")
        println("• Storage: O(n*b) vs O(n²) for dense matrices, where b is bandwidth")
        println("• Operations: Matrix-vector multiply is O(n*b) vs O(n²)")
        println("• Inverse calculations also become more efficient")
        println("• This allows handling of larger time series data")
    end

    @testset "mat2band with Various Bandwidths" begin
        println("\n=== TESTING mat2band WITH SPECIAL BANDWIDTH CASES ===")
        println("This test examines extreme cases of bandwidths and their effect on matrix representation.")
        
        test_mat = reshape(1.0:25.0, 5, 5)
        println("\nTest matrix (5×5):")
        show(stdout, "text/plain", test_mat)
        
        # Test with bandwidth = 0 (only diagonal)
        println("\n\n--- Case 1: Bandwidth = 0 (Diagonal Only) ---")
        println("When both bandwidths are 0, only the main diagonal is preserved.")
        println("This is equivalent to a diagonal matrix approximation.")
        
        band0 = MagiJl.GaussianProcess.mat2band(test_mat, 0, 0)
        
        println("\nVisualizing band structure for (l=0, u=0):")
        for i in 1:size(test_mat, 1)
            for j in 1:size(test_mat, 2)
                if i == j
                    print(" ◉  ") # Elements within band (diagonal only)
                else
                    print(" ○  ") # Elements outside band
                end
            end
            println()
        end
        
        # Check diagonal elements
        @test band0[1,1] == 1.0
        @test band0[3,3] == 13.0
        # Check off-diagonal is zero
        @test band0[1,2] == 0.0
        
        println("\nVerifying properties:")
        println("✓ Diagonal elements are preserved: (1,1) = $(band0[1,1]), (3,3) = $(band0[3,3])")
        println("✓ Off-diagonal elements are zero: (1,2) = $(band0[1,2])")
        
        # Mathematical significance of diagonal approximation
        println("\nMathematical Significance:")
        println("A diagonal band (l=0,u=0) approximates a matrix with independent components.")
        println("In MAGI, this would correspond to assuming no correlation between time points.")
        
        # Test with full bandwidth (should preserve original matrix)
        println("\n--- Case 2: Full Bandwidth (No Data Loss) ---")
        println("When bandwidths match or exceed matrix dimensions, all elements are preserved.")
        
        band_full = MagiJl.GaussianProcess.mat2band(test_mat, 4, 4)
        @test band_full == test_mat
        
        max_diff_full = maximum(abs.(band_full - test_mat))
        println("Bandwidths: lower = 4, upper = 4 (= matrix size-1)")
        println("✓ All elements preserved: max difference = $max_diff_full")
        
        # Test with asymmetric bandwidths
        println("\n--- Case 3: Asymmetric Bandwidths ---")
        println("Different lower and upper bandwidths allow for non-symmetric patterns.")
        println("This is useful when correlations have different reach in different directions.")
        
        band_asym = MagiJl.GaussianProcess.mat2band(test_mat, 2, 1)
        
        println("\nVisualizing band structure for (l=2, u=1):")
        for i in 1:size(test_mat, 1)
            for j in 1:size(test_mat, 2)
                if j-i <= 1 && i-j <= 2
                    print(" ◉  ") # Elements within band
                else
                    print(" ○  ") # Elements outside band
                end
            end
            println()
        end
        
        # Test specific elements
        @test band_asym[3,2] == test_mat[3,2] # Within lower band
        @test band_asym[2,3] == test_mat[2,3] # Within upper band
        @test band_asym[4,1] == 0.0 # Outside lower band
        @test band_asym[1,4] == 0.0 # Outside upper band
        
        println("\nVerifying boundary cases:")
        println("✓ Element (3,2) = $(band_asym[3,2]) - Within lower band (l=2)")
        println("✓ Element (2,3) = $(band_asym[2,3]) - Within upper band (u=1)")
        println("✓ Element (4,1) = $(band_asym[4,1]) - Outside lower band → zero")
        println("✓ Element (1,4) = $(band_asym[1,4]) - Outside upper band → zero")
        
        # Mathematical interpretation of asymmetric bands
        println("\nMathematical Interpretation:")
        println("Asymmetric bands can represent directional correlations:")
        println("• In time series: past may influence future more than vice versa")
        println("• In GP context: derivative information might have asymmetric influence")
        println("• Memory optimization: store only most influential correlations")
    end
    
    println("\n==================================================================")
    println("GAUSSIAN PROCESS UTILITIES TESTS COMPLETE")
    println("==================================================================")
end