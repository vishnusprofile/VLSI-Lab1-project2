`timescale 1ns / 1ps

// ============================================================================
// MODULE 3: POD 4x4 (THE MACRO BUILDING BLOCK)
// ============================================================================
// CONCEPT: This builds one 4x4 sub-grid. It combines 16 PE_Cores.
// To keep the Verilog strictly standard and simple, we use a flattened 
// 68-bit vector for the input buses (4 inputs * 17 bits = 68 bits) instead 
// of complex SystemVerilog 2D ports.
// This module also contains the 4:1 multiplexers to drain the stationary
// accumulators straight out, saving 4 clock cycles (The PA-Scheme).
// ============================================================================
module Pod_4x4 (
    input  wire clk,
    input  wire resetn,
    input  wire [1:0]  mode,
    
    // Control signals for the staggered 4:1 drain multiplexers
    input  wire [1:0]  row_sel,   
    input  wire        drain_en,
    
    // FLATTENED INPUT BUSES: 
    // Instead of complex ports, A_in_bus holds four 17-bit packets from the West.
    // B_in_bus holds four 17-bit packets from the North.
    input  wire [67:0] A_in_bus,  
    input  wire [67:0] B_in_bus,  
    
    // FLATTENED OUTPUT BUS:
    // Holds four 36-bit drained outputs (4 * 36 = 144 bits).
    output wire [143:0] C_drain_out 
);

    // ------------------------------------------------------------------------
    // INTERNAL 2D ARRAYS FOR CLEAN WIRING
    // ------------------------------------------------------------------------
    // Standard Verilog allows 2D arrays internally (just not on ports).
    // This makes wiring the 4x4 grid much easier to read.
    wire [16:0] A_skewed [0:3];
    wire [16:0] B_skewed [0:3];

    // Interconnect meshes to link the PEs together.
    // A_net goes horizontally (4 rows, 5 boundaries)
    // B_net goes vertically (5 boundaries, 4 columns)
    wire [16:0] A_net [0:3][0:4]; 
    wire [16:0] B_net [0:4][0:3]; 
    
    // Holds the raw 36-bit accumulator outputs from all 16 PEs.
    wire [35:0] C_net [0:3][0:3]; 

    genvar r, c;
    generate
        // --------------------------------------------------------------------
        // 1. LOCALIZED 0-3 CYCLE SKEW REGISTERS
        // --------------------------------------------------------------------
        // We unpack the flattened 68-bit bus into four 17-bit signals and 
        // feed them through the Delay_Registers. Row 0 has 0 delay, Row 3 
        // has 3 cycles of delay.
        for (r = 0; r < 4; r = r + 1) begin : A_skew
            Delay_Register #(
                .WIDTH(17), 
                .CYCLES(r) // r determines the skew (0, 1, 2, or 3)
            ) a_dly (
                .clk(clk), 
                .resetn(resetn), 
                .d_in( A_in_bus[r*17 +: 17] ), // Slice 17 bits from the flat bus
                .d_out(A_skewed[r])
            );
            // Drive the left-most boundary of the PE grid with the skewed data
            assign A_net[r][0] = A_skewed[r]; 
        end
        
        // Do the exact same thing for the B inputs coming from the Top.
        for (c = 0; c < 4; c = c + 1) begin : B_skew
            Delay_Register #(
                .WIDTH(17), 
                .CYCLES(c)
            ) b_dly (
                .clk(clk), 
                .resetn(resetn), 
                .d_in( B_in_bus[c*17 +: 17] ), 
                .d_out(B_skewed[c])
            );
            // Drive the top-most boundary of the PE grid
            assign B_net[0][c] = B_skewed[c]; 
        end

        // --------------------------------------------------------------------
        // 2. INSTANTIATE THE 4x4 PE GRID
        // --------------------------------------------------------------------
        // This physically places 16 PE cores and stitches their A and B 
        // passing wires together using the 2D nets we defined above.
        for (r = 0; r < 4; r = r + 1) begin : pe_row
            for (c = 0; c < 4; c = c + 1) begin : pe_col
                PE_Core pe_inst (
                    .clk(clk),
                    .resetn(resetn),
                    .mode(mode),
                    .A_in( A_net[r][c] ),     // Data arriving from the West
                    .B_in( B_net[r][c] ),     // Data arriving from the North
                    .A_out( A_net[r][c+1] ),  // Data leaving to the East
                    .B_out( B_net[r+1][c] ),  // Data leaving to the South
                    .C_acc( C_net[r][c] )     // Tapping the stationary accumulator
                );
            end
        end

        // --------------------------------------------------------------------
        // 3. OUTPUT-STATIONARY DRAIN MULTIPLEXERS
        // --------------------------------------------------------------------
        // In older designs, data shifted down row-by-row to exit, wasting power.
        // We use 4:1 multiplexers to read the accumulators directly.
        for (c = 0; c < 4; c = c + 1) begin : drain_mux
            
            // Standard behavioral multiplexer. Synthesizes to fast MUX gates.
            wire [35:0] mux_out = (row_sel == 2'b00) ? C_net[0][c] :
                                  (row_sel == 2'b01) ? C_net[1][c] :
                                  (row_sel == 2'b10) ? C_net[2][c] :
                                                       C_net[3][c];
                                                       
            // Only output the data if drain_en is 1. Otherwise, drive 0.
            // We pack the 36-bit output back into the 144-bit flat output bus.
            assign C_drain_out[c*36 +: 36] = drain_en ? mux_out : 36'd0;
        end
    endgenerate

endmodule