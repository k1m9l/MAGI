# test/test_ode_models.jl

using Test
using MagiJl # Still needed for the ODE value functions if exported directly
using LinearAlgebra
using Statistics # For mean, etc.
using DifferentialEquations # For integrating ODEs

@testset "ODE Models" begin
    println("\n==================================================================")
    println("ODE MODEL FUNCTION TESTS")
    println("==================================================================")
    println("These tests validate the ODE function implementations and their")
    println("derivatives (Jacobians) which are central to the MAGI methodology.")
    println("==================================================================")

    t = 0.0 # Define time once (we use autonomous ODEs where t doesn't matter)

    # --- ODE Value Tests ---
    @testset "FitzHugh-Nagumo ODE" begin
        println("\n=== FITZHUGH-NAGUMO NEURAL MODEL ===")
        println("The FitzHugh-Nagumo model is a 2D simplification of the Hodgkin-Huxley model")
        println("for neuronal excitability, describing action potential generation.")
        println("\nMathematical formulation:")
        println("dV/dt = c(V - V³/3 + R)")
        println("dR/dt = -(1/c)(V - a + bR)")
        println("where:")
        println("  • V: voltage-like variable")
        println("  • R: recovery variable")
        println("  • Parameters: a, b, c")
        
        # Test the ODE function
        u = [1.0, 2.0]  # State vector: V = 1.0, R = 2.0
        p = (0.5, 0.6, 0.7)  # Parameters: a = 0.5, b = 0.6, c = 0.7
        du_actual = similar(u)  # Output buffer
        
        # Manually calculate expected derivatives
        V, R = u
        a, b, c = p
        dV_dt = c * (V - V^3/3 + R)
        dR_dt = -(1/c) * (V - a + b*R)
        du_expected = [dV_dt, dR_dt]
        
        # Calculate using the ODE function
        MagiJl.fn_ode!(du_actual, u, p, t)
        
        # Display results
        println("\nTest parameters:")
        println("  • State: V = $(u[1]), R = $(u[2])")
        println("  • Parameters: a = $(p[1]), b = $(p[2]), c = $(p[3])")
        
        println("\nExpected derivatives:")
        println("  • dV/dt = $(du_expected[1])")
        println("  • dR/dt = $(du_expected[2])")
        
        println("\nCalculated derivatives:")
        println("  • dV/dt = $(du_actual[1])")
        println("  • dR/dt = $(du_actual[2])")
        
        # Test that the results match
        @test du_actual ≈ du_expected
        println("✓ Function calculation matches expected values")
        
        # Test Jacobian with respect to state (dF/dX)
        println("\n--- Testing State Jacobian (dF/dX) ---")
        println("Mathematical form:")
        println("∂(dV/dt)/∂V = c(1 - V²)")
        println("∂(dV/dt)/∂R = c")
        println("∂(dR/dt)/∂V = -1/c")
        println("∂(dR/dt)/∂R = -b/c")
        
        # Calculate expected Jacobian
        J_expected = [
            c*(1-V^2)  c;
            -1/c       -b/c
        ]
        
        # Calculate using the Jacobian function
        J_actual = zeros(2, 2)
        MagiJl.ODEModels.fn_ode_dx!(J_actual, u, p, t)
        
        # Display results
        println("\nExpected Jacobian:")
        display(J_expected)
        
        println("\nCalculated Jacobian:")
        display(J_actual)
        
        # Test that Jacobian matches
        @test J_actual ≈ J_expected
        println("✓ State Jacobian calculation matches expected values")
        
        # Test Jacobian with respect to parameters (dF/dθ)
        println("\n--- Testing Parameter Jacobian (dF/dθ) ---")
        println("Mathematical form:")
        println("∂(dV/dt)/∂a = 0")
        println("∂(dV/dt)/∂b = 0")
        println("∂(dV/dt)/∂c = V - V³/3 + R")
        println("∂(dR/dt)/∂a = 1/c")
        println("∂(dR/dt)/∂b = -R/c")
        println("∂(dR/dt)/∂c = (V - a + bR)/c²")
        
        # Calculate expected parameter Jacobian
        Jp_expected = [
            0.0  0.0  (V - V^3/3.0 + R);
            1/c  -R/c  (V - a + b*R)/c^2
        ]
        
        # Calculate using the parameter Jacobian function
        Jp_actual = MagiJl.ODEModels.fn_ode_dtheta(u, p, t)
        
        # Display results
        println("\nExpected Parameter Jacobian:")
        display(Jp_expected)
        
        println("\nCalculated Parameter Jacobian:")
        display(Jp_actual)
        
        # Test that parameter Jacobian matches
        @test Jp_actual ≈ Jp_expected
        println("✓ Parameter Jacobian calculation matches expected values")
    end

    @testset "Hes1 ODE" begin
        println("\n=== HES1 GENE REGULATORY NETWORK MODEL ===")
        println("The Hes1 model describes oscillatory gene expression in the")
        println("Hes1 transcription factor, with negative feedback regulation.")
        println("\nMathematical formulation:")
        println("dP/dt = -p₁·P·H + p₂·M - p₃·P")
        println("dM/dt = -p₄·M + p₅/(1 + P²)")
        println("dH/dt = -p₁·P·H + p₆/(1 + P²) - p₇·H")
        println("where:")
        println("  • P: Hes1 protein concentration")
        println("  • M: Hes1 mRNA concentration")
        println("  • H: Hes1 repressor concentration")
        println("  • Parameters: p₁, p₂, ..., p₇")
        
        # Test the ODE function
        u = [1.0, 2.0, 3.0]  # State vector: P = 1.0, M = 2.0, H = 3.0
        p = (0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7)  # Parameters
        du_actual = similar(u)  # Output buffer
        
        # Manually calculate expected derivatives
        P, M, H = u
        p1, p2, p3, p4, p5, p6, p7 = p
        dP_dt = -p1*P*H + p2*M - p3*P
        dM_dt = -p4*M + p5/(1 + P^2)
        dH_dt = -p1*P*H + p6/(1 + P^2) - p7*H
        du_expected = [dP_dt, dM_dt, dH_dt]
        
        # Calculate using the ODE function
        MagiJl.hes1_ode!(du_actual, u, p, t)
        
        # Display results
        println("\nTest parameters:")
        println("  • State: P = $(u[1]), M = $(u[2]), H = $(u[3])")
        println("  • Parameters: [$(join(p, ", "))]")
        
        println("\nExpected derivatives:")
        println("  • dP/dt = $(du_expected[1])")
        println("  • dM/dt = $(du_expected[2])")
        println("  • dH/dt = $(du_expected[3])")
        
        println("\nCalculated derivatives:")
        println("  • dP/dt = $(du_actual[1])")
        println("  • dM/dt = $(du_actual[2])")
        println("  • dH/dt = $(du_actual[3])")
        
        # Test that the results match
        @test du_actual ≈ du_expected
        println("✓ Function calculation matches expected values")
    end

    @testset "LogTransformed Hes1 ODE" begin
        println("\n=== LOG-TRANSFORMED HES1 MODEL ===")
        println("For numerical stability, we often work with log-transformed state variables.")
        println("This transforms the ODE system to work with logP, logM, logH instead of P, M, H.")
        println("\nMathematical transformation:")
        println("d(logP)/dt = dP/dt · 1/P")
        println("d(logM)/dt = dM/dt · 1/M")
        println("d(logH)/dt = dH/dt · 1/H")
        
        # Test log-transformed ODE
        u = [log(1.0), log(2.0), log(3.0)]  # State vector: logP, logM, logH
        p = (0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7)  # Parameters
        du_actual = similar(u)  # Output buffer
        
        # Manually calculate expected derivatives
        logP, logM, logH = u
        P, M, H = exp(logP), exp(logM), exp(logH)
        p1, p2, p3, p4, p5, p6, p7 = p
        
        # Original equations
        dP_dt = -p1*P*H + p2*M - p3*P
        dM_dt = -p4*M + p5/(1 + P^2)
        dH_dt = -p1*P*H + p6/(1 + P^2) - p7*H
        
        # Log-transformed equations
        dlogP_dt = dP_dt / P
        dlogM_dt = dM_dt / M
        dlogH_dt = dH_dt / H
        
        du_expected = [dlogP_dt, dlogM_dt, dlogH_dt]
        
        # Calculate using the ODE function
        MagiJl.hes1log_ode!(du_actual, u, p, t)
        
        # Display results
        println("\nTest parameters:")
        println("  • State: logP = $(u[1]), logM = $(u[2]), logH = $(u[3])")
        println("  • Original state: P = $(P), M = $(M), H = $(H)")
        println("  • Parameters: [$(join(p, ", "))]")
        
        println("\nExpected derivatives (log-space):")
        println("  • d(logP)/dt = $(du_expected[1])")
        println("  • d(logM)/dt = $(du_expected[2])")
        println("  • d(logH)/dt = $(du_expected[3])")
        
        println("\nCalculated derivatives (log-space):")
        println("  • d(logP)/dt = $(du_actual[1])")
        println("  • d(logM)/dt = $(du_actual[2])")
        println("  • d(logH)/dt = $(du_actual[3])")
        
        # Test that the results match
        @test du_actual ≈ du_expected
        println("✓ Log-transformed function calculation matches expected values")
        
        # Compare with fixed parameter variants
        println("\n--- Testing Variants with Fixed Parameters ---")
        
        # Test fixg variant (fixes p7 = 0.3)
        u_fixg = u
        p_fixg = p[1:6]  # Exclude p7
        du_fixg_actual = similar(u)
        MagiJl.hes1log_ode_fixg!(du_fixg_actual, u_fixg, p_fixg, t)
        
        # Recalculate with fixed gamma
        gamma_fixed = 0.3
        dlogH_dt_fixg = -p1*P + p6/(1 + P^2)/H - gamma_fixed
        
        println("\nHes1 with fixed γ=0.3:")
        println("  • Expected d(logH)/dt = $(dlogH_dt_fixg)")
        println("  • Calculated d(logH)/dt = $(du_fixg_actual[3])")
        @test isapprox(du_fixg_actual[3], dlogH_dt_fixg, rtol=1e-5)
        println("✓ Fixed-γ variant calculation matches expected values")
        
        # Test fixf variant (fixes p6 = 20.0)
        u_fixf = u
        p_fixf = [p[1:5]..., p[7]]  # Exclude p6
        du_fixf_actual = similar(u)
        MagiJl.hes1log_ode_fixf!(du_fixf_actual, u_fixf, p_fixf, t)
        
        # Recalculate with fixed f
        f_fixed = 20.0
        dlogH_dt_fixf = -p1*P + f_fixed/(1 + P^2)/H - p[7]
        
        println("\nHes1 with fixed f=20.0:")
        println("  • Expected d(logH)/dt = $(dlogH_dt_fixf)")
        println("  • Calculated d(logH)/dt = $(du_fixf_actual[3])")
        @test isapprox(du_fixf_actual[3], dlogH_dt_fixf, rtol=1e-5)
        println("✓ Fixed-f variant calculation matches expected values")
    end

    @testset "HIV ODE Model" begin
        println("\n=== HIV MODEL ===")
        println("This model describes T-cell dynamics in HIV infection.")
        println("It uses a log transformation of the state variables.")
        
        # Test the HIV ODE function
        u = log.([1000.0, 100.0, 50.0, 20.0])  # Log-transformed state
        p = (10.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0)  # Parameters
        du_actual = similar(u)
        
        # Calculate using the ODE function
        MagiJl.hiv_ode!(du_actual, u, p, t)
        
        # Display some info
        println("\nTest parameters:")
        println("  • Log-transformed state: [$(join(round.(u, digits=2), ", "))]")
        println("  • Original state: [$(join(round.(exp.(u), digits=1), ", "))]")
        println("  • Parameters: [$(join(p, ", "))]")
        
        println("\nCalculated derivatives (log-space):")
        println("  • d(logT)/dt = $(du_actual[1])")
        println("  • d(logTm)/dt = $(du_actual[2])")
        println("  • d(logTw)/dt = $(du_actual[3])")
        println("  • d(logTmw)/dt = $(du_actual[4])")
        
        # Expected values based on simplified calculation
        du_expected = [9.99983, 1.001, 1.001, 1.001]
        @test du_actual ≈ du_expected rtol=1e-4
        println("✓ HIV model calculation matches expected values")
    end

    @testset "Protein Transduction ODE" begin
        println("\n=== PROTEIN TRANSDUCTION MODEL ===")
        println("This model describes signaling pathway dynamics with")
        println("protein phosphorylation/dephosphorylation processes.")
        
        # Test the Protein Transduction ODE function
        u = [10.0, 1.0, 5.0, 1.0, 2.0]  # State
        p = (0.1, 0.2, 0.3, 0.4, 0.5, 1.0)  # Parameters
        du_actual = similar(u)
        
        # Calculate using the ODE function
        MagiJl.ptrans_ode!(du_actual, u, p, t)
        
        # Extract states for clarity
        S, dS, R, RS, RPP = u
        p1, p2, p3, p4, p5, p6 = p
        
        # Display some info
        println("\nTest parameters:")
        println("  • State: S=$(u[1]), dS=$(u[2]), R=$(u[3]), RS=$(u[4]), RPP=$(u[5])")
        println("  • Parameters: [$(join(p, ", "))]")
        
        println("\nCalculated derivatives:")
        println("  • dS/dt = $(du_actual[1])")
        println("  • d(dS)/dt = $(du_actual[2])")
        println("  • dR/dt = $(du_actual[3])")
        println("  • dRS/dt = $(du_actual[4])")
        println("  • dRPP/dt = $(du_actual[5])")
        
        # Expected values
        du_expected = [-10.7, 1.0, -28.1/3.0, 9.3, 0.2/3.0]
        @test du_actual ≈ du_expected rtol=1e-4
        println("✓ Protein transduction model calculation matches expected values")
    end

    @testset "ODE Model Integration" begin
        println("\n=== ODE NUMERICAL INTEGRATION TESTS ===")
        println("Testing that the ODE functions can be integrated correctly")
        println("using standard differential equation solvers.")
        
        @testset "FitzHugh-Nagumo Integration" begin
            println("\n--- FitzHugh-Nagumo Integration Test ---")
            
            # Initial condition and parameters
            u0 = [1.0, 0.0]  # Initial state: V=1.0, R=0.0
            p_fn = [0.5, 0.6, 0.7]  # a, b, c
            tspan = (0.0, 10.0)  # Time span
            
            println("Initial condition: V=$(u0[1]), R=$(u0[2])")
            println("Parameters: a=$(p_fn[1]), b=$(p_fn[2]), c=$(p_fn[3])")
            println("Time span: $(tspan)")
            
            # Setup ODE problem
            prob_fn = ODEProblem(MagiJl.fn_ode!, u0, tspan, p_fn)
            println("Created ODE problem")
            
            # Solve the ODE
            println("Solving ODE...")
            sol_fn = solve(prob_fn, Tsit5(), reltol=1e-6, abstol=1e-6)
            println("Solution has $(length(sol_fn.t)) time points")
            
            # Basic verification
            @test length(sol_fn.t) > 2
            @test sol_fn(0.0) ≈ u0 rtol=1e-6
            println("✓ Solution at t=0 matches initial condition")
            
            # Check a midpoint solution for consistency
            t_mid = 5.0
            u_mid = sol_fn(t_mid)
            
            # Verify by calculating derivative at midpoint
            du_mid = zeros(2)
            MagiJl.fn_ode!(du_mid, u_mid, p_fn, t_mid)
            
            # Get numerical derivative from solution
            t_delta = 0.01
            u_forward = sol_fn(t_mid + t_delta)
            u_backward = sol_fn(t_mid - t_delta)
            du_numerical = (u_forward - u_backward) / (2 * t_delta)
            
            # Compare
            println("\nAt t=$(t_mid):")
            println("  Solution: V=$(u_mid[1]), R=$(u_mid[2])")
            println("  Analytical derivatives: dV/dt=$(du_mid[1]), dR/dt=$(du_mid[2])")
            println("  Numerical derivatives: dV/dt=$(du_numerical[1]), dR/dt=$(du_numerical[2])")
            
            # Test with generous tolerance due to numerical differentiation
            @test isapprox(du_mid, du_numerical, rtol=0.1)
            println("✓ Derivatives at midpoint match numerical approximation")
            
            # Plot the solution profile (pseudocode for documentation)
            println("\nSolution profile (sample points):")
            println(" | Time | V | R |")
            println(" |------|-----|-----|")
            sample_times = [0.0, 2.5, 5.0, 7.5, 10.0]
            for t in sample_times
                sol_pt = sol_fn(t)
                println(" | $(t) | $(round(sol_pt[1], digits=4)) | $(round(sol_pt[2], digits=4)) |")
            end
            
            # Check for expected FN dynamics (oscillations or approach to fixed point)
            # Depends on parameter regime, just a basic check
            println("\nDynamics analysis:")
            end_state = sol_fn(tspan[2])
            middle_state = sol_fn((tspan[1] + tspan[2])/2)
            if norm(end_state - middle_state) < 1e-3
                println("  System appears to approach a steady state")
            else
                println("  System exhibits dynamic behavior (oscillations or transient)")
            end
            println("✓ FitzHugh-Nagumo ODE integration successful")
        end
    end

    println("\n==================================================================")
    println("ODE MODEL FUNCTION TESTS COMPLETE")
    println("==================================================================")
end