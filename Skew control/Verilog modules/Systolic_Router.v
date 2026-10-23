`timescale 1ns / 1ps

// ============================================================================
// MODULE 4: SYSTOLIC ROUTER (ZERO DETECTION)
// ============================================================================
// CONCEPT: We want to catch 'zeros' before they even enter the array.
// This module sits at the boundary. It looks at the 16-bit raw memory data,
// checks if it is non-zero, and appends a '1' or '0' as the 17th Valid bit.
// Again, flattened ports are used for strict standard Verilog compliance.
// ============================================================================
module Systolic_Router (
    input  wire pe_enable,      // Master enable from the FSM (input_valid)
    
    // Flat 256-bit buses representing sixteen 16-bit words
    input  wire [255:0] A_raw,  
    input  wire [255:0] B_raw,  
    
    // Flat 272-bit buses representing sixteen 17-bit formatted packets
    output wire [271:0] A_packet, 
    output wire [271:0] B_packet  
);

    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : packetizer
            
            // Extract the specific 16-bit word from the flat bus
            wire [15:0] a_data_word = A_raw[i*16 +: 16];
            wire [15:0] b_data_word = B_raw[i*16 +: 16];
            
            // ZERO DETECTION LOGIC:
            // |a_data_word performs a bitwise OR across all 16 bits. 
            // If the data is perfectly 0, this evaluates to 0. 
            // If even one bit is high, it evaluates to 1.
            wire a_is_valid = pe_enable & (|a_data_word);
            wire b_is_valid = pe_enable & (|b_data_word);
            
            // Construct the 17-bit packet: {Valid, Data[15:0]}
            // and pack it back into the flat 272-bit output bus.
            assign A_packet[i*17 +: 17] = {a_is_valid, a_data_word};
            assign B_packet[i*17 +: 17] = {b_is_valid, b_data_word};
            
        end
    endgenerate

endmodule




////////////////////////////////////////updated with zero detect  a_update_en = pe_enable & a_is_not_zero;////////////////////////////////////////////////////////////////////////////////
            



`timescale 1ns / 1ps

// ============================================================================
// MODULE: Systolic_Router
// ============================================================================
module Systolic_Router (
    input  wire clk,             // Required to hold previous values
    input  wire resetn,          // Required to clear holding registers
    input  wire pe_enable,       // Comes from input_valid in Top
    
    input  wire [255:0] A_raw,
    input  wire [255:0] B_raw,
    
    output wire [271:0] A_packet,
    output wire [271:0] B_packet
);

    genvar i;
    generate
        // Loop through all 16 elements in the 256-bit flat bus
        for (i = 0; i < 16; i = i + 1) begin : packet_gen
            
            // 1. Slice out the 16-bit data chunks
            wire [15:0] a_data_in = A_raw[i*16 +: 16];
            wire [15:0] b_data_in = B_raw[i*16 +: 16];

            // 2. ZERO-DETECTION
            // Checks if the data has any 1s in it. 0 if completely zero.
            wire a_is_not_zero = |a_data_in;
            wire b_is_not_zero = |b_data_in;

            // 3. THE GATEKEEPER
            // Update only if FSM says valid AND data is not zero
            wire a_update_en = pe_enable & a_is_not_zero;
            wire b_update_en = pe_enable & b_is_not_zero;

            // 4. THE HOLDING REGISTERS (This keeps the previous value!)
            reg [15:0] a_held_data;
            reg [15:0] b_held_data;

            always @(posedge clk or negedge resetn) begin
                if (!resetn) begin
                    a_held_data <= 16'd0;
                    b_held_data <= 16'd0;
                end else begin
                    // If update_en is 0, it skips this and holds previous value
                    if (a_update_en) a_held_data <= a_data_in;
                    if (b_update_en) b_held_data <= b_data_in;
                end
            end

            // 5. PACKET CONSTRUCTION
            // Appends the dynamically checked valid bit to the frozen data
            assign A_packet[i*17 +: 17] = {a_update_en, a_held_data};
            assign B_packet[i*17 +: 17] = {b_update_en, b_held_data};
            
        end
    endgenerate

endmodule


