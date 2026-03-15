`default_nettype none
`timescale 1ns/1ns

module warp_scheduler #(
    parameter THREADS_PER_BLOCK = 8,
    parameter WARP_SIZE = 4
)(
    input  wire clk,
    input  wire reset,
    input  wire start,

    // decoded signals (for current instruction)
    input  wire decoded_ret,

    // fetcher/lsu state
    input  wire [2:0] fetcher_state,
    input  wire [1:0] lsu_state [THREADS_PER_BLOCK-1:0],

    // active threads in the block
    input  wire [$clog2(THREADS_PER_BLOCK):0] thread_count,

    // next pc per thread
    input  wire [7:0] next_pc [THREADS_PER_BLOCK-1:0],

    // outputs
    output reg  [7:0] current_pc,
    output reg  [2:0] core_state,
    output reg  done,
    output reg  [$clog2(THREADS_PER_BLOCK/WARP_SIZE)-1:0] active_warp
);

    localparam integer NUM_WARPS = THREADS_PER_BLOCK / WARP_SIZE;

    localparam IDLE    = 3'b000,
               FETCH   = 3'b001,
               DECODE  = 3'b010,
               REQUEST = 3'b011,
               WAIT    = 3'b100,
               EXECUTE = 3'b101,
               UPDATE  = 3'b110,
               DONE_S  = 3'b111;

    reg [7:0] warp_pc   [NUM_WARPS-1:0];
    reg       warp_done [NUM_WARPS-1:0];

    // pending memory in warp w?
    function automatic warp_mem_pending(input integer w);
        integer l, tid;
        begin
            warp_mem_pending = 1'b0;
            for (l = 0; l < WARP_SIZE; l = l + 1) begin
                tid = w*WARP_SIZE + l;
                if (tid < thread_count) begin
                    if (lsu_state[tid] == 2'b01 || lsu_state[tid] == 2'b10) begin
                        warp_mem_pending = 1'b1;
                    end
                end
            end
        end
    endfunction

    // does this warp have any lanes at all?
    function automatic warp_empty(input integer w);
        begin
            warp_empty = ((w*WARP_SIZE) >= thread_count);
        end
    endfunction

    integer w;

    always @(posedge clk) begin
        if (reset) begin
            core_state  <= IDLE;
            done        <= 1'b0;
            active_warp <= '0;
            current_pc  <= 8'd0;

            for (w = 0; w < NUM_WARPS; w = w + 1) begin
                warp_pc[w]   <= 8'd0;
                warp_done[w] <= 1'b0;
            end

        end else begin
            // drive current_pc from active warp
            current_pc <= warp_pc[active_warp];

            case (core_state)
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        // init per-warp pc and mark empty warps as already done
                        for (w = 0; w < NUM_WARPS; w = w + 1) begin
                            warp_pc[w]   <= 8'd0;
                            warp_done[w] <= warp_empty(w);
                        end

                        // pick first non-empty warp (for NUM_WARPS=2 this is easy)
                        if (!warp_empty(0)) begin
                            active_warp <= 0;
                            core_state  <= FETCH;
                        end else if (!warp_empty(1)) begin
                            active_warp <= 1;
                            core_state  <= FETCH;
                        end else begin
                            // thread_count == 0 case: immediately done
                            done <= 1'b1;
                            core_state <= DONE_S;
                        end
                    end
                end

                FETCH: begin
                    if (fetcher_state == 3'b010) begin // FETCHED
                        core_state <= DECODE;
                    end
                end

                DECODE: begin
                    core_state <= REQUEST;
                end

                REQUEST: begin
                    core_state <= WAIT;
                end

                WAIT: begin
                    // stall until active warp's mem ops finish
                    if (!warp_mem_pending(active_warp)) begin
                        core_state <= EXECUTE;
                    end
                end

                EXECUTE: begin
                    core_state <= UPDATE;
                end

                UPDATE: begin
                    if (decoded_ret) begin
                        warp_done[active_warp] <= 1'b1;

                        // advance to next non-done warp, else finish
                        if (active_warp == NUM_WARPS-1) begin
                            done <= 1'b1;
                            core_state <= DONE_S;
                        end else begin
                            // for NUM_WARPS=2: next is 1
                            if (!warp_done[active_warp + 1'b1]) begin
                                active_warp <= active_warp + 1'b1;
                                core_state  <= FETCH;
                            end else begin
                                // next warp is empty/already done => finish
                                done <= 1'b1;
                                core_state <= DONE_S;
                            end
                        end

                    end else begin
                        // No divergence assumption: lane0 next_pc used
                        warp_pc[active_warp] <= next_pc[active_warp*WARP_SIZE];
                        core_state <= FETCH;
                    end
                end

                DONE_S: begin
                    // hold
                end
            endcase
        end
    end

endmodule