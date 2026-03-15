`default_nettype none
`timescale 1ns/1ns

module warp_scheduler #(
    parameter THREADS_PER_BLOCK = 8,
    parameter WARP_SIZE = 4
)(
    input  wire clk,
    input  wire reset,
    input  wire start,

    // decoded signals
    input  wire decoded_ret,

    // fetcher/lsu state
    input  wire [2:0] fetcher_state,
    input  wire [1:0] lsu_state [THREADS_PER_BLOCK-1:0],

    // active threads in the block
    input  wire [$clog2(THREADS_PER_BLOCK):0] thread_count,

    // next pc per thread
    input  wire [7:0] next_pc [THREADS_PER_BLOCK-1:0],

    // outputs
    output wire [7:0] current_pc,
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
               DONE  = 3'b111;

    reg [7:0] warp_pc   [NUM_WARPS-1:0];
    reg       warp_done [NUM_WARPS-1:0];

    // check if any warp is waiting on memory request
    reg     mem_pending;
    integer l, tid_mp;
    always_comb begin
        mem_pending = 1'b0;
        for (l = 0; l < WARP_SIZE; l = l + 1) begin
            tid_mp = active_warp * WARP_SIZE + l;
            if (tid_mp < thread_count) begin
                if (lsu_state[tid_mp] == 2'b01 || lsu_state[tid_mp] == 2'b10)
                    mem_pending = 1'b1;
            end
        end
    end

    // current_pc: always reflects the active warp's PC immediately
    assign current_pc = warp_pc[active_warp];

    integer w;

    always @(posedge clk) begin
        if (reset) begin
            core_state  <= IDLE;
            done        <= 1'b0;
            active_warp <= '0;

            for (w = 0; w < NUM_WARPS; w = w + 1) begin
                warp_pc[w]   <= 8'd0;
                warp_done[w] <= 1'b0;
            end

        end else begin
            case (core_state)
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        // init per-warp pc and mark empty warps as already done
                        for (w = 0; w < NUM_WARPS; w = w + 1) begin
                            warp_pc[w]   <= 8'd0;
                            warp_done[w] <= (w * WARP_SIZE >= thread_count);
                        end

                        // pick first non-empty warp
                        if (!(0 * WARP_SIZE >= thread_count)) begin
                            active_warp <= 0;
                            core_state  <= FETCH;
                        end else if (!(1 * WARP_SIZE >= thread_count)) begin
                            active_warp <= 1;
                            core_state  <= FETCH;
                        end else begin
                            // thread_count == 0 case: immediately done
                            done <= 1'b1;
                            core_state <= DONE;
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
                    if (!mem_pending) begin
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
                            core_state <= DONE;
                        end else begin
                            // check if warps are done
                            if (!warp_done[active_warp + 1'b1]) begin
                                active_warp <= active_warp + 1'b1;
                                core_state  <= FETCH;
                            end else begin
                                // next warp is empty/already done => finish
                                done <= 1'b1;
                                core_state <= DONE;
                            end
                        end

                    end else begin
                        // No divergence assumption: lane0 next_pc used
                        warp_pc[active_warp] <= next_pc[active_warp*WARP_SIZE];
                        core_state <= FETCH;
                    end
                end

                DONE: begin
                    
                end
            endcase
        end
    end

endmodule