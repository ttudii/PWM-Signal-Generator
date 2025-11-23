module regs (
    // peripheral clock signals
    input clk,
    input rst_n,
    // decoder facing signals
    input        read,
    input        write,
    input [5:0]  addr,
    output [7:0] data_read,
    input  [7:0] data_write,
    // counter programming signals
    input  [15:0] counter_val,
    output [15:0] period,
    output        en,
    output        count_reset,
    output        upnotdown,
    output [7:0]  prescale,
    // PWM signal programming values
    output        pwm_en,
    output [7:0]  functions,
    output [15:0] compare1,
    output [15:0] compare2
);

/*
    All registers that appear in this block should be similar to this. Please try to abide
    to sizes as specified in the architecture documentation.
*/

// registrele efective
reg [15:0] period;
reg        en;
reg [15:0] compare1;
reg [15:0] compare2;
reg        count_reset;
reg [7:0]  prescale;
reg        upnotdown;
reg        pwm_en;
reg [7:0]  functions;

// COUNTER_RESET: pulse care durează 2 cicluri
reg [1:0]  count_reset_sh;

// data_read e combinational
reg [7:0] data_read;

// adrese (pe 6 biți)
localparam ADDR_PERIOD_L       = 6'h00;
localparam ADDR_PERIOD_H       = 6'h01;
localparam ADDR_COUNTER_EN     = 6'h02;
localparam ADDR_COMPARE1_L     = 6'h03;
localparam ADDR_COMPARE1_H     = 6'h04;
localparam ADDR_COMPARE2_L     = 6'h05;
localparam ADDR_COMPARE2_H     = 6'h06;
localparam ADDR_COUNTER_RESET  = 6'h07;
localparam ADDR_COUNTER_VAL_L  = 6'h08;
localparam ADDR_COUNTER_VAL_H  = 6'h09;
localparam ADDR_PRESCALE       = 6'h0A;
localparam ADDR_UPNOTDOWN      = 6'h0B;
localparam ADDR_PWM_EN         = 6'h0C;
localparam ADDR_FUNCTIONS      = 6'h0D;

// WRITE logic + COUNTER_RESET pulse
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        period         <= 16'h0000;
        en             <= 1'b0;
        upnotdown      <= 1'b1;       // să zicem default up
        prescale       <= 8'h00;      // prescale = 0 => div 1
        pwm_en         <= 1'b0;
        functions      <= 8'h00;
        compare1       <= 16'h0000;
        compare2       <= 16'h0000;
        count_reset_sh <= 2'b00;
        count_reset    <= 1'b0;
    end else begin
        // update countdown pentru COUNTER_RESET
        if (count_reset_sh != 2'b00) begin
            count_reset_sh <= count_reset_sh - 2'b01;
        end

        // derivăm semnalul de ieșire
        count_reset <= (count_reset_sh != 2'b00);

        // scrieri în registre
        if (write) begin
            case (addr)
                ADDR_PERIOD_L:      period[7:0]   <= data_write;
                ADDR_PERIOD_H:      period[15:8]  <= data_write;

                ADDR_COUNTER_EN:    en            <= data_write[0];

                ADDR_COMPARE1_L:    compare1[7:0]  <= data_write;
                ADDR_COMPARE1_H:    compare1[15:8] <= data_write;

                ADDR_COMPARE2_L:    compare2[7:0]  <= data_write;
                ADDR_COMPARE2_H:    compare2[15:8] <= data_write;

                ADDR_COUNTER_RESET: count_reset_sh <= 2'b11;   // două cicluri active

                ADDR_PRESCALE:      prescale      <= data_write;

                ADDR_UPNOTDOWN:     upnotdown     <= data_write[0];

                ADDR_PWM_EN:        pwm_en        <= data_write[0];

                ADDR_FUNCTIONS:     functions[1:0] <= data_write[1:0];
                // restul bitilor din FUNCTIONS îi ignorăm
                default: ; // adrese invalide -> ignorăm scrierea
            endcase
        end
    end
end

// READ logic (combinational)
always @(*) begin
    if (read) begin
        case (addr)
            ADDR_PERIOD_L:      data_read = period[7:0];
            ADDR_PERIOD_H:      data_read = period[15:8];

            ADDR_COUNTER_EN:    data_read = {7'b0, en};

            ADDR_COMPARE1_L:    data_read = compare1[7:0];
            ADDR_COMPARE1_H:    data_read = compare1[15:8];

            ADDR_COMPARE2_L:    data_read = compare2[7:0];
            ADDR_COMPARE2_H:    data_read = compare2[15:8];

            ADDR_COUNTER_RESET: data_read = 8'h00; // doar W, la citire dăm 0

            ADDR_COUNTER_VAL_L: data_read = counter_val[7:0];
            ADDR_COUNTER_VAL_H: data_read = counter_val[15:8];

            ADDR_PRESCALE:      data_read = prescale;

            ADDR_UPNOTDOWN:     data_read = {7'b0, upnotdown};

            ADDR_PWM_EN:        data_read = {7'b0, pwm_en};

            ADDR_FUNCTIONS:     data_read = functions;

            default:            data_read = 8'h00;
        endcase
    end else begin
        data_read = 8'h00;
    end
end

endmodule
