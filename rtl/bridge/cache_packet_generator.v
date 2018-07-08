`include "parameters.h"

module cache_packet_generator
#
(
    NUM_WAY                                 = 2,
    TIMING_OUT_CYCLE                        = 100000,

    UNIFIED_CACHE_PACKET_WIDTH_IN_BITS      = `UNIFIED_CACHE_PACKET_WIDTH_IN_BITS,
    UNIFIED_CACHE_PACKET_PORT_ID_WIDTH      = `UNIFIED_CACHE_PACKET_PORT_ID_WIDTH,
    UNIFIED_CACHE_PACKET_BYTE_MASK_LENGTH   = `UNIFIED_CACHE_PACKET_BYTE_MASK_LENGTH,
    UNIFIED_CACHE_PACKET_TYPE_WIDTH         = `UNIFIED_CACHE_PACKET_TYPE_WIDTH,
    UNIFIED_CACHE_BLOCK_SIZE_IN_BITS        = `UNIFIED_CACHE_BLOCK_SIZE_IN_BITS,
    CPU_ADDR_LEN_IN_BITS                    = `CPU_ADDR_LEN_IN_BITS
)
(
    input                                                           reset_in,
    input                                                           clk_in,

    output  [UNIFIED_CACHE_PACKET_WIDTH_IN_BITS * NUM_WAY  - 1 : 0] test_packet_flatted_out,
    input   [NUM_WAY                                       - 1 : 0] test_packet_ack_flatted_in,

    input   [UNIFIED_CACHE_PACKET_WIDTH_IN_BITS * NUM_WAY  - 1 : 0] return_packet_flatted_in,
    output  [NUM_WAY                                       - 1 : 0] return_packet_ack_flatted_out,

    output                                                          done,
    output                                                          error
);

reg [NUM_WAY - 1 : 0] return_packet_ack;
reg [NUM_WAY - 1 : 0] done_way;
reg [NUM_WAY - 1 : 0] error_way;

assign done                             = &done_way;
assign error                            = |error_way;
assign return_packet_ack_flatted_out    = return_packet_ack;

generate
genvar WAY_INDEX;

for(WAY_INDEX = 0; WAY_INDEX < NUM_WAY; WAY_INDEX = WAY_INDEX + 1)
begin:way_logic
    
    if(WAY_INDEX == 0)
    begin
        reg [UNIFIED_CACHE_PACKET_WIDTH_IN_BITS - 1 : 0]    test_packet;
        assign test_packet_flatted_out[WAY_INDEX * UNIFIED_CACHE_PACKET_WIDTH_IN_BITS +: UNIFIED_CACHE_PACKET_WIDTH_IN_BITS] = test_packet;
        
        reg [31                                     : 0]    request_counter;
        reg [63                                     : 0]    timeout_counter;
        
        always@(posedge clk_in or posedge reset_in)
        begin
            if(reset_in)
            begin
                test_packet                     <= 0;
                request_counter                 <= 0;
                timeout_counter                 <= 0;
                return_packet_ack[WAY_INDEX]    <= 0;
                done_way[WAY_INDEX]             <= 0;
                error_way[WAY_INDEX]            <= 0;
            end

            else if(~error_way[WAY_INDEX])
            begin
                if(~test_packet[`UNIFIED_CACHE_PACKET_VALID_POS] & ~done_way[WAY_INDEX])
                begin
                    test_packet <=
                    {
                        /*cacheable*/   {1'b1},
                        /*write*/       {1'b1},
                        /*valid*/       {1'b1},
                        /*port*/        {(UNIFIED_CACHE_PACKET_PORT_ID_WIDTH){1'b0}},
                        /*byte mask*/   {{(UNIFIED_CACHE_PACKET_BYTE_MASK_LENGTH/2){1'b1}}, {(UNIFIED_CACHE_PACKET_BYTE_MASK_LENGTH/2){1'b1}}},
                        /*type*/        {(UNIFIED_CACHE_PACKET_TYPE_WIDTH){1'b0}},
                        /*data*/        {(UNIFIED_CACHE_BLOCK_SIZE_IN_BITS/2){2'b10}},
                        /*addr*/        {(CPU_ADDR_LEN_IN_BITS/32){32'h0000_1000}}
                    };
                    request_counter                 <= request_counter;
                    timeout_counter                 <= 0;
                    return_packet_ack[WAY_INDEX]    <= 0;
                    done_way[WAY_INDEX]             <= 0;
                    error_way[WAY_INDEX]            <= 0;
                end

                else if(test_packet[`UNIFIED_CACHE_PACKET_VALID_POS] & test_packet_ack_flatted_in[WAY_INDEX])
                begin
                    test_packet                     <= 0;
                    request_counter                 <= request_counter + 1'b1;
                    timeout_counter                 <= 0;
                    return_packet_ack[WAY_INDEX]    <= 0;
                    done_way[WAY_INDEX]             <= 1'b1;
                    error_way[WAY_INDEX]            <= timeout_counter >= TIMING_OUT_CYCLE ? 1'b1 : 1'b0;
                end

                else
                begin
                    test_packet                     <= test_packet;
                    request_counter                 <= request_counter;
                    timeout_counter                 <= timeout_counter + 1'b1;
                    return_packet_ack[WAY_INDEX]    <= 0;
                    done_way[WAY_INDEX]             <= done_way[WAY_INDEX];
                    error_way[WAY_INDEX]            <= timeout_counter >= TIMING_OUT_CYCLE & ~done_way[WAY_INDEX]? 1'b1 : 1'b0;
                end
            end
        end
    end

    if(WAY_INDEX == 1)
    begin
        reg [UNIFIED_CACHE_PACKET_WIDTH_IN_BITS - 1 : 0]    test_packet;
        assign test_packet_flatted_out[WAY_INDEX * UNIFIED_CACHE_PACKET_WIDTH_IN_BITS +: UNIFIED_CACHE_PACKET_WIDTH_IN_BITS] = test_packet;
        
        reg [31                                     : 0]    request_counter;
        reg [63                                     : 0]    timeout_counter;
        reg                                                 read_returned;

        always@(posedge clk_in or posedge reset_in)
        begin
            if(reset_in)
            begin
                test_packet                     <= 0;
                request_counter                 <= 0;
                done_way[WAY_INDEX]             <= 0;
            end

            else if(~error_way[WAY_INDEX])
            begin
                if(~test_packet[`UNIFIED_CACHE_PACKET_VALID_POS] & ~done_way[WAY_INDEX] & done_way[WAY_INDEX-1])
                begin
                    test_packet <=
                    {
                        /*cacheable*/   {1'b1},
                        /*write*/       {1'b0},
                        /*valid*/       {1'b1},
                        /*port*/        {{(UNIFIED_CACHE_PACKET_PORT_ID_WIDTH-2){1'b0}},{2'b01}},
                        /*byte mask*/   {(UNIFIED_CACHE_PACKET_BYTE_MASK_LENGTH){1'b0}},
                        /*type*/        {(UNIFIED_CACHE_PACKET_TYPE_WIDTH){1'b0}},
                        /*data*/        {(UNIFIED_CACHE_BLOCK_SIZE_IN_BITS){1'b0}},
                        /*addr*/        {(CPU_ADDR_LEN_IN_BITS/32){32'h0000_1000}}
                    };
                    request_counter                 <= request_counter;
                    done_way[WAY_INDEX]             <= 0;
                end

                else if(test_packet[`UNIFIED_CACHE_PACKET_VALID_POS] & test_packet_ack_flatted_in[WAY_INDEX])
                begin
                    test_packet                     <= 0;
                    request_counter                 <= request_counter + 1'b1;
                    done_way[WAY_INDEX]             <= 1;
                end

                else
                begin
                    test_packet                     <= test_packet;
                    request_counter                 <= request_counter;
                    done_way[WAY_INDEX]             <= done_way[WAY_INDEX];
                end
            end
        end

        wire [`UNIFIED_CACHE_PACKET_DATA_POS_HI : `UNIFIED_CACHE_PACKET_DATA_POS_LO] return_data =
        return_packet_flatted_in[(WAY_INDEX) * UNIFIED_CACHE_PACKET_WIDTH_IN_BITS + `UNIFIED_CACHE_PACKET_DATA_POS_LO +:
                                                                                    UNIFIED_CACHE_BLOCK_SIZE_IN_BITS];

        always@(posedge clk_in or posedge reset_in)
        begin
            if(reset_in)
            begin
                return_packet_ack[WAY_INDEX]    <= 0;
                timeout_counter                 <= 0;
                error_way[WAY_INDEX]            <= 0;
                read_returned                   <= 0;
            end

            else if(~error_way[WAY_INDEX])
            begin
                if(return_packet_flatted_in[(WAY_INDEX) * UNIFIED_CACHE_PACKET_WIDTH_IN_BITS + `UNIFIED_CACHE_PACKET_VALID_POS])
                begin
                    return_packet_ack[WAY_INDEX]    <= 1;
                    timeout_counter                 <= timeout_counter + 1'b1;
                    error_way[WAY_INDEX]            <= return_data != {(UNIFIED_CACHE_BLOCK_SIZE_IN_BITS/2){2'b10}}
                                                    | timeout_counter >= TIMING_OUT_CYCLE;
                    read_returned                   <= 1;
                end

                else if(~read_returned & ~return_packet_flatted_in[(WAY_INDEX) * UNIFIED_CACHE_PACKET_WIDTH_IN_BITS + `UNIFIED_CACHE_PACKET_VALID_POS])
                begin
                    return_packet_ack[WAY_INDEX]    <= 0;
                    timeout_counter                 <= timeout_counter + 1'b1;
                    error_way[WAY_INDEX]            <= timeout_counter >= TIMING_OUT_CYCLE;
                end
            end
        end
    end
end
endgenerate

endmodule