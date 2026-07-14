/*
 * Copyright (c) 2025 Michael Bell
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Wrapper for all TinyQV peripherals
//
// Address space:
// 0x800_0000 - 03f: Reserved by project wrapper (time, debug, etc)
// 0x800_0040 - 07f: GPIO configuration
// 0x800_0080 - 0bf: UART
// 0x800_00c0 - 0ff: Game pmod
// 0x800_0100 - 2bf: 7 user peripherals (64 bytes each, word and halfword access supported, each has an interrupt)
// 0x800_0400 - 43f: 4 simple peripherals (16 bytes each, byte access only)
module tinyQV_peripherals #(
    parameter CLOCK_KHZ=64000, 
    parameter NUM_GPIO=8
) (
    input         clk,
    input         rst_n,

    input  [NUM_GPIO-1:0]  gpio_in,        // GPIO inputs, always available
    input  [NUM_GPIO-1:0]  gpio_in_raw,    // GPIO inputs, not synchronized
    output [NUM_GPIO-1:0]  gpio_out,       // GPIO output.  Each wire is only connected if this peripheral is selected
    output [NUM_GPIO-1:0]  gpio_oe,        // GPIO output enable.
    output [NUM_GPIO-1:0]  gpio_pu,        // GPIO pull up
    output [NUM_GPIO-1:0]  gpio_pd,        // GPIO pull down

    input [10:0]  addr_in,
    input [31:0]  data_in,      // Data in to the peripheral, bottom 8, 16 or all 32 bits are valid on write.

    // Data read and write requests from the TinyQV core.
    input [1:0]   data_write_n, // 11 = no write, 00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    input [1:0]   data_read_n,  // 11 = no read,  00 = 8-bits, 01 = 16-bits, 10 = 32-bits

    output [31:0] data_out,     // Data out from the peripheral, bottom 8, 16 or all 32 bits are valid on read when data_ready is high.
    output        data_ready,

    input         data_read_complete,  // Set by TinyQV when a read is complete

    output [9:2] user_interrupts  // User peripherals get interrupts 2-6
);

    localparam NUM_USER_PERI = 10;
    localparam NUM_SIMPLE_PERI = 4;

    // Registered data out to TinyQV
    reg  [31:0] data_out_r;
    reg         data_out_hold;
    reg         data_ready_r;

    wire        read_req = data_read_n != 2'b11;

    // Muxed data out direct from selected peripheral
    reg [31:0] data_from_peri;
    reg        data_ready_from_peri;

    // Must mask the data_read_n to avoid extra read while
    // buffering the result
    wire [1:0] data_read_n_peri;
    assign data_read_n_peri = data_read_n | {2{data_ready_r}};

    wire [31:0] data_from_user_peri   [0:NUM_USER_PERI-1];
    wire [7:0]  data_from_simple_peri [0:NUM_SIMPLE_PERI-1];
    wire        data_ready_from_user_peri   [0:NUM_USER_PERI-1];

    wire [NUM_GPIO-1:0]  uo_out_from_user_peri   [0:NUM_USER_PERI-1];
    wire [NUM_GPIO-1:0]  uo_out_from_simple_peri [0:NUM_SIMPLE_PERI-1];
    reg [NUM_GPIO-1:0] uo_out_comb;
    assign gpio_out = uo_out_comb;

    // Rebuffer reset on positive edge of clock.  This is fine providing peripherals
    // don't use async reset.
    (* keep *) reg rst_n_rebuf;
    /* verilator lint_off SYNCASYNCNET */
    (* keep *) reg rst_n_rebuf_negedge;
    /* verilator lint_on SYNCASYNCNET */
    always @(posedge clk) begin
        rst_n_rebuf <= rst_n;
    end
    always @(negedge clk) begin
        rst_n_rebuf_negedge <= rst_n_rebuf;
    end

    // Register the data output from the peripheral.  This improves timing and
    // also simplifies the peripheral interface (no need for the peripheral to care
    // about holding data_out until data_read_complete - it looks like it is read
    // synchronously).
    always @(posedge clk) begin
        if (!rst_n_rebuf) begin
            data_out_hold <= 0;
        end else begin
            if (data_read_complete) data_out_hold <= 0;

            if (!data_out_hold && data_ready_from_peri && data_read_n != 2'b11) begin
                data_out_hold <= 1;
                data_out_r <= data_from_peri;
            end

            // Data ready must be registered because data_out is.
            data_ready_r <= read_req && data_ready_from_peri;
        end
    end

    assign data_out = data_out_r;
    assign data_ready = data_ready_r || data_write_n != 2'b11;

    // --------------------------------------------------------------------- //
    // Decode the address to select the active peripheral

    localparam PERI_GPIO = 1;
    localparam PERI_UART = 2;

    reg [NUM_USER_PERI-1:0] peri_user;
    reg [NUM_SIMPLE_PERI-1:0] peri_simple;

    always @(*) begin
        peri_user = 0;
        peri_simple = 0;

        if (addr_in[10:9] == 2'b10) begin
            peri_simple[addr_in[5:4]] = 1;
            data_from_peri = {24'h0, data_from_simple_peri[addr_in[5:4]]};
            data_ready_from_peri = 1;
        end else begin
            peri_user[addr_in[9:6]] = 1;
            data_from_peri = data_from_user_peri[addr_in[9:6]];
            data_ready_from_peri = data_ready_from_user_peri[addr_in[9:6]];
        end
    end

    assign data_from_user_peri[0] = 32'h0;
    assign data_ready_from_user_peri[0] = 0;
    assign uo_out_from_user_peri[0] = '0;

    // --------------------------------------------------------------------- //
    // GPIO

    reg [4:0] gpio_out_func_sel [0:NUM_GPIO-1];
    reg [NUM_GPIO-1:0] io_out;
    reg [NUM_GPIO-1:0] io_oe;
    reg [NUM_GPIO-1:0] io_pu;
    reg [NUM_GPIO-1:0] io_pd;

    always @(posedge clk) begin
        if (!rst_n_rebuf) begin
            io_out <= 0;
            io_oe <= 1;
            io_pu <= 0;
            io_pd <= 0;
        end else if (peri_user[PERI_GPIO]) begin
            case(addr_in[5:0])
                6'h0: if (data_write_n != 2'b11) io_out <= data_in[NUM_GPIO-1:0];
                6'h8: if (data_write_n != 2'b11) io_oe <= data_in[NUM_GPIO-1:0];
                6'hc: if (data_write_n != 2'b11) io_pu <= data_in[NUM_GPIO-1:0];
                6'h10: if (data_write_n != 2'b11) io_pd <= data_in[NUM_GPIO-1:0];
                default:;
            endcase
        end
    end

    assign data_from_user_peri[PERI_GPIO] = (addr_in[5:0] == 6'h0) ? {{32-NUM_GPIO{1'b0}}, io_out} :
                                            (addr_in[5:0] == 6'h4) ? {{32-NUM_GPIO{1'b0}}, gpio_in} :
                                            (addr_in[5:0] == 6'h8) ? {{32-NUM_GPIO{1'b0}}, io_oe} :
                                            (addr_in[5:0] == 6'hc) ? {{32-NUM_GPIO{1'b0}}, io_pu} :
                                            (addr_in[5:0] == 6'h10) ? {{32-NUM_GPIO{1'b0}}, io_pd} :
                                            (addr_in[5]) ? {27'h0, gpio_out_func_sel[addr_in[4:0]][4:0] } :
                                            32'h0;
    assign data_ready_from_user_peri[PERI_GPIO] = 1;
    assign uo_out_from_user_peri[PERI_GPIO] = io_out;

    wire usb_tx_en;
    assign gpio_oe[NUM_GPIO-1:5] = io_oe[NUM_GPIO-1:5];
    assign gpio_oe[4] = gpio_out_func_sel[4] == 5'd7 ? usb_tx_en : io_oe[4];
    assign gpio_oe[3] = gpio_out_func_sel[3] == 5'd7 ? usb_tx_en : io_oe[3];
    assign gpio_oe[2:0] = io_oe[2:0];
    assign gpio_pu = io_pu;
    assign gpio_pd = io_pd;

    genvar i;
    generate
        for (i = 0; i < NUM_GPIO; i = i + 1) begin
            always @(posedge clk) begin
                if (!rst_n_rebuf) begin
                    gpio_out_func_sel[i] <= (i == 0) ? PERI_UART : PERI_GPIO;
                end else if (peri_user[PERI_GPIO]) begin
                    if (addr_in[5] && addr_in[4:0] == i) begin
                        if (data_write_n != 2'b11) gpio_out_func_sel[i] <= {data_in[4:0]};
                    end
                end
            end

            always @(*) begin
                uo_out_comb[i] = 0;

                if (gpio_out_func_sel[i][4]) begin
                    uo_out_comb[i] = uo_out_from_simple_peri[gpio_out_func_sel[i][1:0]][i];
                end else begin
                    uo_out_comb[i] = uo_out_from_user_peri[gpio_out_func_sel[i][3:0]][i];
                end
            end
        end
    endgenerate

    // --------------------------------------------------------------------- //
    // UART

    tqvp_uart_wrapper #(.CLOCK_KHZ(CLOCK_KHZ), .NUM_GPIO(NUM_GPIO)) i_uart (
        .clk(clk),
        .rst_n(rst_n_rebuf),

        .ui_in(gpio_in),
        .uo_out(uo_out_from_user_peri[PERI_UART]),

        .address(addr_in[5:0]),
        .data_in(data_in),

        .data_write_n(data_write_n    | {2{~peri_user[PERI_UART]}}),
        .data_read_n(data_read_n_peri | {2{~peri_user[PERI_UART]}}),

        .data_out(data_from_user_peri[PERI_UART]),
        .data_ready(data_ready_from_user_peri[PERI_UART]),

        .user_interrupt(user_interrupts[PERI_UART+1:PERI_UART])
    );

    // Peripheral 3 is a full peripheral but with no interrupt
    tqvp_game_pmod #(.NUM_GPIO(NUM_GPIO)) i_user_peri03(
        .clk(clk),
        .rst_n(rst_n_rebuf),

        .ui_in(gpio_in),
        .uo_out(uo_out_from_user_peri[3]),

        .address(addr_in[5:0]),
        .data_in(data_in),

        .data_write_n(data_write_n    | {2{~peri_user[3]}}),
        .data_read_n(data_read_n_peri | {2{~peri_user[3]}}),

        .data_out(data_from_user_peri[3]),
        .data_ready(data_ready_from_user_peri[3])
    );

    // --------------------------------------------------------------------- //
    // Full interface peripherals

    tqvp_hx2003_pulse_transmitter #(.NUM_GPIO(NUM_GPIO)) i_user_peri04(
        .clk(clk),
        .rst_n(rst_n_rebuf),

        .ui_in(gpio_in),
        .uo_out(uo_out_from_user_peri[4]),

        .address(addr_in[5:0]),
        .data_in(data_in),

        .data_write_n(data_write_n    | {2{~peri_user[4]}}),
        .data_read_n(data_read_n_peri | {2{~peri_user[4]}}),

        .data_out(data_from_user_peri[4]),
        .data_ready(data_ready_from_user_peri[4]),

        .user_interrupt(user_interrupts[4])
    );

    tqvp_toivoh_pwl_synth #(.NUM_GPIO(NUM_GPIO)) i_user_peri05 (
        .clk(clk),
        .rst_n(rst_n_rebuf_negedge),

        .ui_in(gpio_in),
        .uo_out(uo_out_from_user_peri[5]),

        .address(addr_in[5:0]),
        .data_in(data_in),

        .data_write_n(data_write_n    | {2{~peri_user[5]}}),
        .data_read_n(data_read_n_peri | {2{~peri_user[5]}}),

        .data_out(data_from_user_peri[5]),
        .data_ready(data_ready_from_user_peri[5]),

        .user_interrupt(user_interrupts[5])
    );

    tqvp_CORDIC #(.NUM_GPIO(NUM_GPIO)) i_user_peri06 (
        .clk(clk),
        .rst_n(rst_n_rebuf),

        .ui_in(gpio_in),
        .uo_out(uo_out_from_user_peri[6]),

        .address(addr_in[5:0]),
        .data_in(data_in),

        .data_write_n(data_write_n    | {2{~peri_user[6]}}),
        .data_read_n(data_read_n_peri | {2{~peri_user[6]}}),

        .data_out(data_from_user_peri[6]),
        .data_ready(data_ready_from_user_peri[6]),

        .user_interrupt(user_interrupts[6])
    );

    tqvp_usb_cdc #(.NUM_GPIO(NUM_GPIO)) i_usb_cdc_peri07 (
        .clk(clk),
        .rst_n(rst_n_rebuf),

        .ui_in(gpio_in),
        .uo_out(uo_out_from_user_peri[7]),

        .usb_tx_en(usb_tx_en),

        .address(addr_in[5:0]),
        .data_in(data_in),

        .data_write_n(data_write_n    | {2{~peri_user[7]}}),
        .data_read_n(data_read_n_peri | {2{~peri_user[7]}}),

        .data_out(data_from_user_peri[7]),
        .data_ready(data_ready_from_user_peri[7]),

        .user_interrupt(user_interrupts[7])
    );

    tqvp_jnms_pdm #(.NUM_GPIO(NUM_GPIO)) i_user_peri08 (
        .clk(clk),
        .rst_n(rst_n_rebuf),

        .ui_in(gpio_in),
        .uo_out(uo_out_from_user_peri[8]),

        .address(addr_in[5:0]),
        .data_in(data_in),

        .data_write_n(data_write_n    | {2{~peri_user[8]}}),
        .data_read_n(data_read_n_peri | {2{~peri_user[8]}}),

        .data_out(data_from_user_peri[8]),
        .data_ready(data_ready_from_user_peri[8]),

        .user_interrupt(user_interrupts[8])
    );

    tqvp_crc_wrapper #(.NUM_GPIO(NUM_GPIO)) i_user_peri09 (
        .clk(clk),
        .rst_n(rst_n_rebuf),

        .ui_in(gpio_in),
        .uo_out(uo_out_from_user_peri[9]),

        .address(addr_in[5:0]),
        .data_in(data_in),

        .data_write_n(data_write_n    | {2{~peri_user[9]}}),
        .data_read_n(data_read_n_peri | {2{~peri_user[9]}}),

        .data_out(data_from_user_peri[9]),
        .data_ready(data_ready_from_user_peri[9]),

        .user_interrupt(user_interrupts[9])
    );

    // --------------------------------------------------------------------- //
    // Byte interface peripherals

    tqvp_spi_peripheral #(.NUM_GPIO(NUM_GPIO)) i_simple_peri16 (
        .clk(clk),
        .rst_n(rst_n_rebuf),

        .ui_in(gpio_in_raw),
        .uo_out(uo_out_from_simple_peri[0]),

        .address(addr_in[3:0]),

        .data_write((data_write_n != 2'b11) & peri_simple[0]),
        .data_in(data_in[7:0]),

        .data_out(data_from_simple_peri[0])
    );

    tqvp_meiniKi_waveforms #(.NUM_GPIO(NUM_GPIO)) i_simple_peri17 (
        .clk(clk),
        .rst_n(rst_n_rebuf),

        .ui_in(gpio_in),
        .uo_out(uo_out_from_simple_peri[1]),

        .address(addr_in[3:0]),

        .data_write((data_write_n != 2'b11) & peri_simple[1]),
        .data_in(data_in[7:0]),

        .data_out(data_from_simple_peri[1])
    );

    tqvp_matt_pwm #(.NUM_GPIO(NUM_GPIO)) matt_pwm (
        .clk(clk),
        .rst_n(rst_n_rebuf),

        .ui_in(gpio_in),
        .uo_out(uo_out_from_simple_peri[2]),

        .address(addr_in[3:0]),

        .data_write((data_write_n != 2'b11) & peri_simple[2]),
        .data_in(data_in[7:0]),

        .data_out(data_from_simple_peri[2])
    );

    tqvp_rejunity_ay8913 #(.NUM_GPIO(NUM_GPIO)) i_simple_peri19(
        .clk(clk),
        .rst_n(rst_n_rebuf),

        .ui_in(gpio_in),
        .uo_out(uo_out_from_simple_peri[3]),

        .address(addr_in[3:0]),

        .data_write((data_write_n != 2'b11) & peri_simple[3]),
        .data_in(data_in[7:0]),

        .data_out(data_from_simple_peri[3])
    );

endmodule
