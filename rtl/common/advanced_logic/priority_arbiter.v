module priority_arbiter
#(
    parameter SINGLE_REQUEST_WIDTH_IN_BITS = 64,
    parameter NUM_REQUEST                  = 3,
    parameter NUM_REQUEST_LOG2             = $clog2(NUM_REQUEST) + 1,
    parameter INPUT_QUEUE_SIZE             = 2, // must be a power of 2
    parameter BYTE_PADDING_WIDTH           = 8
)
(
    input                                                               reset_in,
    input                                                               clk_in,

    input      [SINGLE_REQUEST_WIDTH_IN_BITS * NUM_REQUEST - 1 : 0]     request_flatted_in,
    input      [NUM_REQUEST                                - 1 : 0]     request_valid_flatted_in,
    input      [NUM_REQUEST                                - 1 : 0]     request_critical_flatted_in,
    output     [NUM_REQUEST                                - 1 : 0]     issue_ack_out,

    output reg [SINGLE_REQUEST_WIDTH_IN_BITS               - 1 : 0]     request_out,
    output reg                                                          request_valid_out,
    input                                                               issue_ack_in
);

// separete requests to input queue
wire [SINGLE_REQUEST_WIDTH_IN_BITS  - 1 : 0] request_packed_in [NUM_REQUEST - 1 : 0];
wire [NUM_REQUEST                   - 1 : 0] arbiter_ack_flatted_to_request_queue;

// separete requests from input queue
wire [SINGLE_REQUEST_WIDTH_IN_BITS  - 1 : 0] request_packed_from_request_queue [NUM_REQUEST - 1 : 0];
wire [NUM_REQUEST                   - 1 : 0] request_valid_flatted_from_request_queue;
wire [NUM_REQUEST                   - 1 : 0] request_queue_full;
wire [BYTE_PADDING_WIDTH            - 1 : 0] request_critical_flatted_from_request_queue [NUM_REQUEST - 1 : 0];

generate
genvar request_index;
for(request_index = 0; request_index < NUM_REQUEST; request_index = request_index + 1)
begin : request_queue

    assign request_packed_in[request_index] =
           request_flatted_in[(request_index) * (SINGLE_REQUEST_WIDTH_IN_BITS) +: (SINGLE_REQUEST_WIDTH_IN_BITS)];

    fifo_queue
    #(
        .QUEUE_SIZE                     (INPUT_QUEUE_SIZE),
        .SINGLE_ENTRY_WIDTH_IN_BITS     (SINGLE_REQUEST_WIDTH_IN_BITS + 8)
    )
    request_queue
    (
        .reset_in                       (reset_in),
        .clk_in                         (clk_in),

        .is_empty_out                   (), // intended to be left unconnected
        .is_full_out                    (request_queue_full[request_index]),

        .request_in                     ({{(BYTE_PADDING_WIDTH){request_critical_flatted_in[request_index]}},
                                          request_packed_in[request_index]}),
        .request_valid_in               (request_valid_flatted_in[request_index]),
        .issue_ack_out                  (issue_ack_out[request_index]),

        .request_out                    ({request_critical_flatted_from_request_queue[request_index],
                                          request_packed_from_request_queue[request_index]}),
        .request_valid_out              (request_valid_flatted_from_request_queue[request_index]),
        .issue_ack_in                   (arbiter_ack_flatted_to_request_queue[request_index])
    );
end
endgenerate

wire [NUM_REQUEST - 1 : 0] request_critical_final;
for(request_index = 0; request_index < NUM_REQUEST; request_index = request_index + 1)
begin
    assign request_critical_final[request_index] = (|request_critical_flatted_from_request_queue[request_index]) | request_queue_full[request_index];
end
reg [NUM_REQUEST_LOG2 - 1 : 0] last_send_index;

// shift the request valid/critical flatted wire
wire [NUM_REQUEST - 1 : 0] request_valid_flatted_shift_left;
wire [NUM_REQUEST - 1 : 0] request_critical_flatted_shift_left;

