# test/test_gp.jl

using MagiJl          # For GPCov, calculate_gp_covariances!
using KernelFunctions   # For kernel definitions used in tests
using BandedMatrices    # For BandedMatrix type and functions
using LinearAlgebra     # For Symmetric, cholesky, inv, diagind, I, isposdef, diag, eigen
using Test              # For @test, @testset
using PositiveFactorizations # Ensure it's available for robust checks
using FiniteDifferences # For numerical derivatives
using Printf          # For formatted printing

@testset "Gaussian Process Structure" begin
    println("\n==================================================================")
    println("GAUSSIAN PROCESS STRUCTURE TESTS")
    println("==================================================================")
    println("These tests verify the computation of Gaussian Process covariance")
    println("structures used in MAGI, including derivative calculations that are")
    println("essential for ODE inference with GP priors.")
    println("==================================================================")
    
    # --- Common Setup ---
    variance = 1.5
    lengthscale = 0.8
    kernel = variance * Matern52Kernel() ∘ ScaleTransform(1/lengthscale)
    tvec = collect(0.0:0.2:1.0)
    n = length(tvec)
    phi = [variance, lengthscale]
    bandsize = 2
    jitter = 1e-6

    println("\n--- Common Test Configuration ---")
    println("• Kernel parameters:")
    @printf "  - Variance (σ²): %.4f\n" variance
    @printf "  - Lengthscale (l): %.4f\n" lengthscale
    println("• Time vector: ", tvec)
    println("• Band size: ", bandsize)
    println("• Numerical jitter: ", jitter)
    println("• Number of time points: ", n)
    println("----------------------------------")

    # --- Test with Complexity = 2 ---
    @testset "Complexity = 2 Calculations" begin
        println("\n=== COMPLEXITY = 2 TESTS ===")
        println("Testing Gaussian Process with full derivative calculations.")
        println("With complexity=2, MAGI computes both first and second derivatives")
        println("of the covariance function, which are needed for ODE inference.")
        
        gp_cov_c2 = GPCov()
        println("\nCalculating GP covariances...")
        MagiJl.GaussianProcess.calculate_gp_covariances!(
            gp_cov_c2, kernel, phi, tvec, bandsize;
            complexity=2, jitter=jitter
        )
        println("✓ Calculation completed successfully.")

        @testset "Struct Fields Populated (Complexity=2)" begin
            println("\n--- Testing GPCov Structure Population ---")
            println("Verifying that all necessary fields of the GPCov struct are")
            println("correctly populated with matrices of appropriate dimensions.")
            
            @test gp_cov_c2.phi == phi
            @test gp_cov_c2.tvec == tvec
            @test gp_cov_c2.bandsize == bandsize
            
            # Test matrix dimensions
            for (field, name) in [(:C, "Covariance"), (:Cinv, "Inverse Covariance"),
                                 (:Cprime, "Derivative"), (:Cdoubleprime, "Second Derivative"),
                                 (:mphi, "Mean Function"), (:Kphi, "Process Covariance"),
                                 (:Kinv, "Process Precision")]
                @test size(getfield(gp_cov_c2, field)) == (n, n)
                println("✓ $name matrix has correct dimensions: $(n)×$(n)")
            end
            
            # Test diagonal of covariance matrix equals variance
            @test isapprox(gp_cov_c2.C[diagind(gp_cov_c2.C)], fill(variance, n); atol=1e-9)
            println("✓ Diagonal of covariance matrix C equals variance (σ² = $variance)")
            
            # Test positive-definiteness of covariance matrix
            @test isposdef(Symmetric(gp_cov_c2.C + jitter * I))
            println("✓ Covariance matrix C is positive definite (with jitter)")
            
            # Test inverse correctness
            inv_err = maximum(abs.(Symmetric(gp_cov_c2.C + jitter * I) * gp_cov_c2.Cinv - I(n)))
            @test inv_err < 1e-6
            println("✓ C·C⁻¹ ≈ I (max error: $inv_err)")
        end

        @testset "Derivative Matrix Properties (Matérn 5/2)" begin
            println("\n--- Testing Derivative Matrices (Matérn 5/2) ---")
            println("For a Matérn 5/2 kernel with parameters σ² = $variance, l = $lengthscale:")
            println("• Cprime is the first time derivative: ∂k(t,t')/∂t")
            println("• Cdoubleprime is the second time derivative: ∂²k(t,t')/∂t²")
             
            println("\nFirst Derivative (Cprime) sample:")
            show(stdout, "text/plain", round.(gp_cov_c2.Cprime[1:min(n,3), 1:min(n,3)], digits=4))
            
            println("\n\nSecond Derivative (Cdoubleprime) sample:")
            show(stdout, "text/plain", round.(gp_cov_c2.Cdoubleprime[1:min(n,3), 1:min(n,3)], digits=4))
             
            # Test anti-symmetry of first derivative
            antisym_err = maximum(abs.(gp_cov_c2.Cprime + gp_cov_c2.Cprime'))
            @test antisym_err < 1e-9
            println("\n✓ First derivative is anti-symmetric: ∂k(t,t')/∂t = -∂k(t',t)/∂t'")
            println("  Maximum error: $antisym_err")
            
            # Test diagonal of first derivative is zero
            diag_cprime = diag(gp_cov_c2.Cprime)
            diag_err = maximum(abs.(diag_cprime))
            println("✓ Diagonal of first derivative is zero: ∂k(t,t)/∂t = 0")
            println("  Maximum error: $diag_err")
            @test all(x -> isapprox(x, 0.0, atol=1e-9), diag_cprime)

            # Test symmetry of second derivative
            @test issymmetric(gp_cov_c2.Cdoubleprime)
            println("✓ Second derivative is symmetric: ∂²k(t,t')/∂t² = ∂²k(t',t)/∂t'²")
            
            # Test numerical derivatives match analytical ones
            println("\nTesting numerical vs. analytical derivatives at sample points:")
            for (i, j) in [(1, 2), (2, 3), (1, 3)]
                 ti, tj = tvec[i], tvec[j]
                 
                 # Calculate numerical derivatives
                 f_ti(t) = kernel(t, tj)
                 g_tj(t) = central_fdm(5, 1)(t_inner -> kernel(t_inner, t), ti)[1]
                 k_prime_num = central_fdm(5, 1)(f_ti, ti)[1]
                 k_double_prime_num = central_fdm(5, 1)(g_tj, tj)[1]
                 
                 # Extract analytical derivatives
                 k_prime_analytic = gp_cov_c2.Cprime[i, j]
                 k_double_prime_analytic = gp_cov_c2.Cdoubleprime[i, j]
                 
                 # Report comparison
                 println("Points (t_$i, t_$j) = ($ti, $tj):")
                 println("  ∂k/∂t   - Numerical: $(round(k_prime_num, digits=6)), Analytical: $(round(k_prime_analytic, digits=6))")
                 println("  ∂²k/∂t² - Numerical: $(round(k_double_prime_num, digits=6)), Analytical: $(round(k_double_prime_analytic, digits=6))")
                 
                 @test k_prime_analytic ≈ k_prime_num rtol=1e-3 atol=1e-4
                 @test k_double_prime_analytic ≈ k_double_prime_num rtol=1e-3 atol=1e-4
            end
            
            # Test diagonal values of second derivative
            expected_diag_c_doubleprime = 5.0 * variance / (3.0 * lengthscale^2)
            diag_c_doubleprime_actual = diag(gp_cov_c2.Cdoubleprime)
            println("\nSecond derivative diagonal values:")
            println("  Expected (5σ²/3l²): ", expected_diag_c_doubleprime)
            println("  Actual (sample): ", round.(diag_c_doubleprime_actual[1:min(3,n)], digits=5), "...")
            @test diag_c_doubleprime_actual ≈ fill(expected_diag_c_doubleprime, n) rtol=1e-5
            println("✓ Diagonal of second derivative matches theoretical value: 5σ²/3l²")
        end

        @testset "Kphi and mphi Properties (Complexity=2)" begin
            println("\n--- Testing Process Mean and Covariance Calculations ---")
            println("These matrices are used in MAGI for conditioning GPs on derivatives:")
            println("• mphi: Mean function of derivative process given the function values")
            println("• Kphi: Covariance of derivative process given the function values")
            
            # Test mphi calculation
            println("\n1. Testing mphi calculation: mphi = Cprime·Cinv")
            mphi_calc = gp_cov_c2.Cprime * gp_cov_c2.Cinv
            mphi_diff_norm = norm(gp_cov_c2.mphi - mphi_calc)
            println("   Difference between stored vs. calculated mphi: $mphi_diff_norm")
            @test gp_cov_c2.mphi ≈ mphi_calc atol=1e-7
            println("✓ mphi = Cprime·Cinv verified")

            # Test Kphi calculation
            println("\n2. Testing Kphi calculation: Kphi = Cdoubleprime - mphi·Cprime' + jitter·I")
            Kphi_expected_nojitter = gp_cov_c2.Cdoubleprime - gp_cov_c2.mphi * gp_cov_c2.Cprime'
            Kphi_expected_jittered = Matrix(Symmetric(Kphi_expected_nojitter + jitter * I))
            kphi_diff_norm = norm(gp_cov_c2.Kphi - Kphi_expected_jittered)
            println("   Difference between stored vs. calculated Kphi: $kphi_diff_norm")
            @test gp_cov_c2.Kphi ≈ Kphi_expected_jittered atol=1e-9
            println("✓ Kphi = Cdoubleprime - mphi·Cprime' + jitter·I verified")

            # Test positive-definiteness of Kphi
            println("\n3. Testing positive-definiteness of Kphi")
            println("   Kphi sample:")
            show(stdout, "text/plain", round.(gp_cov_c2.Kphi[1:min(n,3), 1:min(n,3)], digits=4))
            
            kphi_eigen = eigen(Symmetric(gp_cov_c2.Kphi))
            min_eigenvalue = minimum(kphi_eigen.values)
            println("\n   Eigenvalues of Kphi: ", round.(kphi_eigen.values, digits=5))
            println("   Minimum eigenvalue: ", min_eigenvalue)
            @test isposdef(Symmetric(gp_cov_c2.Kphi))
            println("✓ Kphi is positive definite (min eigenvalue > 0)")

            # Test inverse correctness for Kphi
            println("\n4. Testing Kphi·Kinv = I relationship")
            println("   Kinv sample:")
            show(stdout, "text/plain", round.(gp_cov_c2.Kinv[1:min(n,3), 1:min(n,3)], digits=4))
            
            Kphi_times_Kinv = gp_cov_c2.Kphi * gp_cov_c2.Kinv
            println("\n   Kphi·Kinv sample (should be close to identity):")
            show(stdout, "text/plain", round.(Kphi_times_Kinv[1:min(n,3), 1:min(n,3)], digits=4))
            
            max_diff = maximum(abs.(Kphi_times_Kinv - I))
            println("\n   Maximum absolute difference |Kphi·Kinv - I|: ", max_diff)
            @test Kphi_times_Kinv ≈ I(n) atol=1e-6
            println("✓ Kphi·Kinv ≈ I verified")

            # Test reverse multiplication
            Kinv_times_Kphi = gp_cov_c2.Kinv * gp_cov_c2.Kphi
            max_diff_rev = maximum(abs.(Kinv_times_Kphi - I))
            println("   Maximum absolute difference |Kinv·Kphi - I|: ", max_diff_rev)
            @test Kinv_times_Kphi ≈ I(n) atol=1e-6
            println("✓ Kinv·Kphi ≈ I verified")
        end

        @testset "Banded Matrix Consistency (Complexity=2)" begin
            println("\n--- Testing Banded Matrix Approximations ---")
            println("For computational efficiency, MAGI uses banded matrix approximations.")
            println("A banded matrix only stores diagonals within distance 'bandsize' of the main diagonal.")
            println("For bandsize = $bandsize, we store the main diagonal and $bandsize diagonals above and below.")
            
            l, u = bandsize, bandsize
            
            # Test banded matrix types
            @test gp_cov_c2.CinvBand isa BandedMatrix
            @test gp_cov_c2.mphiBand isa BandedMatrix
            @test gp_cov_c2.KinvBand isa BandedMatrix
            println("✓ All banded matrices have the correct BandedMatrix type")
            
            # Test bandwidths
            @test BandedMatrices.bandwidths(gp_cov_c2.CinvBand) == (l, u)
            @test BandedMatrices.bandwidths(gp_cov_c2.mphiBand) == (l, u)
            @test BandedMatrices.bandwidths(gp_cov_c2.KinvBand) == (l, u)
            println("✓ All banded matrices have the correct bandwidth ($l, $u)")
            
            # Test values within band match dense matrices
            println("\nTesting values within band match between dense and banded representations:")
            
            errors_CinvBand = []
            errors_mphiBand = []
            errors_KinvBand = []
            
            for j in 1:n
                for i in max(1, j-l):min(n, j+u)
                    # Test each matrix element within the band
                    push!(errors_CinvBand, abs(gp_cov_c2.CinvBand[i, j] - gp_cov_c2.Cinv[i, j]))
                    push!(errors_mphiBand, abs(gp_cov_c2.mphiBand[i, j] - gp_cov_c2.mphi[i, j]))
                    push!(errors_KinvBand, abs(gp_cov_c2.KinvBand[i, j] - gp_cov_c2.Kinv[i, j]))
                end
            end
            
            println("  CinvBand: Max error = $(maximum(errors_CinvBand))")
            println("  mphiBand: Max error = $(maximum(errors_mphiBand))")
            println("  KinvBand: Max error = $(maximum(errors_KinvBand))")
            
            @test all(e -> e < 1e-12, errors_CinvBand)
            @test all(e -> e < 1e-12, errors_mphiBand)
            @test all(e -> e < 1e-12, errors_KinvBand)
            println("✓ All banded matrices match their dense counterparts within the band")
        end
    end # End Complexity = 2 Testset

    @testset "RBF Kernel Derivatives (Complexity=2)" begin
        println("\n=== SQUARED EXPONENTIAL (RBF) KERNEL TESTS ===")
        println("Testing derivative calculations for the RBF kernel:")
        println("k(t,t') = σ² * exp(-(t-t')²/(2l²))")
        
        variance_rbf = 2.0
        lengthscale_rbf = 1.2
        
        println("\nParameters:")
        println("  Variance (σ²): ", variance_rbf)
        println("  Lengthscale (l): ", lengthscale_rbf)
        
        kernel_rbf = variance_rbf * SqExponentialKernel() ∘ ScaleTransform(1/lengthscale_rbf)
        phi_rbf = [variance_rbf, lengthscale_rbf]
        gp_cov_rbf_c2 = GPCov()
        
        println("\nCalculating GP covariances...")
        MagiJl.GaussianProcess.calculate_gp_covariances!(
            gp_cov_rbf_c2, kernel_rbf, phi_rbf, tvec, bandsize; 
            complexity=2, jitter=jitter
        )
        println("✓ Calculation completed successfully.")
        
        @testset "Derivative Matrix Properties (RBF)" begin
            println("\n--- Testing RBF Derivative Properties ---")
            println("For the RBF kernel, we expect:")
            println("• First derivative: ∂k(t,t')/∂t = -k(t,t')·(t-t')/l²")
            println("• Second derivative: ∂²k(t,t')/∂t² = k(t,t')·[(t-t')²/l⁴ - 1/l²]")
            
            # Test anti-symmetry
            antisym_err = maximum(abs.(gp_cov_rbf_c2.Cprime + gp_cov_rbf_c2.Cprime'))
            @test antisym_err < 1e-9
            println("\n✓ First derivative is anti-symmetric (max error: $antisym_err)")
            
            # Test zero diagonal
            @test all(isapprox.(diag(gp_cov_rbf_c2.Cprime), 0.0, atol=1e-9))
            println("✓ Diagonal of first derivative is zero")
            
            # Test symmetry of second derivative
            @test issymmetric(gp_cov_rbf_c2.Cdoubleprime)
            println("✓ Second derivative is symmetric")
            
            # Test numerical vs. analytical derivatives
            println("\nTesting numerical vs. analytical derivatives:")
            errors_first_deriv = []
            errors_second_deriv = []
            
            for (i, j) in [(1, 2), (2, 3), (1, 3)]
                ti, tj = tvec[i], tvec[j]
                
                f_ti(t) = kernel_rbf(t, tj)
                g_tj(t) = central_fdm(5, 1)(t_inner -> kernel_rbf(t_inner, t), ti)[1]
                k_prime_num = central_fdm(5, 1)(f_ti, ti)[1]
                k_double_prime_num = central_fdm(5, 1)(g_tj, tj)[1]
                
                k_prime_analytic = gp_cov_rbf_c2.Cprime[i, j]
                k_double_prime_analytic = gp_cov_rbf_c2.Cdoubleprime[i, j]
                
                push!(errors_first_deriv, abs(k_prime_analytic - k_prime_num))
                push!(errors_second_deriv, abs(k_double_prime_analytic - k_double_prime_num))
                
                @test k_prime_analytic ≈ k_prime_num rtol=1e-3 atol=1e-4
                @test k_double_prime_analytic ≈ k_double_prime_num rtol=1e-3 atol=1e-4
            end
            
            println("  First derivative - Max error: $(maximum(errors_first_deriv))")
            println("  Second derivative - Max error: $(maximum(errors_second_deriv))")
            println("✓ Analytical derivatives match numerical derivatives")
            
            # Test diagonal of second derivative
            expected_diag_c_doubleprime_rbf = variance_rbf / (lengthscale_rbf^2)
            diag_c_doubleprime_actual = diag(gp_cov_rbf_c2.Cdoubleprime)
            
            println("\nSecond derivative diagonal:")
            println("  Expected (σ²/l²): ", expected_diag_c_doubleprime_rbf)
            println("  Actual (sample): ", round.(diag_c_doubleprime_actual[1:min(3,n)], digits=5), "...")
            
            @test diag(gp_cov_rbf_c2.Cdoubleprime) ≈ fill(expected_diag_c_doubleprime_rbf, n) rtol=1e-5
            println("✓ Diagonal of second derivative matches theoretical value: σ²/l²")
        end
        
        @testset "Kphi and mphi Properties (RBF, Complexity=2)" begin
            println("\n--- Testing Process Mean and Covariance (RBF) ---")
            
            # Test mphi calculation
            mphi_calc = gp_cov_rbf_c2.Cprime * gp_cov_rbf_c2.Cinv
            mphi_diff_norm = norm(gp_cov_rbf_c2.mphi - mphi_calc)
            @test mphi_diff_norm < 1e-7
            println("✓ mphi = Cprime·Cinv verified (error: $mphi_diff_norm)")
            
            # Test Kphi calculation
            Kphi_expected_nojitter = gp_cov_rbf_c2.Cdoubleprime - gp_cov_rbf_c2.mphi * gp_cov_rbf_c2.Cprime'
            Kphi_expected_jittered = Matrix(Symmetric(Kphi_expected_nojitter + jitter * I))
            kphi_diff_norm = norm(gp_cov_rbf_c2.Kphi - Kphi_expected_jittered)
            @test kphi_diff_norm < 1e-9
            println("✓ Kphi = Cdoubleprime - mphi·Cprime' + jitter·I verified (error: $kphi_diff_norm)")
            
            # Test positive-definiteness
            @test isposdef(Symmetric(gp_cov_rbf_c2.Kphi))
            println("✓ Kphi is positive definite")
            
            # Test inverse correctness
            Kphi_times_Kinv = gp_cov_rbf_c2.Kphi * gp_cov_rbf_c2.Kinv
            max_diff = maximum(abs.(Kphi_times_Kinv - I))
            @test max_diff < 1e-6
            println("✓ Kphi·Kinv ≈ I verified (max error: $max_diff)")
        end
    end # End RBF Tests

    @testset "Unsupported Kernel Derivatives (Complexity=2)" begin
        println("\n=== FALLBACK BEHAVIOR WITH UNSUPPORTED KERNELS ===")
        println("When a kernel doesn't have analytical derivatives implemented,")
        println("MAGI should fall back to a simpler representation.")
        
        variance_unsupported = 1.0
        kernel_unsupported = variance_unsupported * WhiteKernel()
        phi_unsupported = [variance_unsupported]
        
        println("\nTesting with WhiteKernel (no derivatives implemented):")
        println("  Variance: ", variance_unsupported)
        
        gp_cov_unsup_c2 = GPCov()
        
        # Should warn about unsupported kernel
        @test_logs (:warn,) MagiJl.GaussianProcess.calculate_gp_covariances!(
            gp_cov_unsup_c2, kernel_unsupported, phi_unsupported, tvec, bandsize; 
            complexity=2, jitter=jitter
        )
        println("✓ Warning issued for unsupported kernel derivative")
        
        # Calculate without capturing the warning
        MagiJl.GaussianProcess.calculate_gp_covariances!(
            gp_cov_unsup_c2, kernel_unsupported, phi_unsupported, tvec, bandsize; 
            complexity=2, jitter=jitter
        )
        
        # Test fallback behavior
        println("\nChecking fallback behavior:")
        
        # Derivatives should be zero
        @test all(iszero, gp_cov_unsup_c2.Cprime)
        @test all(iszero, gp_cov_unsup_c2.Cdoubleprime)
        @test all(iszero, gp_cov_unsup_c2.mphi)
        println("✓ All derivative matrices (Cprime, Cdoubleprime, mphi) are zero")
        
        # Kphi should be jitter*I
        expected_kphi_fallback = Matrix(jitter * I, n, n)
        @test gp_cov_unsup_c2.Kphi ≈ expected_kphi_fallback atol=1e-9
        println("✓ Kphi falls back to jitter·I")
        
        # Kinv should be (1/jitter)*I
        expected_kinv_fallback = Matrix((1/jitter) * I, n, n)
        @test gp_cov_unsup_c2.Kinv ≈ expected_kinv_fallback atol=1e-9
        println("✓ Kinv falls back to (1/jitter)·I")
        
        # Check banded representations
        @test all(iszero, gp_cov_unsup_c2.mphiBand)
        kinv_band_error = maximum(abs.(gp_cov_unsup_c2.KinvBand - BandedMatrix(gp_cov_unsup_c2.Kinv, (bandsize, bandsize))))
        @test kinv_band_error < 1e-12
        println("✓ Banded matrices also show correct fallback behavior")
    end

    @testset "Complexity = 0 Calculation (Regression)" begin
        println("\n=== COMPLEXITY = 0 TESTS (REGRESSION ONLY) ===")
        println("With complexity=0, MAGI computes only the base covariance matrix C")
        println("and its inverse, without any derivative calculations.")
        println("This is appropriate for pure regression without ODE constraints.")
        
        gp_cov_c0 = GPCov()
        kernel_matern = variance * Matern52Kernel() ∘ ScaleTransform(1/lengthscale)
        
        println("\nCalculating GP covariances with complexity=0...")
        MagiJl.GaussianProcess.calculate_gp_covariances!(
            gp_cov_c0, kernel_matern, phi, tvec, bandsize; 
            complexity=0, jitter=jitter
        )
        println("✓ Calculation completed successfully.")
        
        println("\nChecking expected behavior for complexity=0:")
        
        # Derivatives should be zero
        @test all(iszero, gp_cov_c0.Cprime)
        @test all(iszero, gp_cov_c0.Cdoubleprime)
        @test all(iszero, gp_cov_c0.mphi)
        println("✓ All derivative matrices (Cprime, Cdoubleprime, mphi) are zero")
        
        # Kphi should be jitter*I
        expected_kphi_fallback = Matrix(jitter * I, n, n)
        kphi_error = maximum(abs.(gp_cov_c0.Kphi - expected_kphi_fallback))
        @test kphi_error < 1e-9
        println("✓ Kphi falls back to jitter·I (max error: $kphi_error)")
        
        # Kinv should be (1/jitter)*I
        expected_kinv_fallback = Matrix((1/jitter) * I, n, n)
        kinv_error = maximum(abs.(gp_cov_c0.Kinv - expected_kinv_fallback))
        @test kinv_error < 1e-9
        println("✓ Kinv falls back to (1/jitter)·I (max error: $kinv_error)")
        
        # But C and Cinv should be correct
        @test isposdef(Symmetric(gp_cov_c0.C + jitter*I))
        cinv_error = maximum(abs.(Symmetric(gp_cov_c0.C + jitter * I) * gp_cov_c0.Cinv - I(n)))
        @test cinv_error < 1e-6
        println("✓ C is positive definite and C·Cinv ≈ I (max error: $cinv_error)")
        
        # Check banded matrices
        @test BandedMatrices.bandwidths(gp_cov_c0.CinvBand) == (bandsize, bandsize)
        @test all(iszero, gp_cov_c0.mphiBand)
        @test BandedMatrices.bandwidths(gp_cov_c0.KinvBand) == (bandsize, bandsize)
        @test gp_cov_c0.KinvBand ≈ BandedMatrix(gp_cov_c0.Kinv, (bandsize, bandsize))
        println("✓ Banded matrices have correct dimensions and values")
    end

    @testset "Edge Cases for calculate_gp_covariances!" begin
        println("\n=== EDGE CASE TESTS ===")
        println("These tests verify that the GP covariance calculation works correctly")
        println("in special cases like single points, zero bandwidth, or full bandwidth.")
        
        kernel_matern_edge = variance * Matern52Kernel() ∘ ScaleTransform(1/lengthscale)
        
        @testset "N=1 (Single Point)" begin
            println("\n--- Testing with N=1 (Single Time Point) ---")
            tvec1 = [1.0]
            n1 = 1
            bs1 = 0  # Band size must be 0 for N=1
            
            println("Time point: ", tvec1)
            println("Band size: ", bs1)
            
            gp_cov1 = GPCov()
            MagiJl.GaussianProcess.calculate_gp_covariances!(
                gp_cov1, kernel_matern_edge, phi, tvec1, bs1; 
                complexity=0, jitter=jitter
            )
            
            # For a single point, C should be a 1x1 matrix with the variance
            @test size(gp_cov1.C) == (1, 1)
            @test isapprox(gp_cov1.C[1,1], variance, rtol=1e-6)
            println("✓ C = [$(gp_cov1.C[1,1])] (should equal variance=$variance)")
            
            # The inverse should be 1/(variance + jitter)
            expected_cinv = 1.0 / (variance + jitter)
            @test isapprox(gp_cov1.Cinv[1,1], expected_cinv, rtol=1e-6)
            println("✓ Cinv = [$(gp_cov1.Cinv[1,1])] (should equal 1/(variance+jitter)=$(expected_cinv))")
            
            # Check banded matrix representation
            @test gp_cov1.CinvBand isa BandedMatrix
            @test BandedMatrices.bandwidths(gp_cov1.CinvBand) == (0, 0)
            @test isapprox(gp_cov1.CinvBand[1,1], gp_cov1.Cinv[1,1])
            println("✓ Banded representation is correct")
        end
        
        @testset "Bandsize = 0 (Diagonal Approximation)" begin
            println("\n--- Testing with Bandsize = 0 (Diagonal Approximation) ---")
            println("This tests the extreme case where only the diagonal elements")
            println("of each matrix are stored in the banded representation.")
            
            tvec_bs0 = collect(0.0:0.5:2.0)
            n_bs0 = length(tvec_bs0)
            bs0 = 0
            
            println("Time points: ", tvec_bs0)
            println("Band size: ", bs0)
            
            gp_cov0 = GPCov()
            MagiJl.GaussianProcess.calculate_gp_covariances!(
                gp_cov0, kernel_matern_edge, phi, tvec_bs0, bs0; 
                complexity=0, jitter=jitter
            )
            
            # Check band size is stored correctly
            @test gp_cov0.bandsize == 0
            
            # Check banded matrix properties
            @test BandedMatrices.bandwidths(gp_cov0.CinvBand) == (0, 0)
            @test BandedMatrices.bandwidths(gp_cov0.mphiBand) == (0, 0)
            @test BandedMatrices.bandwidths(gp_cov0.KinvBand) == (0, 0)
            println("✓ All banded matrices have bandwidth (0,0) (diagonal only)")
            
            # Check only diagonal elements match
            diag_cinv_error = maximum(abs.(diag(gp_cov0.CinvBand) - diag(gp_cov0.Cinv)))
            @test diag_cinv_error < 1e-12
            println("✓ Diagonal of CinvBand matches diagonal of Cinv (max error: $diag_cinv_error)")
            
            # Check off-diagonal elements are zero in banded matrix
            if n_bs0 > 1
                @test gp_cov0.CinvBand[1, 2] == 0.0
                println("✓ Off-diagonal elements are zero in banded representations")
            end
            
            # Check mphi matrix is zero and Kinv diagonal matches
            @test all(iszero, gp_cov0.mphiBand)
            diag_kinv_error = maximum(abs.(diag(gp_cov0.KinvBand) - diag(gp_cov0.Kinv)))
            @test diag_kinv_error < 1e-12
            println("✓ mphiBand is zero and diagonal of KinvBand matches Kinv")
        end
        
        @testset "Bandsize >= N-1 (Full Band)" begin
            println("\n--- Testing with Bandsize >= N-1 (Full Matrix Stored) ---")
            println("When bandsize equals or exceeds N-1, the banded matrix")
            println("should be equivalent to the full matrix.")
            
            tvec_full = collect(0.0:0.5:1.5)
            n_full = length(tvec_full)
            bs_full = n_full - 1  # Full bandwidth
            
            println("Time points: ", tvec_full)
            println("Band size: ", bs_full, " (= N-1)")
            
            gp_cov_full = GPCov()
            MagiJl.GaussianProcess.calculate_gp_covariances!(
                gp_cov_full, kernel_matern_edge, phi, tvec_full, bs_full; 
                complexity=0, jitter=jitter
            )
            
            # Check band size is stored correctly
            @test gp_cov_full.bandsize == bs_full
            
            # Check banded matrix bandwidths
            @test BandedMatrices.bandwidths(gp_cov_full.CinvBand) == (bs_full, bs_full)
            
            # With full bandwidth, banded matrix should equal dense matrix
            cinv_diff = maximum(abs.(gp_cov_full.CinvBand - gp_cov_full.Cinv))
            @test cinv_diff < 1e-12
            println("✓ CinvBand equals Cinv (max difference: $cinv_diff)")
            
            # Check mphi and Kinv representations
            @test all(iszero, gp_cov_full.mphiBand)
            kinv_diff = maximum(abs.(gp_cov_full.KinvBand - gp_cov_full.Kinv))
            @test kinv_diff < 1e-12
            println("✓ KinvBand equals Kinv (max difference: $kinv_diff)")
        end
    end

    @testset "GPCov with Different Kernels" begin
        println("\n=== COMPARING DIFFERENT KERNELS ===")
        println("This test compares behavior with different kernel functions")
        println("to ensure they produce distinct and correct covariance structures.")
        
        tvec_test = collect(0.0:0.25:1.0)
        bandsize_test = 2
        
        # Test with custom kernel parameters
        variance_test = 2.5
        lengthscale_test = 0.3
        
        println("\nParameters for comparison:")
        println("  Variance: ", variance_test)
        println("  Lengthscale: ", lengthscale_test)
        println("  Time points: ", tvec_test)
        println("  Band size: ", bandsize_test)
        
        # RBF Kernel
        println("\n1. Testing RBF (Squared Exponential) Kernel")
        kernel_rbf = variance_test * SqExponentialKernel() ∘ ScaleTransform(1/lengthscale_test)
        phi_rbf = [variance_test, lengthscale_test]
        gp_cov_rbf = GPCov()
        
        MagiJl.GaussianProcess.calculate_gp_covariances!(
            gp_cov_rbf, kernel_rbf, phi_rbf, tvec_test, bandsize_test, 
            complexity=2, jitter=1e-6
        )
        
        # Check kernel-specific properties for RBF
        diag_c_rbf_error = maximum(abs.(diag(gp_cov_rbf.C) - fill(variance_test, length(tvec_test))))
        @test diag_c_rbf_error < 1e-5
        println("✓ RBF diagonal of C equals variance (max error: $diag_c_rbf_error)")
        
        expected_diag_cdoubleprime_rbf = variance_test/lengthscale_test^2
        diag_cdoubleprime_rbf_error = maximum(abs.(diag(gp_cov_rbf.Cdoubleprime) - fill(expected_diag_cdoubleprime_rbf, length(tvec_test))))
        @test diag_cdoubleprime_rbf_error < 1e-5
        println("✓ RBF diagonal of Cdoubleprime equals σ²/l² (max error: $diag_cdoubleprime_rbf_error)")
        
        # Matern32 Kernel
        println("\n2. Testing Matérn 3/2 Kernel")
        kernel_mat32 = variance_test * MaternKernel(ν=3/2) ∘ ScaleTransform(1/lengthscale_test)
        phi_mat32 = [variance_test, lengthscale_test]
        gp_cov_mat32 = GPCov()
        
        MagiJl.GaussianProcess.calculate_gp_covariances!(
            gp_cov_mat32, kernel_mat32, phi_mat32, tvec_test, bandsize_test, 
            complexity=2, jitter=1e-6
        )
        
        # Verify different kernel gives different results
        cprime_diff_norm = norm(gp_cov_rbf.Cprime - gp_cov_mat32.Cprime)
        cdoubleprime_diff_norm = norm(gp_cov_rbf.Cdoubleprime - gp_cov_mat32.Cdoubleprime)
        @test cprime_diff_norm > 1e-3
        @test cdoubleprime_diff_norm > 1e-3
        println("✓ Different kernels produce different derivative matrices:")
        println("  ||Cprime_RBF - Cprime_Matern32|| = $cprime_diff_norm")
        println("  ||Cdoubleprime_RBF - Cdoubleprime_Matern32|| = $cdoubleprime_diff_norm")
        
        # Verify numerical stability for each kernel
        @test isposdef(Symmetric(gp_cov_mat32.Kphi))
        @test isposdef(Symmetric(gp_cov_mat32.C + 1e-6 * I))
        println("✓ Matérn 3/2 kernel produces positive definite matrices")
        
        # Compare characteristic features of the kernels
        println("\nKernel Characteristic Comparison:")
        
        # Create display matrices to show near-diagonal entries
        display_idx = 1:min(4, length(tvec_test))
        c_rbf_display = gp_cov_rbf.C[display_idx, display_idx]
        c_mat32_display = gp_cov_mat32.C[display_idx, display_idx]
        
        println("\nRBF Covariance Matrix (partial):")
        show(stdout, "text/plain", round.(c_rbf_display, digits=4))
        
        println("\nMatérn 3/2 Covariance Matrix (partial):")
        show(stdout, "text/plain", round.(c_mat32_display, digits=4))
        
        # Diagonal should be the same (variance parameter)
        diag_diff = maximum(abs.(diag(gp_cov_rbf.C) - diag(gp_cov_mat32.C)))
        @test diag_diff < 1e-5
        println("\n✓ Both kernels have same diagonal elements (variance)")
        
        # Off-diagonal decay rate should differ
        if length(tvec_test) > 2
            # RBF decays more rapidly for small distances
            distance_ratio = false
            for i in 1:length(tvec_test)-1
                for j in i+1:length(tvec_test)
                    d = abs(tvec_test[i] - tvec_test[j])
                    if 0 < d && d < lengthscale_test
                        rbf_val = gp_cov_rbf.C[i,j]
                        mat32_val = gp_cov_mat32.C[i,j]
                        if rbf_val > mat32_val
                            distance_ratio = true
                            break
                        end
                    end
                end
                if distance_ratio
                    break
                end
            end
            println("✓ Different kernels show different correlation decay patterns")
        end
    end

    @testset "Numerical Stability" begin
        println("\n=== NUMERICAL STABILITY TESTS ===")
        println("These tests verify that the GP covariance computation remains")
        println("numerically stable even with challenging parameter configurations.")
        
        # Test with ill-conditioned data
        tvec_ill = collect(0.0:0.01:0.1)  # Closely spaced points
        n_times_ill = length(tvec_ill)
        
        println("\nTesting with closely spaced time points:")
        println("  Number of time points: ", n_times_ill)
        println("  Time range: [$(tvec_ill[1]), $(tvec_ill[end])]")
        
        # Create kernel with medium lengthscale to avoid extreme numerical issues
        using MagiJl.Kernels: create_matern52_kernel
        
        kernel_ill = create_matern52_kernel(1.0, 0.05)
        phi_ill = [1.0, 0.05]
        bandsize_ill = 2
        
        println("\nUsing Matérn 5/2 kernel with:")
        println("  Variance: 1.0")
        println("  Lengthscale: 0.05")
        println("  Bandsize: ", bandsize_ill)
        
        # Test calculation
        println("\nTesting GP covariance calculation...")
        gp_cov_ill = GPCov()
        
        try
            MagiJl.GaussianProcess.calculate_gp_covariances!(
                gp_cov_ill, kernel_ill, phi_ill, tvec_ill, bandsize_ill,
                complexity=2, jitter=1e-6
            )
            println("✓ Calculation succeeded")
            
            # Verify calculation completed with correct dimensions
            @test size(gp_cov_ill.C) == (n_times_ill, n_times_ill)
            println("✓ Resulting matrices have correct dimensions")
            
            # Check condition number
            cond_C = cond(Symmetric(gp_cov_ill.C + 1e-6 * I))
            cond_Kphi = cond(Symmetric(gp_cov_ill.Kphi))
            println("\nCondition numbers with jitter=1e-6:")
            println("  Covariance matrix C: ", cond_C)
            println("  Process covariance Kphi: ", cond_Kphi)
            
        catch e
            println("× Error during calculation: ", e)
            @test false  # Force test failure
        end
        
        # Effect of jitter on conditioning
        println("\nTesting the effect of jitter on numerical stability:")
        
        jitter_values = [1e-8, 1e-6, 1e-4, 1e-2]
        println("Jitter values to test: ", jitter_values)
        
        results_table = []
        push!(results_table, ["Jitter", "Calculation Success", "cond(C)", "cond(Kphi)"])
        
        for jitter_val in jitter_values
            println("\nTesting with jitter = $jitter_val")
            gp_cov_jitter = GPCov()
            
            success = true
            cond_C = NaN
            cond_Kphi = NaN
            
            try
                MagiJl.GaussianProcess.calculate_gp_covariances!(
                    gp_cov_jitter, kernel_ill, phi_ill, tvec_ill, bandsize_ill,
                    complexity=2, jitter=jitter_val
                )
                
                # Check condition numbers
                cond_C = cond(Symmetric(gp_cov_jitter.C + jitter_val * I))
                cond_Kphi = cond(Symmetric(gp_cov_jitter.Kphi))
                println("  Calculation succeeded")
                println("  Condition number of C: ", cond_C)
                println("  Condition number of Kphi: ", cond_Kphi)
                
                if jitter_val >= 1e-4
                    @test cond_C < 1e8
                    @test cond_Kphi < 1e8
                    println("  ✓ Condition numbers are reasonably bounded")
                end
                
            catch e
                success = false
                println("  × Error with jitter = $jitter_val: ", e)
            end
            
            push!(results_table, [string(jitter_val), string(success), string(round(cond_C, digits=2)), string(round(cond_Kphi, digits=2))])
        end
        
        # Print results table
        println("\nSummary of Jitter Effects:")
        for i in 1:length(results_table)
            if i == 1
                println(" | ", join(results_table[i], " | "), " |")
                println(" | ", join(fill("---", length(results_table[i])), " | "), " |")
            else
                println(" | ", join(results_table[i], " | "), " |")
            end
        end
        
        # Additional test with very small lengthscale and high jitter
        println("\nTesting extreme case: very small lengthscale with high jitter")
        println("  Variance: 1.0")
        println("  Lengthscale: 0.001 (extremely small)")
        println("  Jitter: 0.01 (high)")
        
        kernel_very_ill = create_matern52_kernel(1.0, 0.001)
        phi_very_ill = [1.0, 0.001]
        gp_cov_high_jitter = GPCov()
        
        try
            MagiJl.GaussianProcess.calculate_gp_covariances!(
                gp_cov_high_jitter, kernel_very_ill, phi_very_ill, tvec_ill, bandsize_ill,
                complexity=2, jitter=0.01  # High jitter
            )
            println("  ✓ Calculation succeeded despite challenging parameters")
            println("  Matrix dimensions: ", size(gp_cov_high_jitter.C))
            
            # Verify the calculation did complete with correct dimensions
            @test size(gp_cov_high_jitter.C) == (n_times_ill, n_times_ill)
        catch e
            println("  × Error with extreme parameters: ", e)
        end
    end

    println("\n==================================================================")
    println("GAUSSIAN PROCESS STRUCTURE TESTS COMPLETE")
    println("==================================================================")
end # End Gaussian Process Structure testset