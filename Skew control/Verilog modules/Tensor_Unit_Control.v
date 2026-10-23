`timescale 1ns / 1ps

module Tensor_Unit_Control (
    input  wire clk,
    input  wire resetn,      // Active-low synchronous or asynchronous reset
    input  wire start,       // 1-cycle pulse to begin matrix multiplication
    
    output reg  busy,        // High while the array is computing or draining
    output wire done,        // 1-cycle pulse when all 256 results are drained
    output wire input_valid, // Signals the router to pump data into the array
    output wire drain_en,    // Enables the 4:1 column MUXes
    output wire [1:0] row_sel// Selects the local row (0-3) for the 4:1 MUX drain
);

    // -------------------------------------------------------------------------
    // 23-Bit One-Hot Delay Line (Tracks t = 0 to t = 22)
    // -------------------------------------------------------------------------
    reg [22:0] delay_line;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            delay_line <= 23'd0;
            busy       <= 1'b0;
        end else begin
            // Shift the delay line left by 1 every clock cycle
            delay_line <= {delay_line[21:0], 1'b0};

            // Inject a '1' at t=0 when start is asserted
            if (start && !busy) begin
                delay_line[0] <= 1'b1;
                busy <= 1'b1;
            end
            
            // Clear the busy flag immediately after the final cycle (t=22) finishes
            if (delay_line[22]) begin
                busy <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Data-Driven Input Control
    // -------------------------------------------------------------------------
    // Keep input_valid high for the first 16 clock cycles (t=0 to t=15)
    // This tells the Systolic_Router to stream the 16x16 matrices into the pods.
    // A bitwise OR reduction over the first 16 bits of the delay line.
    assign input_valid = |delay_line[15:0];

    // -------------------------------------------------------------------------
    // Overlapped Output Drain Control (t=19 to t=22)
    // -------------------------------------------------------------------------
    // Enable the local 4:1 MUXes only during the final 4 clock cycles
    assign drain_en = delay_line[19] | delay_line[20] | delay_line[21] | delay_line[22];

    // MUX Row Selection matches your timing schedule:
    // t=19: row_sel = 2'b00 (Local Row 0)
    // t=20: row_sel = 2'b01 (Local Row 1)
    // t=21: row_sel = 2'b10 (Local Row 2)
    // t=22: row_sel = 2'b11 (Local Row 3)
    
    // bit 0 is high at t=20 and t=22
    assign row_sel[0] = delay_line[20] | delay_line[22];
    
    // bit 1 is high at t=21 and t=22
    assign row_sel[1] = delay_line[21] | delay_line[22];

    // -------------------------------------------------------------------------
    // Completion Flag
    // -------------------------------------------------------------------------
    // Assert 'done' exactly at t=22, signaling the wrapper that data is ready
    assign done = delay_line[22];

endmodule