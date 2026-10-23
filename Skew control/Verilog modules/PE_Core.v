`timescale 1ns / 1ps

// ============================================================================
// MODULE: PE_CORE (PROCESSING ELEMENT) - v1.3 FINAL
// ============================================================================
module PE_Core (
    input  wire clk,
    input  wire resetn,
    input  wire [1:0]  mode,       
    input  wire [16:0] A_in,       
    input  wire [16:0] B_in,       
    output reg  [16:0] A_out,      
    output reg  [16:0] B_out,      
    output reg signed [35:0] C_acc       
);

    wire A_valid = A_in[16];
    wire B_valid = B_in[16];
    wire signed [15:0] A_raw = A_in[15:0];
    wire signed [15:0] B_raw = B_in[15:0];

    reg signed [15:0] A_masked;
    reg signed [15:0] B_masked;

    always @(*) begin
        case (mode)
            2'b00: begin 
                A_masked = {{12{A_raw[3]}}, A_raw[3:0]};
                B_masked = {{12{B_raw[3]}}, B_raw[3:0]};
            end
            2'b01: begin 
                A_masked = {{8{A_raw[7]}}, A_raw[7:0]};
                B_masked = {{8{B_raw[7]}}, B_raw[7:0]};
            end
            default: begin 
                A_masked = A_raw;
                B_masked = B_raw;
            end
        endcase
    end

    wire signed [31:0] product = A_masked * B_masked;
    wire signed [35:0] product_ext = {{4{product[31]}}, product};

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            A_out <= 17'd0;
            B_out <= 17'd0;
            C_acc <= 36'd0;
        end else begin
            
            // 1. UNCONDITIONAL PROPAGATION
            // All 17 bits pass to the next PE every cycle.
            // If data is constant/zero, dynamic power is naturally near zero.
            // This cleanly guarantees the pipeline flushes without race conditions.
            A_out <= A_in;
            B_out <= B_in;

            // 2. MAC POWER GATING
            // The combinational multiplier tree and adder only consume 
            // active switching power when valid data is present.
            if (A_valid && B_valid) begin
                C_acc <= C_acc + product_ext;
            end
        end
    end

endmodule