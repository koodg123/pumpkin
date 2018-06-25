`include "parameters.h"

`define IDLE        4'b0000
`define FIRST       4'b0001
`define READ_HIT    4'b0010
`define READ_MISS   4'b0011
`define WRITE_HIT   4'b0100
`define WRITE_MISS  4'b0101

module cache_bank_simple_ctrl
#(
    parameter BANK_NUM                           = 0,
    parameter NUM_INPUT_PORT                     = 2,
    parameter UNIFIED_CACHE_PACKET_WIDTH_IN_BITS = `UNIFIED_CACHE_PACKET_WIDTH_IN_BITS,

    parameter NUM_SET                            = `UNIFIED_CACHE_NUM_SETS,
    parameter NUM_WAY                            = `UNIFIED_CACHE_SET_ASSOCIATIVITY,
    parameter BLOCK_SIZE_IN_BYTES                = `UNIFIED_CACHE_BLOCK_SIZE_IN_BYTES,
    parameter SET_PTR_WIDTH_IN_BITS              = $clog2(NUM_SET)
)
(
    input                                                                   reset_in,
    input                                                                   clk_in,
    
    input       [UNIFIED_CACHE_PACKET_WIDTH_IN_BITS         - 1 : 0]        access_packet,
    output  reg                                                             access_packet_ack,
    input                                                                   bank_lock_release,

    input       [UNIFIED_CACHE_PACKET_WIDTH_IN_BITS          - 1 : 0]       fetched_request_in,
    input                                                                   fetched_request_valid_in,
    output  reg                                                             fetch_ack_out,

    output  reg [UNIFIED_CACHE_PACKET_WIDTH_IN_BITS          - 1 : 0]       miss_request_out,
    output  reg                                                             miss_request_valid_out,
    output  reg                                                             miss_request_critical_out,
    input                                                                   miss_request_ack_in,

    output  reg [UNIFIED_CACHE_PACKET_WIDTH_IN_BITS          - 1 : 0]       writeback_request_out,
    output  reg                                                             writeback_request_valid_out,
    output  reg                                                             writeback_request_critical_out,
    input                                                                   writeback_request_ack_in,

    output      [UNIFIED_CACHE_PACKET_WIDTH_IN_BITS          - 1 : 0]       return_request_out,
    output                                                                  return_request_valid_out,
    output                                                                  return_request_critical_out,
    input                                                                   return_request_ack_in,

    // to valid, history, tag array
    output  reg                                                             access_en_to_main_array_out,
    output  reg                                                             write_en_to_main_array_out,
    output  reg [NUM_WAY                                     - 1 : 0]       way_select_to_main_array_out,
    output  reg [SET_PTR_WIDTH_IN_BITS                       - 1 : 0]       access_set_addr_to_main_array_out,
    output                                                                  write_single_entry_to_main_array_out,

    input   [NUM_WAY                                         - 1 : 0]       valid_flatted_in,
    input   [NUM_WAY                                         - 1 : 0]       history_flatted_in,
    input   [NUM_WAY * `UNIFIED_CACHE_TAG_LEN_IN_BITS        - 1 : 0]       tag_flatted_in,
    input   [`UNIFIED_CACHE_BLOCK_SIZE_IN_BITS               - 1 : 0]       data_in
);

reg  bank_lock;
wire issue_grant = access_packet[`UNIFIED_CACHE_PACKET_VALID_POS] & (~bank_lock | (bank_lock & bank_lock_release));

always@(posedge clk_in or posedge reset_in)
begin
    if(reset_in)
    begin
        bank_lock           <= 1'b0;
        access_packet_ack   <= 1'b0;
    end
    
    else if(issue_grant)
    begin
        bank_lock           <= 1'b1;
        access_packet_ack   <= 1'b0;
    end

    else if(bank_lock & bank_lock_release)
    begin
        bank_lock           <= 1'b0;
        access_packet_ack   <= 1'b1;
    end

    else
    begin
        bank_lock           <= bank_lock;
        access_packet_ack   <= 1'b0;
    end
end

wire                   access_full_addr = access_packet[`UNIFIED_CACHE_PACKET_ADDR_POS_HI : `UNIFIED_CACHE_PACKET_ADDR_POS_LO];
wire                   is_write         = access_packet[`UNIFIED_CACHE_PACKET_IS_WRITE_POS];
wire [NUM_WAY - 1 : 0] hit_flatted;
reg  [3           : 0] stage;

generate
genvar way_index;
    for(way_index = 0; way_index < NUM_WAY; way_index = way_index + 1)
    begin
        assign hit_flatted[way_index] = (tag_flatted_in[(way_index+1) * `UNIFIED_CACHE_TAG_LEN_IN_BITS - 1 : way_index * `UNIFIED_CACHE_TAG_LEN_IN_BITS] == access_full_addr[`UNIFIED_CACHE_TAG_POS_HI : `UNIFIED_CACHE_TAG_POS_LO]) & valid_flatted_in[way_index];
    end
endgenerate

always@(posedge clk_in or posedge reset_in)
begin
    if(reset_in)
    begin
        stage                                           <= 1'b0;
        // to valid, history, dirty, tag array
        access_en_to_main_array_out                     <= 1'b0;
        write_en_to_main_array_out                      <= 1'b0;
        way_select_to_main_array_out                    <= {(NUM_WAY){1'b0}};
        access_set_addr_to_main_array_out               <= 0;
        write_single_entry_to_main_array_out            <= 1'b0;
    end
    
    else
    begin
        if(issue_grant && stage == `IDLE) // ready to issue request
        begin
            stage                                           <= `FIRST;
            // to valid, history, dirty, tag array
            access_en_to_main_array_out                     <= 1'b1;
            write_en_to_main_array_out                      <= 1'b0;
            way_select_to_main_array_out                    <= {(NUM_WAY){1'b1}};
            access_set_addr_to_main_array_out               <= access_full_addr[`UNIFIED_CACHE_INDEX_POS_HI : `UNIFIED_CACHE_INDEX_POS_HI];
            write_single_entry_to_main_array_out            <= 1'b0;
        end

        else if(stage == `FIRST)
        begin
            // to valid, history, dirty, tag array
            access_en_to_main_array_out                     <= 1'b0;
            write_en_to_main_array_out                      <= 1'b0;
            way_select_to_main_array_out                    <= {(NUM_WAY){1'b0}};
            access_set_addr_to_main_array_out               <= 0;
            write_single_entry_to_main_array_out            <= 1'b0;

            if((|hit_flatted) && ~is_write)
            begin
                stage <= `READ_HIT;
            end
            
            else if(~(|hit_flatted) && ~is_write)
            begin
                stage <= `READ_MISS;
            end
            
            else if((|hit_flatted) && is_write)
            begin
                stage <= `WRITE_HIT;
            end
            
            else if(~(|hit_flatted) && is_write)
            begin
                stage <= `WRITE_MISS;
            end
        end

        else if(stage == `READ_HIT)
        begin

        end
    end
end
endmodule