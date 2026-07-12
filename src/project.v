/*
 * Copyright (c) 2024 Michael Bell
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tinyQV_top #(
    parameter CLOCK_KHZ=56000,
    parameter NUM_GPIO=6
) (
    input  wire [NUM_GPIO-1:0] gpio_in,
    output wire [NUM_GPIO-1:0] gpio_out,
    output wire [NUM_GPIO-1:0] gpio_oe,
    output wire [NUM_GPIO-1:0] gpio_pu,
    output wire [NUM_GPIO-1:0] gpio_pd,
    input  wire [6:0] qspi_in,
    output wire [6:0] qspi_out,
    output wire [6:0] qspi_oe,
    output wire [6:0] qspi_pu,
    output wire [6:0] qspi_pd,
    input  wire       clk,
    input  wire       rst_n
);

    // Address to peripheral map
    localparam PERI_NONE = 4'h0;
    localparam PERI_ID = 4'h2;
    localparam PERI_TIME_LIMIT = 4'hB;
    localparam PERI_USER = 4'hF;

    // Bidirs are used for SPI interface
    wire [3:0] qspi_data_in = {qspi_in[5:4], qspi_in[2:1]};
    wire [3:0] qspi_data_out;
    wire [3:0] qspi_data_oe;
    wire       qspi_clk_out;
    wire       qspi_flash_select;
    wire       qspi_ram_a_select;
    assign qspi_out = {qspi_ram_a_select, qspi_data_out[3:2], 
                       qspi_clk_out, qspi_data_out[1:0], qspi_flash_select};
    assign qspi_oe = rst_n ? {1'b1, qspi_data_oe[3:2], 1'b1, qspi_data_oe[1:0], 1'b1} : 7'h00;
    assign qspi_pu = 7'b1000011;
    assign qspi_pd = 7'b0110100;

    wire [3:0] qspi_data_in_ctrl;
    reg  [3:0] qspi_config;
    wire [3:0] qspi_data_out_ctrl;
    wire [3:0] qspi_data_oe_ctrl;
    wire       qspi_clk_out_ctrl;
    wire       qspi_flash_select_ctrl;
    wire       qspi_ram_a_select_ctrl;
    wire [3:0] qspi_data_out_setup;
    wire [3:0] qspi_data_oe_setup;
    wire       qspi_clk_out_setup;
    wire       qspi_flash_select_setup;
    wire       qspi_ram_a_select_setup;
    wire       setup_done;
    reg        setup_rst_n;

    wire [27:0] addr;
    wire  [1:0] write_n;
    wire  [1:0] read_n;
    wire        read_complete;
    wire [31:0] data_to_write;

    wire        data_ready;
    reg [31:0] data_from_read;

    reg [3:0] connect_peripheral;

    // Time
    reg [6:2] time_limit;
    wire time_pulse;

    // Peripherals interface
    wire [31:0] peri_data_out;
    wire        peri_data_ready;
    wire [7:2] peri_interrupts;

    // Peripherals get synchronized ui_in.
    reg [NUM_GPIO-1:0] gpio_in_sync0;
    reg [NUM_GPIO-1:0] gpio_in_sync;
    always @(posedge clk) begin
        gpio_in_sync0 <= gpio_in;
        gpio_in_sync <= gpio_in_sync0;
    end

    // Interrupt requests
    wire [7:0] interrupt_req = {peri_interrupts, gpio_in_sync[1:0]};
    // Register the reset on the negative edge of clock for safety.
    // This also allows the option of async reset in the design, which might be preferable in some cases
    always @(negedge clk) setup_rst_n <= rst_n;

    /* verilator lint_off SYNCASYNCNET */
    (* keep *) reg rst_reg_n;
    /* verilator lint_on SYNCASYNCNET */
    always @(negedge clk) rst_reg_n <= rst_n & setup_done;

    always @(posedge clk) begin
        if (!setup_rst_n) begin
            qspi_config <= qspi_data_in;
        end
    end

    assign qspi_data_in_ctrl = rst_reg_n ? qspi_data_in : qspi_config;
    assign qspi_data_out     = rst_reg_n ? qspi_data_out_ctrl : qspi_data_out_setup;
    assign qspi_data_oe      = rst_reg_n ? qspi_data_oe_ctrl  : qspi_data_oe_setup;
    assign qspi_clk_out      = rst_reg_n ? qspi_clk_out_ctrl  : qspi_clk_out_setup;
    assign qspi_flash_select = rst_reg_n ? qspi_flash_select_ctrl : qspi_flash_select_setup;
    assign qspi_ram_a_select = rst_reg_n ? qspi_ram_a_select_ctrl : qspi_ram_a_select_setup;

    qspi_setup i_setup(
        .clk(clk),
        .rstn(setup_rst_n),

        .spi_data_out(qspi_data_out_setup),
        .spi_data_oe(qspi_data_oe_setup),
        .spi_clk_out(qspi_clk_out_setup),
        .spi_flash_select(qspi_flash_select_setup),
        .spi_ram_a_select(qspi_ram_a_select_setup),

        .done(setup_done)
    );

    tinyQV i_tinyqv(
        .clk(clk),
        .rstn(rst_reg_n),

        .data_addr(addr),
        .data_write_n(write_n),
        .data_read_n(read_n),
        .data_read_complete(read_complete),
        .data_out(data_to_write),

        .data_ready(data_ready),
        .data_in(data_from_read),

        .interrupt_req(interrupt_req),
        .time_pulse(time_pulse),

        .spi_data_in(qspi_data_in_ctrl),
        .spi_data_out(qspi_data_out_ctrl),
        .spi_data_oe(qspi_data_oe_ctrl),
        .spi_clk_out(qspi_clk_out_ctrl),
        .spi_flash_select(qspi_flash_select_ctrl),
        .spi_ram_a_select(qspi_ram_a_select_ctrl)
    );

    tinyQV_peripherals #(.CLOCK_KHZ(CLOCK_KHZ), .NUM_GPIO(NUM_GPIO)) i_peripherals (
        .clk(clk),
        .rst_n(rst_reg_n),

        .gpio_in(gpio_in_sync),
        .gpio_in_raw(gpio_in),
        .gpio_out(gpio_out),
        .gpio_oe(gpio_oe),
        .gpio_pu(gpio_pu),
        .gpio_pd(gpio_pd),

        .addr_in(addr[10:0]),
        .data_in(data_to_write),

        .data_write_n(write_n | {2{connect_peripheral != PERI_USER}}),
        .data_read_n(read_n),

        .data_out(peri_data_out),
        .data_ready(peri_data_ready),

        .data_read_complete(read_complete),

        .user_interrupts(peri_interrupts)
    );

    always @(*) begin
        if ({addr[27:6], addr[1:0]} == 24'h800000) 
            connect_peripheral = addr[5:2];
        else if (addr[27:11] == 17'h10000)
            connect_peripheral = PERI_USER;
        else
            connect_peripheral = PERI_NONE;
    end

    // Read data
    always @(*) begin
        case (connect_peripheral)
            PERI_ID:          data_from_read = "WS_2";
            PERI_TIME_LIMIT:  data_from_read = {25'h0, time_limit, 2'b11};
            PERI_USER:        data_from_read = peri_data_out;
            default:          data_from_read = 32'hFFFF_FFFF;
        endcase
    end

    assign data_ready = (connect_peripheral == PERI_USER) ? peri_data_ready : 1'b1;

    always @(posedge clk) begin
        if (!rst_reg_n) begin
            time_limit <= (CLOCK_KHZ / 4000 - 1);
        end
        if (write_n != 2'b11) begin
            if (connect_peripheral == PERI_TIME_LIMIT) time_limit <= data_to_write[6:2];
        end
    end

    reg [6:0] time_count;

    always @(posedge clk) begin
        if (!rst_reg_n) begin
            time_count <= 0;
        end else begin
            if (time_pulse) time_count <= 0;
            else time_count <= time_count + 1;
        end
    end
    assign time_pulse = time_count == {time_limit, 2'b11};

    // List all unused inputs to prevent warnings
    wire _unused = &{qspi_in[6], qspi_in[3], qspi_in[0], read_complete, 1'b0};

endmodule
