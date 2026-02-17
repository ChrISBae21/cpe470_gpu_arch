`default_nettype none
`timescale 1ns/1ns

// BLOCK DISPATCH
// > The GPU has one dispatch unit at the top level
// > Manages processing of threads and marks kernel execution as done
// > Sends off batches of threads in blocks to be executed by available compute cores

module dispatch #(
    parameter NUM_CORES = 2,
    parameter THREADS_PER_BLOCK = 4,
    parameter MAX_BLOCKS = 256,
    parameter PRIO_BITS = 4   // kept for compatibility; unused in this FIFO version
) (
    input wire clk,
    input wire reset,
    input wire start,

    // Kernel Metadata
    input wire [7:0] thread_count,

    input  reg [NUM_CORES-1:0] core_done,
    output reg [NUM_CORES-1:0] core_start,
    output reg [NUM_CORES-1:0] core_reset,
    output reg [7:0] core_block_id [NUM_CORES-1:0],
    output reg [$clog2(THREADS_PER_BLOCK):0] core_thread_count [NUM_CORES-1:0],

    // Kernel Execution
    output reg done
);

    // Calculate the total number of blocks based on total threads & threads per block
    wire [7:0] total_blocks;
    assign total_blocks = (thread_count + THREADS_PER_BLOCK - 1) / THREADS_PER_BLOCK;

    // Keep track of how many blocks have been processed
    reg [MAX_BLOCKS-1:0] dispatched_mask; // How many blocks have been sent to cores?
    reg [7:0] blocks_done; // How many blocks have finished processing?
    reg start_execution; // EDA: Unimportant hack used because of EDA tooling

    reg [MAX_BLOCKS-1:0] temp_mask;

    // local picker vars (inlined pick)
    reg found_local;
    reg [7:0] chosen_id;

    always @(posedge clk) begin
        if (reset) begin
            done <= 1'b0;
            dispatched_mask <= {MAX_BLOCKS{1'b0}};
            blocks_done <= 8'd0;
            start_execution <= 1'b0;

            for (int i = 0; i < NUM_CORES; i++) begin
                core_start[i] <= 1'b0;
                core_reset[i] <= 1'b1;
                core_block_id[i] <= 8'd0;
                core_thread_count[i] <= THREADS_PER_BLOCK;
            end

        end else if (start) begin
            // EDA: Indirect way to get @(posedge start) without driving from 2 different clocks
            if (!start_execution) begin
                start_execution <= 1'b1;
                for (int i = 0; i < NUM_CORES; i++) begin
                    core_reset[i] <= 1'b1;
                    core_start[i] <= 1'b0;
                end
            end

            // If the last block has finished processing, mark this kernel as done executing
            if (blocks_done == total_blocks) begin
                done <= 1'b1;
            end

            // DISPATCH: allocate distinct blocks to all available cores
            temp_mask = dispatched_mask; // local temp

            for (int i = 0; i < NUM_CORES; i++) begin
                if (core_reset[i]) begin
                    core_reset[i] <= 1'b0;

                    // choose lowest block id not yet dispatched (< total_blocks)
                    found_local = 1'b0;
                    chosen_id   = 8'd0;

                    for (int b = 0; b < MAX_BLOCKS; b++) begin
                        if ((b < total_blocks) && (!temp_mask[b]) && (!found_local)) begin
                            found_local = 1'b1;
                            chosen_id   = b[7:0];
                        end
                    end

                    if (found_local) begin
                        // activate the core
                        core_start[i]    <= 1'b1;
                        // set the block id for the core executing
                        core_block_id[i] <= chosen_id;
                        // edge case, last block should only execute remaining threads
                        core_thread_count[i] <= (chosen_id == (total_blocks - 1))
                            ? (thread_count - (chosen_id * THREADS_PER_BLOCK))
                            : THREADS_PER_BLOCK;
                        // ensure next core gets a different block
                        temp_mask[chosen_id] = 1'b1;
                    end
                end
            end
            // commit after assigning all cores
            dispatched_mask <= temp_mask;

            // COMPLETION PHASE
            for (int i = 0; i < NUM_CORES; i = i + 1) begin
                if (core_start[i] && core_done[i]) begin
                    // If a core just finished executing it's current block, reset it
                    core_reset[i] <= 1'b1;
                    core_start[i] <= 1'b0;
                    blocks_done   <= blocks_done + 8'd1;
                end
            end
        end
    end

endmodule