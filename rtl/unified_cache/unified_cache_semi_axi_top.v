`include "parameters.h"

module unified_cache_semi_axi_top
#
(
    // cache parameters
    parameter NUM_INPUT_PORT                        = 1,
    parameter NUM_BANK                              = 4,
    parameter NUM_SET                               = 4,
    parameter NUM_WAY                               = 4,
    parameter BLOCK_SIZE_IN_BYTES                   = 4,
    parameter UNIFIED_CACHE_PACKET_WIDTH_IN_BITS    = `UNIFIED_CACHE_PACKET_WIDTH_IN_BITS,
    parameter PORT_ID_WIDTH                         = $clog2(NUM_INPUT_PORT) + 1,
    parameter BANK_BITS                             = $clog2(NUM_BANK)，

    // AXI parameters
    parameter C_M_TARGET_SLAVE_BASE_ADDR	        = 32'h0000_0000,
    parameter C_M_AXI_ADDR_WIDTH	                = 32,
    parameter C_M_AXI_DATA_WIDTH	                = 32,
    parameter C_M_AXI_BURST_LEN	                    = BLOCK_SIZE_IN_BYTES * `BYTE_LEN_IN_BITS / C_M_AXI_DATA_WIDTH,
    parameter C_M_AXI_ID_WIDTH	                    = 4,
    parameter C_M_AXI_AWUSER_WIDTH	                = 1,
    parameter C_M_AXI_ARUSER_WIDTH	                = 1,
    parameter C_M_AXI_WUSER_WIDTH	                = 1,
    parameter C_M_AXI_RUSER_WIDTH	                = 1,
    parameter C_M_AXI_BUSER_WIDTH	                = 1
)
(
    input                                                                               reset_in,
    input                                                                               clk_in,

    // input packet
    input   [NUM_INPUT_PORT * (UNIFIED_CACHE_PACKET_WIDTH_IN_BITS) - 1 : 0]             input_packet_flatted_in,
    output  [NUM_INPUT_PORT - 1 : 0]                                                    input_packet_ack_flatted_out,

    // return packet
    output  [NUM_INPUT_PORT * (UNIFIED_CACHE_PACKET_WIDTH_IN_BITS) - 1 : 0]             return_packet_flatted_out,
    input   [NUM_INPUT_PORT - 1 : 0]                                                    return_packet_ack_flatted_in,

    //AXI signals
    input                                           M_AXI_ACLK,
    input                                           M_AXI_ARESETN,
    output      [C_M_AXI_ID_WIDTH       - 1 : 0]    M_AXI_AWID,
    output      [C_M_AXI_ADDR_WIDTH     - 1 : 0]    M_AXI_AWADDR,
    output      [7                          : 0]    M_AXI_AWLEN,
    output      [2                          : 0]    M_AXI_AWSIZE,
    output      [1                          : 0]    M_AXI_AWBURST,
    output                                          M_AXI_AWLOCK,
    output      [3                          : 0]    M_AXI_AWCACHE,
    output      [2                          : 0]    M_AXI_AWPROT,
    output      [3                          : 0]    M_AXI_AWQOS,
    output      [C_M_AXI_AWUSER_WIDTH   - 1 : 0]    M_AXI_AWUSER,
    output                                          M_AXI_AWVALID,
    input                                           M_AXI_AWREADY,
    output      [C_M_AXI_DATA_WIDTH     - 1 : 0]    M_AXI_WDATA,
    output      [C_M_AXI_DATA_WIDTH / 8 - 1 : 0]    M_AXI_WSTRB,
    output                                          M_AXI_WLAST,
    output      [C_M_AXI_WUSER_WIDTH    - 1 : 0]    M_AXI_WUSER,
    output                                          M_AXI_WVALID,
    input                                           M_AXI_WREADY,
    input       [C_M_AXI_ID_WIDTH       - 1 : 0]    M_AXI_BID,
    input       [1                          : 0]    M_AXI_BRESP,
    input       [C_M_AXI_BUSER_WIDTH    - 1 : 0]    M_AXI_BUSER,
    input                                           M_AXI_BVALID,
    output                                          M_AXI_BREADY,
    output      [C_M_AXI_ID_WIDTH       - 1 : 0]    M_AXI_ARID,
    output      [C_M_AXI_ADDR_WIDTH     - 1 : 0]    M_AXI_ARADDR,
    output      [7                          : 0]    M_AXI_ARLEN,
    output      [2                          : 0]    M_AXI_ARSIZE,
    output      [1                          : 0]    M_AXI_ARBURST,
    output                                          M_AXI_ARLOCK,
    output      [3                          : 0]    M_AXI_ARCACHE,
    output      [2                          : 0]    M_AXI_ARPROT,
    output      [3                          : 0]    M_AXI_ARQOS,
    output      [C_M_AXI_ARUSER_WIDTH   - 1 : 0]    M_AXI_ARUSER,
    output                                          M_AXI_ARVALID,
    input                                           M_AXI_ARREADY,
    input       [C_M_AXI_ID_WIDTH       - 1 : 0]    M_AXI_RID,
    input       [C_M_AXI_DATA_WIDTH     - 1 : 0]    M_AXI_RDATA,
    input       [1                          : 0]    M_AXI_RRESP,
    input                                           M_AXI_RLAST,
    input       [C_M_AXI_RUSER_WIDTH    - 1 : 0]    M_AXI_RUSER,
    input                                           M_AXI_RVALID,
    output                                          M_AXI_RREADY
);

reg                                                 init_pulse;
wire [`UNIFIED_CACHE_PACKET_WIDTH_IN_BITS - 1 : 0]  cache_to_mem_packet;
wire [`UNIFIED_CACHE_PACKET_WIDTH_IN_BITS - 1 : 0]  mem_to_cache_packet;
wire [`UNIFIED_CACHE_BLOCK_SIZE_IN_BITS   - 1 : 0]  mem_return_data;

