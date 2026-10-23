`timescale 1ns / 1ps

// ============================================================================
// MODULE 1: LOCAL DELAY REGISTER (INPUT SKEWING)
// ============================================================================
// CONCEPT: This module implements the "P-Scheme" (Partitioning Scheme).
// Instead of a massive global triangle of delay flip-flops (DFFs) that wastes
// power, we only use small 0-to-3 cycle shift registers locally at the edges 
// of our 4x4 Pods. This removes ~80% of the skew DFFs in the design.
// ============================================================================
module Delay_Register #(
    parameter WIDTH = 17,  // 17 bits to hold the {Valid, Data[15:0]} packet
    parameter CYCLES = 1   // How many clock cycles to delay the data
)(
    input  wire clk,
    input  wire resetn,             // Standard active-low reset
    input  wire [WIDTH-1:0] d_in,   // Input data to be delayed
    output wire [WIDTH-1:0] d_out   // Delayed output data
);

    // We use a generate block to physically build the shift register.
    // If CYCLES is 0, it just creates a direct wire (no flip-flops).
    generate
        if (CYCLES == 0) begin : gen_no_delay
            
            // Zero delay means the input connects directly to the output.
            assign d_out = d_in;
            
        end else begin : gen_delay
            
            // Create an internal array of registers to act as a delay line.
            // For example, if CYCLES = 3, this makes three 17-bit registers.
            reg [WIDTH-1:0] shift_reg [0:CYCLES-1];
            integer i;
            
            always @(posedge clk or negedge resetn) begin
                if (!resetn) begin
                    // On reset, clear every flip-flop in the shift register to 0.
                    for (i = 0; i < CYCLES; i = i + 1) begin
                        shift_reg[i] <= {WIDTH{1'b0}};
                    end
                end else begin
                    // Stage 0 always grabs the fresh input data from the pin.
                    shift_reg[0] <= d_in;
                    
                    // The rest of the stages pass data to the right every clock cycle.
                    // This creates a physical pipeline delay.
                    for (i = 1; i < CYCLES; i = i + 1) begin
                        shift_reg[i] <= shift_reg[i-1];
                    end
                end
            end
            
            // The final output is always driven by the very last register stage.
            assign d_out = shift_reg[CYCLES-1];
            
        end
    endgenerate

endmodule