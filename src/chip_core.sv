// SPDX-FileCopyrightText: © 2025 XXX Authors
// SPDX-License-Identifier: Apache-2.0

`default_nettype none

module chip_core #(
    parameter NUM_BIDIR_PADS
    )(
    `ifdef USE_POWER_PINS
    inout  wire VDD,
    inout  wire VSS,
    `endif
    
    input  wire clk,       // clock
    input  wire rst_n,     // reset (active low)
    
    input  wire [NUM_BIDIR_PADS-1:0] bidir_in,   // Input value
    output wire [NUM_BIDIR_PADS-1:0] bidir_out,  // Output value
    output wire [NUM_BIDIR_PADS-1:0] bidir_oe,   // Output enable
    output wire [NUM_BIDIR_PADS-1:0] bidir_cs,   // Input type (0=CMOS Buffer, 1=Schmitt Trigger)
    output wire [NUM_BIDIR_PADS-1:0] bidir_sl,   // Slew rate (0=fast, 1=slow)
    output wire [NUM_BIDIR_PADS-1:0] bidir_ie,   // Input enable
    output wire [NUM_BIDIR_PADS-1:0] bidir_pu,   // Pull-up
    output wire [NUM_BIDIR_PADS-1:0] bidir_pd    // Pull-down
);

    // See here for usage: https://gf180mcu-pdk.readthedocs.io/en/latest/IPs/IO/gf180mcu_fd_io/digital.html
    assign bidir_cs = '0;
    assign bidir_sl = '0;
    assign bidir_ie = '1;

    tinyQV_top tt(
        .gpio_in(bidir_in[NUM_BIDIR_PADS-1:7]),
        .gpio_out(bidir_out[NUM_BIDIR_PADS-1:7]),
        .gpio_oe(bidir_oe[NUM_BIDIR_PADS-1:7]),
        .gpio_pu(bidir_pu[NUM_BIDIR_PADS-1:7]),
        .gpio_pd(bidir_pd[NUM_BIDIR_PADS-1:7]),
        .qspi_in(bidir_in[6:0]),
        .qspi_out(bidir_out[6:0]),
        .qspi_oe(bidir_oe[6:0]),
        .qspi_pu(bidir_pu[6:0]),
        .qspi_pd(bidir_pd[6:0]),
        .clk(clk),
        .rst_n(rst_n)
    );

endmodule

`default_nettype wire