wire                                                mem_done;
wire                                                from_cache_ack;
reg                                                 to_cache_ack;

// generate master pulse

reg [`UNIFIED_CACHE_PACKET_WIDTH_IN_BITS - 1 : 0]   cache_to_mem_packet_last_cycle;

always@(posedge clk_in or posedge reset_in)
begin
    if(reset_in)
    begin
        init_pulse                              <= 1'b0;
        cache_to_mem_packet_valid_last_cycle    <= 1'b0;
    end

    else
    begin
        cache_to_mem_packet_last_cycle <= cache_to_mem_packet;
        
        if(cache_to_mem_packet[`UNIFIED_CACHE_PACKET_VALID_POS] & cache_to_mem_packet != cache_to_mem_packet_last_cycle)
        begin
            if(~init_pulse)
            begin
                init_pulse      <= 1'b1;
            end
        end

        else if(cache_to_mem_packet[`UNIFIED_CACHE_PACKET_VALID_POS])
        begin
            init_pulse      <= 1'b0;
        end
    end
end

// release to cache ack
always@(posedge clk_in or posedge reset_in)
begin
    if(reset_in)
    begin
        to_cache_ack <= 1'b0;
    end

    else
    begin
        // write
        if(cache_to_mem_packet[`UNIFIED_CACHE_PACKET_VALID_POS]    &
           cache_to_mem_packet[`UNIFIED_CACHE_PACKET_IS_WRITE_POS] &
           mem_done)
        begin
            to_cache_ack <= 1'b1;
        end

        // read
        else if(cache_to_mem_packet[`UNIFIED_CACHE_PACKET_VALID_POS]     &
                ~cache_to_mem_packet[`UNIFIED_CACHE_PACKET_IS_WRITE_POS] &
                from_cache_ack)
            to_cache_ack <= 1'b1;
        
        else to_cache_ack <= 1'b1;
    end
end

// generate to cache packet
always@(posedge clk_in or posedge reset_in)
begin
    if(reset_in)
    begin
        mem_to_cache_packet <= 0;
    end

    else
    begin
        if(cache_to_mem_packet[`UNIFIED_CACHE_PACKET_VALID_POS]    &
          ~cache_to_mem_packet[`UNIFIED_CACHE_PACKET_IS_WRITE_POS] &
          mem_done)
        begin
            mem_to_cache_packet <=
            {   
                /*cacheable*/   {cache_to_mem_packet[`UNIFIED_CACHE_PACKET_CACHEABLE_POS]},
                /*write*/       {cache_to_mem_packet[`UNIFIED_CACHE_PACKET_IS_WRITE_POS]},                   
                /*valid*/       {cache_to_mem_packet[`UNIFIED_CACHE_PACKET_VALID_POS]},
                /*port*/        {cache_to_mem_packet[`UNIFIED_CACHE_PACKET_PORT_NUM_HI : `UNIFIED_CACHE_PACKET_PORT_NUM_LO]},
                /*byte mask*/   {cache_to_mem_packet[`UNIFIED_CACHE_PACKET_BYTE_MASK_POS_HI : `UNIFIED_CACHE_PACKET_BYTE_MASK_POS_LO]},     
                /*type*/        {cache_to_mem_packet[`UNIFIED_CACHE_PACKET_TYPE_POS_HI : `UNIFIED_CACHE_PACKET_TYPE_POS_LO]},
                /*data*/        {mem_return_data},
                /*addr*/        {cache_to_mem_packet[`UNIFIED_CACHE_PACKET_ADDR_POS_HI : `UNIFIED_CACHE_PACKET_ADDR_POS_LO]}
            };
        end

        else if(from_cache_ack)
        begin
            mem_to_cache_packet <= 0;
        end

        else
            mem_to_cache_packet <= mem_to_cache_packet;
    end
end

