module spi_bridge (
    input        clk,
    input        rst_n,
    input        sclk,
    input        cs_n,
    input        mosi,
    output       miso,
    output       byte_sync,
    output [7:0] data_in,
    input  [7:0] data_out
);

    reg miso_reg;
    reg byte_sync_reg;
    reg [7:0] data_in_reg;

    assign miso      = miso_reg;
    assign byte_sync = byte_sync_reg;
    assign data_in   = data_in_reg;

    reg [2:0] bit_cnt;
    reg [7:0] shift_reg;
    reg [7:0] captured_data;
    reg [7:0] byte_counter;

    // capture MOSI on rising edge
    always @(posedge sclk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt <= 0;
            shift_reg <= 0;
            captured_data <= 0;
            byte_counter <= 0;
        end else if (cs_n) begin
            bit_cnt <= 0;
        //cs active
        end else begin
            shift_reg <= {shift_reg[6:0], mosi};

            //full byte read; increase byte counter and store the whole byte
            if (bit_cnt == 3'd7) begin
                bit_cnt <= 0;
                captured_data <= {shift_reg[6:0], mosi};
                byte_counter <= byte_counter + 1;
            //else, just increase number of bits read
            end else begin
                bit_cnt <= bit_cnt + 1;
            end
        end
    end

    // put the next output bit on MISO so it is stable before the master samples it
    always @(negedge sclk or negedge rst_n) begin
        if (!rst_n)
            miso_reg <= 1'b0;
        else if (!cs_n)
            miso_reg <= data_out[7 - bit_cnt];
    end

    // when cs is becoming active, make sure miso register contains data master can read
    always @(negedge cs_n or negedge rst_n) begin
        if (!rst_n)
            miso_reg <= 1'b0;
        else
            miso_reg <= data_out[7];
    end

    // synchronize byte event into clk domain
    reg [7:0] bc_sync1, bc_sync2, bc_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bc_sync1 <= 0;
            bc_sync2 <= 0;
            bc_prev  <= 0;
            byte_sync_reg <= 0;
            data_in_reg <= 0;
        end else begin
            //lag by one clock cycle
            bc_sync1 <= byte_counter;
            bc_sync2 <= bc_sync1;
            bc_prev  <= bc_sync2;

            byte_sync_reg <= 1'b0;
            // change produced, a full byte was read, send byte sync pulse 
            // copy the read byte into data_in
            if (bc_sync2 != bc_prev) begin
                byte_sync_reg <= 1'b1;
                data_in_reg <= captured_data;
            end
        end
    end

endmodule
