`define START 8'hff
`define TRAIN 8'hf0
`define TEST  8'h0f
`define STOP  8'hff

module uart_protocol
    #(IMG_SZ = 784<<3)
    (
    input  logic              uart_sampling_clk, rst, data_rdy,
    input  logic [7:0]        uart_byte,
    output logic              start, train, resend,
    output logic [IMG_SZ-1:0] image);

    enum logic [2:0] {s_start, s_train, s_data, s_check, s_stop} cs, ns;

    logic shift, inc;
    logic [15:0] count; // 16 bits should be big enough for our IMG_SZs
    logic [7:0]  checksum, checksum_add, result;
    
    always_ff @(posedge uart_sampling_clk, posedge rst) begin 
        if (rst) begin
            cs <= s_start;
            image <= 'd0;
            count <= 16'd0;
            checksum <= 8'd0;
        end
        else begin 
            cs <= ns;
            // Shift image data into this register
            image <= (shift) ? {image[IMG_SZ-1:8], uart_byte} : image;
            count <= next_count;
            checksum <= result;
        end
    end

    // Use one's complement addition to calculate checksum because it's
    // better for catching errors
    ones_comp_add add (.A(checksum), .B(checksum_add), .C(result));
     
    always_comb begin
        shift = 1'b0;
        start = 1'b0;
        train = 1'b0;
        next_count = 16'd0;
        checksum_add = 8'd0;
        resend = 1'b0;
        case (cs)
            s_start: begin
                ns = (data_rdy && uart_byte == `START) ? s_train : s_start;
            end
            s_train: begin
                ns = (data_rdy && (uart_byte == `TRAIN || uart_byte == `TEST)) 
                     ? s_data : s_train;
                // Asserted for one cycle, buffered and cleared in control unit
                train = (data_rdy && uart_byte == `TRAIN) ? 1'b1 : 1'b0;
            end
            s_data: begin
                // Shift in all the pixel data
                ns = (data_rdy && count == IMG_SZ - 16'd8) ? s_check : s_data; 
                shift = (data_rdy) ? 1'b1 : 1'b0;
                next_count = (data_rdy) ? count + 16'd8 : count;
                checksum_add = uart_byte;
            end
            s_check: begin
                ns = (data_rdy) ? ((uart_byte == checksum) ? s_stop : s_start) 
                                  : s_check;
                resend = (data_rdy) ? ((uart_byte == checksum) ? 1'b0 : 1'b1) 
                                  : 1'b0;
            end
            s_stop: begin
                ns = (data_rdy && uart_byte == `STOP) ? s_start : s_stop;
                // Asserted for one cycle, buffered and cleared in control unit
                start = (data_rdy && uart_byte == `STOP) ? 1'b1 : 1'b0;
            end
        endcase
    end

endmodule: uart_protocol