assign request_valid_flatted_shift_left     = (request_valid_flatted_from_request_queue >> last_send_index + 1) | (request_valid_flatted_from_request_queue << (NUM_REQUEST - last_send_index - 1));
assign request_critical_flatted_shift_left  = (request_critical_final >> last_send_index + 1) | (request_critical_final << (NUM_REQUEST - last_send_index - 1));

// find the first valid requests
reg [NUM_REQUEST_LOG2 - 1 : 0] valid_sel;
integer                        valid_find_index;

always@*
begin : Find_First_Valid_Way
    valid_sel  <= {(NUM_REQUEST_LOG2){1'b0}};

    for(valid_find_index = 0; valid_find_index < NUM_REQUEST; valid_find_index = valid_find_index + 1)
    begin
        if(request_valid_flatted_shift_left[valid_find_index])
        begin
            if(last_send_index + valid_find_index + 1 >= NUM_REQUEST)
                    valid_sel <= last_send_index + valid_find_index + 1 - NUM_REQUEST;
            else
                    valid_sel <= last_send_index + valid_find_index + 1;
            disable Find_First_Valid_Way; //TO exit the loop
        end
    end
end

// find the first critical requests
reg [NUM_REQUEST_LOG2 - 1 : 0] critical_sel;
integer                        critical_find_index;

always@*
begin : Find_First_Critical_Way
    critical_sel  <= {(NUM_REQUEST_LOG2){1'b0}};

    for(critical_find_index = 0; critical_find_index < NUM_REQUEST; critical_find_index = critical_find_index + 1)
    begin
        if(request_critical_flatted_shift_left[critical_find_index] & request_valid_flatted_shift_left[critical_find_index])
        begin
            if(last_send_index + critical_find_index + 1 >= NUM_REQUEST)
                    critical_sel <= last_send_index + critical_find_index + 1 - NUM_REQUEST;
            else
                    critical_sel <= last_send_index + critical_find_index + 1;
            disable Find_First_Critical_Way; //TO exit the loop
        end
    end
end

// fill the valid/critical mask
wire [NUM_REQUEST - 1 : 0] valid_mask;
wire [NUM_REQUEST - 1 : 0] critical_mask;

generate
    for(request_index = 0; request_index < NUM_REQUEST; request_index = request_index + 1)
    begin
        assign    valid_mask[request_index]      =    valid_sel == request_index ? 1 : 0;
        assign critical_mask[request_index]      = critical_sel == request_index ? 1 : 0;
    end
endgenerate

generate
    for(request_index = 0; request_index < NUM_REQUEST; request_index = request_index + 1)
    begin
        assign arbiter_ack_flatted_to_request_queue[request_index] = 
                (issue_ack_in & (last_send_index == request_index)) ? 1 : 0;
    end
endgenerate

// arbiter logic
always@(posedge clk_in)
begin
    if(reset_in)
    begin
        request_out                             <= {(SINGLE_REQUEST_WIDTH_IN_BITS){1'b0}};
        request_valid_out                       <= 1'b0;
        last_send_index                         <= {(NUM_REQUEST_LOG2){1'b0}};
    end

    // move on to the next request
    else if((issue_ack_in & request_valid_out) | ~request_valid_out)
    begin
        if(~request_valid_out)
        begin
            if(request_critical_final[critical_sel] & request_valid_flatted_from_request_queue[critical_sel])
            begin
                request_out                             <= request_packed_from_request_queue[critical_sel];
                request_valid_out                       <= 1'b1;
                last_send_index                         <= critical_sel;
            end

            else if(request_valid_flatted_from_request_queue[valid_sel])
            begin
                request_out                             <= request_packed_from_request_queue[valid_sel];
                request_valid_out                       <= 1'b1;
                last_send_index                         <= valid_sel;
            end
        end
        // a empty cycle is needed to wait for the input queue to deliver new data
        else
        begin
            request_out                             <= {(SINGLE_REQUEST_WIDTH_IN_BITS){1'b0}};
            request_valid_out                       <= 1'b0;
            last_send_index                         <= last_send_index;
        end
    end

    else
    begin
        request_out                             <= request_out;
        request_valid_out                       <= request_valid_out;
        last_send_index                         <= last_send_index;
    end
end

endmodule