unified_cache
#(
    .UNIFIED_CACHE_PACKET_WIDTH_IN_BITS (`UNIFIED_CACHE_PACKET_WIDTH_IN_BITS),
    .NUM_INPUT_PORT                     (NUM_INPUT_PORT),
    .NUM_BANK                           (NUM_BANK),
    .NUM_SET                            (NUM_SET),
    .NUM_WAY                            (NUM_WAY),
    .BLOCK_SIZE_IN_BYTES                (BLOCK_SIZE_IN_BYTES),
)
unified_cache
(
    .reset_in                       (reset_in),
    .clk_in                         (clk_in),
    .input_packet_flatted_in        (input_packet_flatted_in),
    .input_packet_ack_flatted_out   (input_packet_ack_flatted_out),

    .return_packet_flatted_out      (return_packet_flatted_out),
    .return_packet_ack_flatted_in   (return_packet_ack_flatted_in),

    .from_mem_packet_in             (mem_to_cache_packet),
    .from_mem_packet_ack_out        (from_cache_ack),

    .to_mem_packet_out              (cache_to_mem_packet),
    .to_mem_packet_ack_in           (to_cache_ack)
);

axi4_master
#(
    C_M_TARGET_SLAVE_BASE_ADDR      (C_M_TARGET_SLAVE_BASE_ADDR),
    C_M_AXI_ADDR_WIDTH              (C_M_AXI_ADDR_WIDTH),
    C_M_AXI_DATA_WIDTH	            (C_M_AXI_DATA_WIDTH),
    C_M_AXI_BURST_LEN	            (C_M_AXI_BURST_LEN),
    C_M_AXI_ID_WIDTH	            (C_M_AXI_ID_WIDTH),
    C_M_AXI_AWUSER_WIDTH	        (C_M_AXI_AWUSER_WIDTH),
    C_M_AXI_ARUSER_WIDTH	        (C_M_AXI_ARUSER_WIDTH),
    C_M_AXI_WUSER_WIDTH	            (C_M_AXI_WUSER_WIDTH),
    C_M_AXI_RUSER_WIDTH	            (C_M_AXI_RUSER_WIDTH),
    C_M_AXI_BUSER_WIDTH	            (C_M_AXI_BUSER_WIDTH)
)
axi4_master
(
    INIT_AXI_TXN                    (init_pulse),
    TRANSACTION_PACKET              (cache_to_mem_packet),
    RETURN_DATA                     (mem_return_data),
    TXN_DONE                        (mem_done),

    M_AXI_ACLK                      (M_AXI_ACLK),
    M_AXI_ARESETN                   (M_AXI_ARESETN),
    M_AXI_AWID                      (M_AXI_AWID),
    M_AXI_AWADDR                    (M_AXI_AWADDR),
    M_AXI_AWLEN                     (M_AXI_AWLEN),
    M_AXI_AWSIZE                    (M_AXI_AWSIZE),
    M_AXI_AWBURST                   (M_AXI_AWBURST),
    M_AXI_AWLOCK                    (M_AXI_AWLOCK),
    M_AXI_AWCACHE                   (M_AXI_AWCACHE),
    M_AXI_AWPROT                    (M_AXI_AWPROT),
    M_AXI_AWQOS                     (M_AXI_AWQOS),
    M_AXI_AWUSER                    (M_AXI_AWUSER),
    M_AXI_AWVALID                   (M_AXI_AWVALID),
    M_AXI_AWREADY                   (M_AXI_AWREADY),
    M_AXI_WDATA                     (M_AXI_WDATA),
    M_AXI_WSTRB                     (M_AXI_WSTRB),
    M_AXI_WLAST                     (M_AXI_WLAST),
    M_AXI_WUSER                     (M_AXI_WUSER),
    M_AXI_WVALID                    (M_AXI_WVALID),
    M_AXI_WREADY                    (M_AXI_WREADY),
    M_AXI_BID                       (M_AXI_BID),
    M_AXI_BRESP                     (M_AXI_BRESP),
    M_AXI_BUSER                     (M_AXI_BUSER),
    M_AXI_BVALID                    (M_AXI_BVALID),
    M_AXI_BREADY                    (M_AXI_BREADY),
    M_AXI_ARID                      (M_AXI_ARID),
    M_AXI_ARADDR                    (M_AXI_ARADDR),
    M_AXI_ARLEN                     (M_AXI_ARLEN),
    M_AXI_ARSIZE                    (M_AXI_ARSIZE),
    M_AXI_ARBURST                   (M_AXI_ARBURST),
    M_AXI_ARLOCK                    (M_AXI_ARLOCK),
    M_AXI_ARCACHE                   (M_AXI_ARCACHE),
    M_AXI_ARPROT                    (M_AXI_ARPROT),
    M_AXI_ARQOS                     (M_AXI_ARQOS),
    M_AXI_ARUSER                    (M_AXI_ARUSER),
    M_AXI_ARVALID                   (M_AXI_ARVALID),
    M_AXI_ARREADY                   (M_AXI_ARREADY),
    M_AXI_RID                       (M_AXI_RID),
    M_AXI_RDATA                     (M_AXI_RDATA),
    M_AXI_RRESP                     (M_AXI_RRESP),
    M_AXI_RLAST                     (M_AXI_RLAST),
    M_AXI_RUSER                     (M_AXI_RUSER),
    M_AXI_RVALID                    (M_AXI_RVALID),
    M_AXI_RREADY                    (M_AXI_RREADY)
);