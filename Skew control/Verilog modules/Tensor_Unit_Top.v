`timescale 1ns / 1ps

// ============================================================================
// MODULE 5: TENSOR UNIT TOP (THE GLOBAL WRAPPER)
// ============================================================================
// CONCEPT: This connects everything together. It instantiates the FSM, 
// the Systolic Router, and a 4x4 grid of Pods (meaning 16 Pods total, 
// which equals 256 PEs). 
// By structuring it this way, we eliminate long global wires and ensure
// clean routing and easy 300 MHz timing closure for ASIC synthesis.
// ============================================================================
module Tensor_Unit_Top (
    input  wire clk,
    input  wire resetn,
    input  wire start,
    input  wire [1:0] mode,
    
    // Flattened 256-bit buses from main memory
    input  wire [255:0] A_matrix_in,
    input  wire [255:0] B_matrix_in,
    
    // Outputs to main memory
    output wire busy,
    output wire done,
    
    // Flattened 2304-bit bus (64 columns * 36 bits). 
    // This allows the array to drain 64 MAC results simultaneously per cycle.
    output wire [2303:0] C_matrix_out 
);

    // ------------------------------------------------------------------------
    // INTERNAL CONTROL AND ROUTING WIRES
    // ------------------------------------------------------------------------
    wire input_valid;
    wire drain_en;
    wire [1:0] row_sel;
    
    // The formatted 17-bit packets from the router
    wire [271:0] A_packet_flat;
    wire [271:0] B_packet_flat;

    // ------------------------------------------------------------------------
    // 1. INSTANTIATE THE GLOBAL CONTROL FSM
    // ------------------------------------------------------------------------
    // This is the 23-bit One-Hot Delay Line FSM we built earlier.
    Tensor_Unit_Control control_fsm (
        .clk(clk), 
        .resetn(resetn), 
        .start(start),
        .busy(busy), 
        .done(done),
        .input_valid(input_valid), 
        .drain_en(drain_en), 
        .row_sel(row_sel)
    );

    // ------------------------------------------------------------------------
    // 2. INSTANTIATE THE SYSTOLIC ROUTER
    // ------------------------------------------------------------------------
    // This converts the raw memory data into power-gated 17-bit packets.
    Systolic_Router router (
        .pe_enable(input_valid),
        .A_raw(A_matrix_in), 
        .B_raw(B_matrix_in),
        .A_packet(A_packet_flat), 
        .B_packet(B_packet_flat)
    );

    // ------------------------------------------------------------------------
    // 3. INSTANTIATE THE 16 PODS (4x4 MACRO-GRID)
    // ------------------------------------------------------------------------
    genvar pod_r, pod_c, i;
    generate
        for (pod_r = 0; pod_r < 4; pod_r = pod_r + 1) begin : macro_row
            for (pod_c = 0; pod_c < 4; pod_c = pod_c + 1) begin : macro_col
                
                // These wires will hold the specific data for this specific Pod
                wire [67:0] pod_A_in;
                wire [67:0] pod_B_in;
                wire [143:0] pod_C_out;
                
                for (i = 0; i < 4; i = i + 1) begin : input_map
                    
                    // FORKING THE DATA BUS:
                    // Instead of shifting data through all 16 pods, we broadcast
                    // the inputs directly to the specific pods that need them.
                    // This is how all 16 pods can start computing at t=0.
                    
                    // Route A inputs to all pods in the same macro-row
                    assign pod_A_in[i*17 +: 17] = A_packet_flat[((pod_r * 4) + i) * 17 +: 17];
                    
                    // Route B inputs to all pods in the same macro-column
                    assign pod_B_in[i*17 +: 17] = B_packet_flat[((pod_c * 4) + i) * 17 +: 17];
                end

                // Physically instantiate the 4x4 Pod
                Pod_4x4 pod_inst (
                    .clk(clk), 
                    .resetn(resetn), 
                    .mode(mode),
                    .row_sel(row_sel), 
                    .drain_en(drain_en),
                    .A_in_bus(pod_A_in), 
                    .B_in_bus(pod_B_in),
                    .C_drain_out(pod_C_out)
                );
                
                // MAP THE OUTPUT DRAIN:
                // Take the 4 drained 36-bit outputs from this pod and place 
                // them in their correct spot on the global 64-wide output bus.
                for (i = 0; i < 4; i = i + 1) begin : output_map
                    assign C_matrix_out[((pod_r * 16) + (pod_c * 4) + i) * 36 +: 36] = pod_C_out[i*36 +: 36];
                end

            end
        end
    endgenerate

endmodule